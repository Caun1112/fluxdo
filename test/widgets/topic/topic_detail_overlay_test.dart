import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/topic_detail_overlay.dart';
import 'package:fluxdo/services/local_notification_service.dart';

TopicDetail _detail() {
  return TopicDetail(
    id: 1,
    title: '测试话题',
    slug: 'test-topic',
    postsCount: 1,
    postStream: PostStream(posts: const [], stream: const [1]),
    categoryId: 1,
    closed: false,
    archived: false,
  );
}

Widget _wrap(Widget child) {
  return TranslationProvider(
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorKey: navigatorKey,
      supportedLocales: AppLocaleUtils.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 390,
            height: 844,
            child: Stack(fit: StackFit.expand, children: [child]),
          ),
        ),
      ),
    ),
  );
}

TopicDetailOverlay _overlay({VoidCallback? onBack, bool isLoggedIn = true}) {
  return TopicDetailOverlay(
    showBottomBarListenable: ValueNotifier(false),
    isLoggedIn: isLoggedIn,
    streamIndexListenable: ValueNotifier(1),
    totalCount: 1,
    detail: _detail(),
    onScrollToTop: () {},
    onShare: () {},
    onOpenInBrowser: () {},
    onBack: onBack,
    onReply: () {},
    isReadBoostActive: false,
    onShowReadBoost: () {},
    onProgressTap: () {},
    isNestedMode: true,
  );
}

void main() {
  testWidgets('手机端返回和回复 FAB 同尺寸且返回位于回复上方', (tester) async {
    await tester.pumpWidget(_wrap(_overlay(onBack: () {})));
    await tester.pumpAndSettle();

    final back = find.byKey(const ValueKey('fab_back'));
    final reply = find.byKey(const ValueKey('fab_reply'));
    expect(back, findsOneWidget);
    expect(reply, findsOneWidget);
    expect(tester.getSize(back), const Size(56, 56));
    expect(tester.getSize(reply), const Size(56, 56));
    expect(tester.getTopLeft(back).dy, lessThan(tester.getTopLeft(reply).dy));
    expect(tester.getTopLeft(reply).dy - tester.getTopLeft(back).dy, 68);
    final overlayBottom = tester
        .getRect(find.byType(TopicDetailOverlay))
        .bottom;
    expect(overlayBottom - tester.getBottomRight(reply).dy, 132);
  });

  testWidgets('未登录时仍显示返回 FAB，但不显示回复 FAB', (tester) async {
    await tester.pumpWidget(_wrap(_overlay(onBack: () {}, isLoggedIn: false)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('fab_back')), findsOneWidget);
    expect(find.byKey(const ValueKey('fab_reply')), findsNothing);
  });
}
