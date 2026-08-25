import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/pages/topics_page.dart';
import 'package:fluxdo/pages/topics_screen.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _createContainer({required bool showRefresh}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  container.read(fabRefreshModeProvider.notifier).state = showRefresh;
  return container;
}

Widget _wrap(ProviderContainer container, TopicsFloatingActions actions) {
  return UncontrolledProviderScope(
    container: container,
    child: TranslationProvider(
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocaleUtils.supportedLocales,
        home: Scaffold(floatingActionButton: actions),
      ),
    ),
  );
}

void main() {
  testWidgets('分类按钮位于刷新按钮上方，尺寸和颜色一致', (tester) async {
    final container = await _createContainer(showRefresh: true);
    addTearDown(container.dispose);
    var categoryTapCount = 0;

    await tester.pumpWidget(
      _wrap(
        container,
        TopicsFloatingActions(
          onOpenCategories: () => categoryTapCount++,
          onCreateTopic: () {},
          onOpenDrafts: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final category = find.byKey(const ValueKey('topics-category-fab'));
    final primary = find.byKey(const ValueKey('topics-primary-fab'));
    expect(category, findsOneWidget);
    expect(primary, findsOneWidget);
    expect(tester.getSize(category), const Size(56, 56));
    expect(tester.getSize(primary), const Size(56, 56));
    expect(tester.getCenter(category).dx, tester.getCenter(primary).dx);
    expect(
      tester.getTopLeft(primary).dy - tester.getBottomLeft(category).dy,
      12,
    );

    final categoryFab = tester.widget<FloatingActionButton>(category);
    final primaryFab = tester.widget<FloatingActionButton>(primary);
    expect(categoryFab.backgroundColor, primaryFab.backgroundColor);
    expect(categoryFab.foregroundColor, primaryFab.foregroundColor);

    final categoryIcon = find.descendant(
      of: category,
      matching: find.byIcon(Symbols.category_rounded),
    );
    final refreshIcon = find.descendant(
      of: primary,
      matching: find.byIcon(Symbols.refresh_rounded),
    );
    expect(
      IconTheme.of(tester.element(categoryIcon)).color,
      IconTheme.of(tester.element(refreshIcon)).color,
    );

    await tester.tap(category);
    expect(categoryTapCount, 1);
  });

  testWidgets('游客仍显示分类入口，但不显示发帖主按钮', (tester) async {
    final container = await _createContainer(showRefresh: false);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _wrap(container, TopicsFloatingActions(onOpenCategories: () {})),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('topics-category-fab')), findsOneWidget);
    expect(find.byKey(const ValueKey('topics-primary-fab')), findsNothing);
  });

  testWidgets('展开新建菜单时分类按钮不可点击，避免与子按钮重叠', (tester) async {
    final container = await _createContainer(showRefresh: false);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _wrap(
        container,
        TopicsFloatingActions(
          onOpenCategories: () {},
          onCreateTopic: () {},
          onOpenDrafts: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('topics-primary-fab')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('topics-category-fab')).hitTestable(),
      findsNothing,
    );
  });
}
