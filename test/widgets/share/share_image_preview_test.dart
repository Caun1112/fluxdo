import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/widgets/share/share_image_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';

Post _post() {
  final now = DateTime(2026, 8, 26);
  return Post(
    id: 1,
    username: 'tester',
    avatarTemplate: '',
    cooked: '<p>测试正文</p>',
    postNumber: 1,
    postType: 1,
    updatedAt: now,
    createdAt: now,
    likeCount: 0,
    replyCount: 0,
  );
}

TopicDetail _detail(Post post) {
  return TopicDetail(
    id: 1,
    title: '测试话题',
    slug: 'test-topic',
    postsCount: 1,
    postStream: PostStream(posts: [post], stream: const [1]),
    categoryId: 1,
    closed: false,
    archived: false,
  );
}

Future<Widget> _buildPreview() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final post = _post();
  return ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
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
          body: ShareImagePreview(detail: _detail(post), post: post),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('底部操作顺序为分享、保存到相册、复制', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(await _buildPreview());
    await tester.pumpAndSettle();

    final share = find.byKey(const ValueKey('share-image-share-action'));
    final save = find.byKey(const ValueKey('share-image-save-action'));
    final copy = find.byKey(const ValueKey('share-image-copy-action'));
    expect(share, findsOneWidget);
    expect(save, findsOneWidget);
    expect(copy, findsOneWidget);
    expect(tester.getCenter(share).dx, lessThan(tester.getCenter(save).dx));
    expect(tester.getCenter(save).dx, lessThan(tester.getCenter(copy).dx));
    expect(tester.widget(share), isA<FilledButton>());
    expect(tester.widget(copy), isA<OutlinedButton>());
  });
}
