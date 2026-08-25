import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/models/category.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/widgets/topic/category_drawer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCurrentUser extends CurrentUserNotifier {
  @override
  Future<User?> build() async => null;
}

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
];

Future<ProviderContainer> _createContainer({List<String>? pinnedIds}) async {
  SharedPreferences.setMockInitialValues({
    if (pinnedIds != null) 'pinned_category_ids': pinnedIds,
  });
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      categoriesProvider.overrideWith((ref) async => _categories),
      currentUserProvider.overrideWith(_FakeCurrentUser.new),
    ],
  );
}

Widget _wrap(
  ProviderContainer container, {
  required ValueChanged<Category> onSelected,
  required VoidCallback onClose,
}) {
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
        home: Scaffold(
          body: CategoryDrawer(
            onPinnedSelected: onSelected,
            onRequestClose: onClose,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('常用分类为空时仍显示首段和管理入口', (tester) async {
    final container = await _createContainer(pinnedIds: const []);
    addTearDown(container.dispose);
    var closeCount = 0;

    await tester.pumpWidget(
      _wrap(container, onSelected: (_) {}, onClose: () => closeCount++),
    );
    await tester.pumpAndSettle();

    final commonLabel = find.text(S.current.category_myCategories);
    final allLabel = find.text(S.current.category_allCategories);
    expect(commonLabel, findsOneWidget);
    expect(allLabel, findsOneWidget);
    expect(
      tester.getTopLeft(commonLabel).dy,
      lessThan(tester.getTopLeft(allLabel).dy),
    );
    expect(
      find.byKey(const ValueKey('manage-common-categories')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('common-categories-empty')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('common-categories-empty')));
    await tester.pumpAndSettle();

    expect(closeCount, 1);
    expect(find.text(S.current.category_editMyCategories), findsOneWidget);
  });

  testWidgets('常用分类按保存顺序显示，点击后关闭抽屉并选中', (tester) async {
    final container = await _createContainer(pinnedIds: const ['14', '4']);
    addTearDown(container.dispose);
    Category? selected;
    var closeCount = 0;

    await tester.pumpWidget(
      _wrap(
        container,
        onSelected: (category) => selected = category,
        onClose: () => closeCount++,
      ),
    );
    await tester.pumpAndSettle();

    final resource = find.text('资源荟萃').first;
    final develop = find.text('开发调优').first;
    expect(
      tester.getTopLeft(resource).dy,
      lessThan(tester.getTopLeft(develop).dy),
    );

    await tester.tap(resource);
    await tester.pump();

    expect(closeCount, 1);
    expect(selected?.id, 14);
  });
}
