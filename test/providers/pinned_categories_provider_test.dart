import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/pinned_categories_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<({SharedPreferences prefs, PinnedCategoriesNotifier notifier})>
_createNotifier({Map<String, Object> initialValues = const {}}) async {
  SharedPreferences.setMockInitialValues(initialValues);
  final prefs = await SharedPreferences.getInstance();
  return (prefs: prefs, notifier: PinnedCategoriesNotifier(prefs));
}

void main() {
  test('首次使用时写入去重后的默认常用分类', () async {
    final (:prefs, :notifier) = await _createNotifier();

    notifier.seedIfUnset([4, 14, 34, 36, 14]);

    expect(notifier.state, [4, 14, 34, 36]);
    expect(prefs.getStringList('pinned_category_ids'), ['4', '14', '34', '36']);
  });

  test('用户主动删空后不会再次自动回填', () async {
    final (:prefs, :notifier) = await _createNotifier(
      initialValues: {'pinned_category_ids': <String>[]},
    );

    notifier.seedIfUnset([4, 14, 34, 36]);

    expect(notifier.state, isEmpty);
    expect(prefs.containsKey('pinned_category_ids'), isTrue);
  });

  test('添加删除排序会持久化并可在重建后恢复', () async {
    final (:prefs, :notifier) = await _createNotifier(
      initialValues: {
        'pinned_category_ids': ['4', '14'],
      },
    );

    notifier
      ..add(34)
      ..add(34)
      ..remove(14)
      ..reorder(1, 0);

    expect(notifier.state, [34, 4]);
    expect(PinnedCategoriesNotifier(prefs).state, [34, 4]);
  });
}
