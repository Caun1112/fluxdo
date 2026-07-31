import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '_cli_ui.dart';
import '_workspace_cli.dart';

final _cliUi = CliUi();

Future<void> main(List<String> args) async {
  enterWorkspaceRoot();

  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    return;
  }

  final yes = args.contains('--yes') || args.contains('-y');
  final trollStoreLite = args.contains('--trollstore-lite');
  final filteredArgs = args
      .where(
        (arg) => arg != '--yes' && arg != '-y' && arg != '--trollstore-lite',
      )
      .toList(growable: false);

  if (!Platform.isMacOS) {
    stderr.writeln('iOS 无签名 IPA 只能在 macOS 上打包');
    exit(64);
  }

  final version = await _resolveVersion(filteredArgs);
  if (version.isEmpty) {
    stderr.writeln('无法确定版本号');
    exit(1);
  }

  if (!yes &&
      (await _cliUi.confirm(
            prompt: '确认构建 iOS 无签名 IPA ($version)?',
            defaultValue: true,
          ) !=
          true)) {
    stdout.writeln('==> 已取消');
    return;
  }

  final ipaDir = Directory('build/ios/ipa')..createSync(recursive: true);
  final compatibilitySuffix = trollStoreLite ? '-trollstore-lite' : '';
  final ipaPath = p.join(
    ipaDir.path,
    'fluxdo-$version$compatibilitySuffix-nosign.ipa',
  );

  stdout.writeln('==> 构建 iOS 无签名 IPA ($version)');
  await runOrExit(
    title: '构建 iOS 应用',
    executable: Platform.resolvedExecutable,
    arguments: const ['tool/flutterw.dart', 'build', 'ios', '--release', '--no-codesign'],
  );

  final runnerApp = Directory('build/ios/iphoneos/Runner.app');
  if (!runnerApp.existsSync()) {
    stderr.writeln('缺少构建产物: ${runnerApp.path}');
    exit(1);
  }

  final tempDir = await Directory.systemTemp.createTemp('fluxdo_ipa_');
  try {
    final payloadDir = Directory(p.join(tempDir.path, 'Payload'))..createSync(recursive: true);
    final packagedRunner = Directory(p.join(payloadDir.path, 'Runner.app'));
    await _copyDirectory(runnerApp, packagedRunner);
    if (trollStoreLite) {
      await _prepareTrollStoreLiteNativeAssets(packagedRunner, tempDir);
    }

    final ipaFile = File(ipaPath);
    if (ipaFile.existsSync()) {
      ipaFile.deleteSync();
    }

    await runOrExit(
      title: '打包 IPA',
      executable: 'zip',
      arguments: ['-qr', ipaFile.absolute.path, 'Payload'],
      workingDirectory: tempDir.path,
    );
  } finally {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }

  stdout.writeln('==> IPA 已输出: $ipaPath');
}

