import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/models/category.dart';
import 'package:fluxdo/pages/topics_page.dart';
import 'package:fluxdo/pages/topics_screen.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/providers/topic_list/filter_provider.dart';
import 'package:fluxdo/providers/topic_list/tab_state_provider.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _categories = [
  Category(
    id: 4,
    name: '开发调优',
    color: '336699',
    textColor: 'FFFFFF',
    slug: 'develop',
  ),
  Category(
    id: 14,
    name: '资源荟萃',
    color: '669933',
    textColor: 'FFFFFF',
    slug: 'resource',
  ),
  Category(
    id: 34,
    name: '前沿快讯',
    color: '993366',
    textColor: 'FFFFFF',
    slug: 'news',
  ),
];

Future<ProviderContainer> _createContainer({required bool showRefresh}) async {
  SharedPreferences.setMockInitialValues({
    'pinned_category_ids': ['4', '14'],
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      categoriesProvider.overrideWith((ref) async => _categories),
      tagsProvider.overrideWith((ref) async => ['flutter', 'ios', 'dart']),
    ],
  );
  container.read(fabRefreshModeProvider.notifier).state = showRefresh;
  return container;
}

Widget _wrap(ProviderContainer container, TopicsFloatingActions actions) {
  return UncontrolledProviderScope(
    container: container,
    child: TranslationProvider(
      child: MaterialApp(
        navigatorKey: navigatorKey,
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

TopicsFloatingActions _actions({
  bool isLoggedIn = true,
  ValueChanged<int?>? onCategorySelected,
}) {
  return TopicsFloatingActions(
    isLoggedIn: isLoggedIn,
    onCategorySelected: onCategorySelected ?? (_) {},
    onEditCategories: () {},
    onEditTags: () {},
    onDismissAll: () {},
    onCreateTopic: isLoggedIn ? () {} : null,
    onOpenDrafts: isLoggedIn ? () {} : null,
  );
}

void main() {
  testWidgets('范围、分类、刷新按钮垂直排列，尺寸和颜色一致', (tester) async {
    final container = await _createContainer(showRefresh: true);
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container, _actions()));
    await tester.pumpAndSettle();

    final range = find.byKey(const ValueKey('topics-range-fab'));
    final category = find.byKey(const ValueKey('topics-category-fab'));
    final primary = find.byKey(const ValueKey('topics-primary-fab'));
    expect(range, findsOneWidget);
    expect(category, findsOneWidget);
    expect(primary, findsOneWidget);
    expect(tester.getSize(range), const Size(56, 56));
    expect(tester.getSize(category), const Size(56, 56));
    expect(tester.getSize(primary), const Size(56, 56));
    expect(tester.getCenter(range).dx, tester.getCenter(category).dx);
    expect(tester.getCenter(category).dx, tester.getCenter(primary).dx);
    expect(tester.getTopLeft(category).dy - tester.getBottomLeft(range).dy, 12);
    expect(
      tester.getTopLeft(primary).dy - tester.getBottomLeft(category).dy,
      12,
    );

    final rangeFab = tester.widget<FloatingActionButton>(range);
    final categoryFab = tester.widget<FloatingActionButton>(category);
    final primaryFab = tester.widget<FloatingActionButton>(primary);
    expect(rangeFab.backgroundColor, primaryFab.backgroundColor);
    expect(categoryFab.backgroundColor, primaryFab.backgroundColor);
    expect(rangeFab.foregroundColor, primaryFab.foregroundColor);
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
  });

  testWidgets('分类按钮弹出上方悬浮面板，只展示常用分类', (tester) async {
    final container = await _createContainer(showRefresh: true);
    addTearDown(container.dispose);
    int? selectedCategory;

    await tester.pumpWidget(
      _wrap(
        container,
        _actions(onCategorySelected: (id) => selectedCategory = id),
      ),
    );
    await tester.pumpAndSettle();

    final category = find.byKey(const ValueKey('topics-category-fab'));
    await tester.tap(category);
    await tester.pumpAndSettle();

    final panel = find.byKey(const ValueKey('home-browse-quick-panel'));
    expect(panel, findsOneWidget);
    expect(
      tester.getRect(panel).bottom,
      lessThan(tester.getRect(category).top),
    );
    expect(find.text('开发调优'), findsOneWidget);
    expect(find.text('资源荟萃'), findsOneWidget);
    expect(find.text('前沿快讯'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('home-category-14')));
    await tester.pumpAndSettle();
    expect(selectedCategory, 14);
    expect(panel, findsNothing);
  });

  testWidgets('范围按钮弹出五项悬浮选择并更新筛选', (tester) async {
    final container = await _createContainer(showRefresh: true);
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container, _actions()));
    await tester.pumpAndSettle();

    final range = find.byKey(const ValueKey('topics-range-fab'));
    await tester.tap(range);
    await tester.pumpAndSettle();

    final panel = find.byKey(const ValueKey('home-topic-range-quick-panel'));
    expect(panel, findsOneWidget);
    expect(tester.getRect(panel).bottom, lessThan(tester.getRect(range).top));
    for (final filter in [
      TopicListFilter.latest,
      TopicListFilter.unread,
      TopicListFilter.unseen,
      TopicListFilter.top,
      TopicListFilter.hot,
    ]) {
      expect(
        find.byKey(ValueKey('home-topic-filter-${filter.name}')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey('home-topic-filter-newTopics')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('home-topic-sort-dropdown')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('home-topic-filter-hot')));
    await tester.pumpAndSettle();
    expect(container.read(topicFilterProvider), TopicListFilter.hot);
    expect(panel, findsNothing);
  });

  testWidgets('标签页展示热门标签并可直接切换', (tester) async {
    final container = await _createContainer(showRefresh: true);
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container, _actions()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('topics-category-fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.current.tag_tabTags));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-common-tags-list')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-tag-flutter')));
    await tester.pump();
    expect(container.read(tabTagsProvider(null)), ['flutter']);
  });

  testWidgets('短横屏时悬浮面板自动放到按钮左侧，避免越出屏幕', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final container = await _createContainer(showRefresh: true);
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container, _actions()));
    await tester.pumpAndSettle();
    final range = find.byKey(const ValueKey('topics-range-fab'));
    await tester.tap(range);
    await tester.pumpAndSettle();

    final panel = find.byKey(const ValueKey('home-topic-range-quick-panel'));
    expect(tester.getRect(panel).right, lessThan(tester.getRect(range).left));
  });

  testWidgets('游客仍显示范围和分类入口，但不显示发帖主按钮', (tester) async {
    final container = await _createContainer(showRefresh: false);
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container, _actions(isLoggedIn: false)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('topics-range-fab')), findsOneWidget);
    expect(find.byKey(const ValueKey('topics-category-fab')), findsOneWidget);
    expect(find.byKey(const ValueKey('topics-primary-fab')), findsNothing);
  });

  testWidgets('展开新建菜单时两个筛选按钮均不可点击', (tester) async {
    final container = await _createContainer(showRefresh: false);
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container, _actions()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('topics-primary-fab')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('topics-category-fab')).hitTestable(),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('topics-range-fab')).hitTestable(),
      findsNothing,
    );
  });
}
