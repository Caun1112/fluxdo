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
  final filteredArgs = args
      .where((arg) => arg != '--yes' && arg != '-y')
      .toList(growable: false);

  if (!Platform.isMacOS) {
    stderr.writeln('iOS 无签名 IPA 只能在 macOS 上打包');
    exit(64);
  }

  final version = yes && filteredArgs.isEmpty
      ? _readVersionFromPubspec()
      : await _resolveVersion(filteredArgs);
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
  final ipaPath = p.join(ipaDir.path, 'fluxdo-$version-nosign.ipa');

  stdout.writeln('==> 构建 iOS 无签名 IPA ($version)');
  await runOrExit(
    title: '构建 iOS 应用',
    executable: Platform.resolvedExecutable,
    arguments: const [
      'tool/flutterw.dart',
      'build',
      'ios',
      '--release',
      '--no-codesign',
    ],
  );

  final runnerApp = Directory('build/ios/iphoneos/Runner.app');
  if (!runnerApp.existsSync()) {
    stderr.writeln('缺少构建产物: ${runnerApp.path}');
    exit(1);
  }

  final tempDir = await Directory.systemTemp.createTemp('fluxdo_ipa_');
  try {
    final payloadDir = Directory(p.join(tempDir.path, 'Payload'))
      ..createSync(recursive: true);
    final packagedRunner = Directory(p.join(payloadDir.path, 'Runner.app'));
    await _copyDirectory(runnerApp, packagedRunner);
    await _normalizeNativeAssetFrameworks(packagedRunner);

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

/// 把 Flutter native-assets 的 Framework 归一化成「thin arm64 + 完全未签名」。
///
/// Flutter 会给 native-assets 打上 adhoc 签名并保留 FAT(单 arm64 切片)外壳，
/// 而 CocoaPods 插件 Framework 是 thin 且完全未签名的。侧载工具在安装时会对
/// 整个 bundle 统一重签，预置的 adhoc 签名反而让这些库在运行时 dlopen 被
/// AMFI 判为 code signature invalid，表现为启动后一直白屏。这里把它们对齐到
/// 与其它插件 Framework 一致的形态，交给安装侧统一签名。
Future<void> _normalizeNativeAssetFrameworks(Directory runnerApp) async {
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
    stdout.writeln('==> 未发现 Flutter native-assets，跳过归一化');
    return;
  }

  final manifest = jsonDecode(await manifestFile.readAsString());
  if (manifest is! Map || manifest['native-assets'] is! Map) {
    stderr.writeln('NativeAssetsManifest.json 格式无效');
    exit(1);
  }

  // 二进制路径 -> 所属 .framework 目录(没有则为 null)。
  final targets = <String, String?>{};
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

      final binaryPath = p.normalize(
        p.joinAll([frameworksDir.path, ...segments]),
      );
      if (!p.isWithin(frameworksDir.absolute.path, p.absolute(binaryPath)) ||
          !FileSystemEntity.isFileSync(binaryPath)) {
        stderr.writeln('native-assets 目标不存在: $relativePath');
        exit(1);
      }

      final frameworkIndex = segments.indexWhere(
        (segment) => segment.endsWith('.framework'),
      );
      targets[binaryPath] = frameworkIndex >= 0
          ? p.normalize(
              p.joinAll([
                frameworksDir.path,
                ...segments.take(frameworkIndex + 1),
              ]),
            )
          : null;
    }
  }

  if (targets.isEmpty) {
    stdout.writeln('==> 未发现需要归一化的 Flutter native-assets');
    return;
  }

  for (final binaryPath in targets.keys.toList()..sort()) {
    final name = p.basename(binaryPath);

    // 1. FAT(单 arm64 切片)外壳剥成 thin，与其它插件 Framework 一致。
    if (await _isFatBinary(binaryPath)) {
      final thinPath = '$binaryPath.thin';
      await runOrExit(
        title: '剥离 FAT 外壳 $name',
        executable: '/usr/bin/lipo',
        arguments: ['-thin', 'arm64', binaryPath, '-output', thinPath],
      );
      File(thinPath).renameSync(binaryPath);
    }

    // 2. 去掉 Flutter 预置的 adhoc 签名，交给侧载工具统一重签。
    await runOrExit(
      title: '移除预置签名 $name',
      executable: '/usr/bin/codesign',
      arguments: ['--remove-signature', binaryPath],
    );

    // 3. 清掉残留的 bundle 签名封装目录。
    final frameworkDir = targets[binaryPath];
    if (frameworkDir != null) {
      final codeSignatureDir = Directory(
        p.join(frameworkDir, '_CodeSignature'),
      );
      if (codeSignatureDir.existsSync()) {
        codeSignatureDir.deleteSync(recursive: true);
      }
    }

    // 4. 校验结果确实是 thin 且未签名，避免再次产出白屏包。
    if (await _isFatBinary(binaryPath)) {
      stderr.writeln('归一化失败，仍是 FAT 二进制: $binaryPath');
      exit(1);
    }
    final verify = await Process.run('/usr/bin/codesign', ['-dv', binaryPath]);
    if (!'${verify.stderr}'.contains('not signed at all')) {
      stderr.writeln('归一化失败，签名未移除: $binaryPath');
      exit(1);
    }
    stdout.writeln('==> 已归一化 native-assets: $name');
  }
}

Future<bool> _isFatBinary(String path) async {
  final result = await Process.run('/usr/bin/lipo', ['-info', path]);
  return result.exitCode == 0 &&
      '${result.stdout}'.contains('Architectures in the fat file');
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
  final match = RegExp(
    r'^version:\s*(.+)$',
    multiLine: true,
  ).firstMatch(pubspecFile.readAsStringSync());
  return match?.group(1)?.split('+').first.trim() ?? '';
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  destination.createSync(recursive: true);
  await for (final entity in source.list(
    recursive: false,
    followLinks: false,
  )) {
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
  dart tool/build_ipa_nosign.dart [版本号] [-y|--yes]
''';