Future<void> _prepareTrollStoreLiteNativeAssets(
  Directory runnerApp,
  Directory tempDir,
) async {
  final frameworksDir = Directory(p.join(runnerApp.path, 'Frameworks'));
  final manifestFile = File(
    p.join(
      frameworksDir.path,
      'App.framework',
      'flutter_assets',
      'NativeAssetsManifest.json',
    ),
  );
  if (!manifestFile.existsSync()) {
    stdout.writeln('==> 未发现 Flutter native-assets，无需应用 TrollStore Lite 兼容处理');
    return;
  }

  final manifest = jsonDecode(await manifestFile.readAsString());
  if (manifest is! Map || manifest['native-assets'] is! Map) {
    stderr.writeln('NativeAssetsManifest.json 格式无效');
    exit(1);
  }

  final signingTargets = <String>{};
  final nativeAssets = manifest['native-assets'] as Map;
  for (final platformAssets in nativeAssets.values.whereType<Map>()) {
    for (final location in platformAssets.values.whereType<List>()) {
      if (location.length < 2 ||
          location.first != 'absolute' ||
          location[1] is! String) {
        continue;
      }

      final relativePath = location[1] as String;
      final segments = p.posix.split(relativePath);
      if (p.posix.isAbsolute(relativePath) ||
          segments.isEmpty ||
          segments.contains('..')) {
        stderr.writeln('native-assets 路径无效: $relativePath');
        exit(1);
      }

      final frameworkIndex = segments.indexWhere(
        (segment) => segment.endsWith('.framework'),
      );
      final targetSegments = frameworkIndex >= 0
          ? segments.take(frameworkIndex + 1)
          : segments;
      final targetPath = p.normalize(
        p.joinAll([frameworksDir.path, ...targetSegments]),
      );
      if (!p.isWithin(frameworksDir.absolute.path, p.absolute(targetPath)) ||
          !FileSystemEntity.isFileSync(targetPath) &&
              !FileSystemEntity.isDirectorySync(targetPath)) {
        stderr.writeln('native-assets 签名目标不存在: $relativePath');
        exit(1);
      }
      signingTargets.add(targetPath);
    }
  }

  if (signingTargets.isEmpty) {
    stdout.writeln('==> 未发现需要兼容处理的 Flutter native-assets');
    return;
  }

  // TrollStore Lite 会在安装时以 merge 模式递归重签，保留这里写入的
  // PMAP_CS 信任级别；否则运行时 dlopen 的 native-assets 会被 dyld 拒绝。
  final entitlementsFile = File(
    p.join(tempDir.path, 'trollstore_lite_native_assets.entitlements'),
  );
  await entitlementsFile.writeAsString(_trollStoreLiteNativeAssetEntitlements);

  for (final targetPath in signingTargets.toList()..sort()) {
    await runOrExit(
      title: '处理 TrollStore Lite 原生库 ${p.basename(targetPath)}',
      executable: '/usr/bin/codesign',
      arguments: [
        '--force',
        '--sign',
        '-',
        '--entitlements',
        entitlementsFile.path,
        '--force-library-entitlements',
        '--generate-entitlement-der',
        targetPath,
      ],
    );
    await runOrExit(
      title: '验证原生库签名 ${p.basename(targetPath)}',
      executable: '/usr/bin/codesign',
      arguments: ['--verify', '--strict', '--verbose=2', targetPath],
    );

    final verifiedEntitlements = File(
      p.join(tempDir.path, '${p.basename(targetPath)}.entitlements.plist'),
    );
    final dumpResult = await Process.run('/usr/bin/codesign', [
      '--display',
      '--entitlements',
      verifiedEntitlements.path,
      '--xml',
      targetPath,
    ]);
    final trustResult = dumpResult.exitCode == 0
        ? await Process.run('/usr/bin/plutil', [
            '-extract',
            r'jb\.pmap_cs\.custom_trust',
            'raw',
            '-o',
            '-',
            verifiedEntitlements.path,
          ])
        : null;
    if (trustResult?.exitCode != 0 ||
        (trustResult?.stdout as String?)?.trim() != 'PMAP_CS_APP_STORE') {
      stderr.writeln('原生库信任 entitlement 校验失败: $targetPath');
      exit(1);
    }
  }
}

Future<String> _resolveVersion(List<String> args) async {
  if (args.isNotEmpty) {
    return args.first.trim();
  }

  final pubspecVersion = _readVersionFromPubspec();
  if (!_cliUi.canPrompt) {
    return pubspecVersion;
  }

  final selected = await _cliUi.input(
    prompt: '输入 iOS 无签名 IPA 版本号',
    defaultValue: pubspecVersion,
  );
  return selected?.trim() ?? '';
}

String _readVersionFromPubspec() {
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    return '';
  }
  final match = RegExp(r'^version:\s*(.+)$', multiLine: true).firstMatch(
    pubspecFile.readAsStringSync(),
  );
  return match?.group(1)?.split('+').first.trim() ?? '';
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  destination.createSync(recursive: true);
  await for (final entity in source.list(recursive: false, followLinks: false)) {
    final targetPath = p.join(destination.path, p.basename(entity.path));
    if (entity is Directory) {
      await _copyDirectory(entity, Directory(targetPath));
    } else if (entity is File) {
      File(targetPath).parent.createSync(recursive: true);
      await entity.copy(targetPath);
    }
  }
}

const _usage = '''
用法:
  dart tool/build_ipa_nosign.dart [版本号] [-y|--yes] [--trollstore-lite]
''';

const _trollStoreLiteNativeAssetEntitlements = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>jb.pmap_cs.custom_trust</key>
  <string>PMAP_CS_APP_STORE</string>
</dict>
</plist>
''';
