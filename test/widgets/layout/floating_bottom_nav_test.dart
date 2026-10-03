import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/widgets/layout/adaptive_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 悬浮胶囊底栏的几何与选中态回归。
///
/// 几何：默认高 56、图标 24，距屏底 8、靠右留边 12，左侧保留空隙。
void main() {
  const screen = Size(390, 844);
  const safeBottom = 34.0;

  Future<void> pumpBar(
    WidgetTester tester, {
    required bool labelless,
    double textScale = 1.0,
    int count = 5,
    int selectedIndex = 0,
    Size viewport = screen,
    ValueChanged<int>? onSelected,
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'pref_bottom_nav_floating': true,
      'pref_bottom_nav_labelless': labelless,
      'pref_bottom_nav_floating_blur': true,
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: viewport,
              padding: const EdgeInsets.only(bottom: safeBottom),
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              extendBody: true,
              bottomNavigationBar: AdaptiveBottomNavigation(
                selectedIndex: selectedIndex,
                onDestinationSelected: onSelected ?? (_) {},
                destinations: [
                  for (var i = 0; i < count; i++)
                    AdaptiveDestination(
                      id: 'id$i',
                      icon: const Icon(Icons.home_outlined),
                      selectedIcon: const Icon(Icons.home),
                      label: '标签$i',
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 胶囊本体（ClipRRect 是最外层裁切，等于胶囊可见范围）
  RenderBox capsuleOf(WidgetTester tester) =>
      tester.renderObject<RenderBox>(find.byType(ClipRRect).first);

  testWidgets('带字态胶囊高 56，贴屏底 8 / 靠右留边 12', (tester) async {
    await pumpBar(tester, labelless: false);
    final box = capsuleOf(tester);
    expect(box.size.height, 56, reason: 'item 48 + inset 4×2');
    expect(box.size.width, 288, reason: '5 个 56 宽槽位 + inset 4×2');
    final topLeft = box.localToGlobal(Offset.zero);
    expect(topLeft.dx, greaterThanOrEqualTo(screen.width * 0.12));
    expect(screen.width - topLeft.dx - box.size.width, closeTo(12, 0.01));
    expect(topLeft.dx + box.size.width / 2, greaterThan(screen.width / 2));
    expect(
      screen.height - (topLeft.dy + box.size.height),
      safeBottom + 8,
      reason: '安全区之外再让 8（TG 双端一致）',
    );
  });

  testWidgets('无字态胶囊高 56，与带字态保持一致', (tester) async {
    await pumpBar(tester, labelless: true);
    expect(capsuleOf(tester).size.height, 56, reason: 'item 48 + inset 4×2');
  });

  testWidgets('大字号下带字态高度上浮，不裁标签', (tester) async {
    await pumpBar(tester, labelless: false, textScale: 2.0);
    expect(
      capsuleOf(tester).size.height,
      greaterThan(56),
      reason: '标签行高超出基准时补偿高度',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('无字态高度不随字号变化', (tester) async {
    await pumpBar(tester, labelless: true, textScale: 2.0);
    expect(capsuleOf(tester).size.height, 56);
  });

  testWidgets('宽屏不铺满：胶囊宽度受上限约束并靠右', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'pref_bottom_nav_floating': true,
      'pref_bottom_nav_floating_blur': true,
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1200, 900)),
            child: Scaffold(
              extendBody: true,
              bottomNavigationBar: AdaptiveBottomNavigation(
                selectedIndex: 0,
                onDestinationSelected: (_) {},
                destinations: [
                  for (var i = 0; i < 10; i++)
                    AdaptiveDestination(
                      id: 'id$i',
                      icon: const Icon(Icons.home_outlined),
                      selectedIcon: const Icon(Icons.home),
                      label: '标签$i',
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final box = capsuleOf(tester);
    expect(box.size.width, 420, reason: '入口较多时宽屏限制最大宽度');
    final left = box.localToGlobal(Offset.zero).dx;
    expect(left, closeTo(1200 - box.size.width - 12, 0.5), reason: '靠右悬浮');
  });

  testWidgets('选中 pill 铺满整个条目槽位（非 M3 的只包图标短胶囊）', (tester) async {
    const count = 5;
    await pumpBar(tester, labelless: false, count: count);

    final capsule = capsuleOf(tester);
    // pill 是 StadiumBorder 的 DecoratedBox；条目的墨水层也用 StadiumBorder，
    // 这里按尺寸筛出 pill（宽 = 槽宽、高 = item 高）
    final itemHeight = capsule.size.height - 4 * 2;
    final slot = (capsule.size.width - 4 * 2) / count;

    final pill = find.byWidgetPredicate((w) {
      if (w is! DecoratedBox) return false;
      final d = w.decoration;
      return d is ShapeDecoration && d.shape is StadiumBorder;
    });
    expect(pill, findsWidgets);

    final pillBox = tester.renderObject<RenderBox>(pill.first);
    expect(pillBox.size.width, closeTo(slot, 0.5), reason: 'pill 宽 = 槽宽');
    expect(
      pillBox.size.height,
      closeTo(itemHeight, 0.5),
      reason: 'pill 满高铺满条目（含标签），不是只包图标',
    );
  });

  testWidgets('槽宽随 item 高等比缩放：pill 比例恒定 7 / 6', (tester) async {
    final pill = find.byWidgetPredicate((w) {
      if (w is! DecoratedBox) return false;
      final d = w.decoration;
      return d is ShapeDecoration && d.shape is StadiumBorder;
    });

    // 单个入口不触发宽度压缩，可以验证槽位比例。
    await pumpBar(tester, labelless: false, count: 1);
    final labeled = tester.renderObject<RenderBox>(pill.first).size;
    expect(
      labeled.width / labeled.height,
      closeTo(7 / 6, 0.02),
      reason: '带字态槽宽 = item 高 × 7 / 6',
    );

    await pumpBar(tester, labelless: true, count: 1);
    final bare = tester.renderObject<RenderBox>(pill.first).size;
    expect(
      bare.width / bare.height,
      closeTo(7 / 6, 0.02),
      reason: '无字态保持相同的紧凑槽位比例',
    );
    expect(bare, labeled, reason: '默认带字与无字态的槽位大小一致');

    await pumpBar(tester, labelless: false, count: 1, textScale: 2.0);
    final enlarged = tester.renderObject<RenderBox>(pill.first).size;
    expect(enlarged.height, greaterThan(labeled.height));
    expect(
      enlarged.width / enlarged.height,
      closeTo(7 / 6, 0.02),
      reason: '大字号增加高度后，槽宽仍按比例增加',
    );
  });

  for (final labelless in [false, true]) {
    testWidgets('两个入口胶囊为 120×56，图标为 24（无字：$labelless）', (tester) async {
      await pumpBar(tester, labelless: labelless, count: 2);
      final capsule = capsuleOf(tester);
      expect(capsule.size, const Size(120, 56));
      final origin = capsule.localToGlobal(Offset.zero);
      expect(origin.dx + capsule.size.width, closeTo(378, 0.01));
      expect(
        origin.dy + capsule.size.height,
        closeTo(screen.height - safeBottom - 8, 0.01),
      );
      final icons = find.byType(Icon);
      expect(icons, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        expect(tester.getSize(icons.at(i)), const Size(24, 24));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('320 窄屏无溢出且所有按钮可点击（无字：$labelless）', (tester) async {
      final selected = <int>[];
      await pumpBar(
        tester,
        labelless: labelless,
        viewport: const Size(320, 568),
        selectedIndex: -1,
        onSelected: selected.add,
      );
      final box = capsuleOf(tester);
      final origin = box.localToGlobal(Offset.zero);
      expect(origin.dx, greaterThan(12));
      expect(origin.dx + box.size.width, closeTo(308, 0.01));
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byTooltip('标签$i'));
        await tester.pumpAndSettle();
      }
      expect(selected, [0, 1, 2, 3, 4]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('切换选中项时 pill 滑动到新槽位', (tester) async {
    await pumpBar(tester, labelless: false, selectedIndex: 0);
    final pill = find.byWidgetPredicate((w) {
      if (w is! DecoratedBox) return false;
      final d = w.decoration;
      return d is ShapeDecoration && d.shape is StadiumBorder;
    });
    final startX = tester
        .renderObject<RenderBox>(pill.first)
        .localToGlobal(Offset.zero)
        .dx;

    await pumpBar(tester, labelless: false, selectedIndex: 3);
    final endX = tester
        .renderObject<RenderBox>(pill.first)
        .localToGlobal(Offset.zero)
        .dx;

    expect(endX, greaterThan(startX), reason: 'pill 随选中项右移');
  });
}
