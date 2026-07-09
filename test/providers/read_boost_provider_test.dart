import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/read_boost_provider.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ReadBoostNotifier> _createNotifier({
  Map<String, Object> initialValues = const {},
}) async {
  SharedPreferences.setMockInitialValues(initialValues);
  final prefs = await SharedPreferences.getInstance();
  return ReadBoostNotifier(prefs, DiscourseService());
}

void main() {
  test('ReadBoost 默认配置与脚本保持一致', () async {
    final notifier = await _createNotifier();

    final config = notifier.state.config;

    expect(ReadBoostNotifier.maxBatchRetries, 6);
    expect(config.baseDelay, 2500);
    expect(config.randomDelayRange, 800);
    expect(config.minReqSize, 8);
    expect(config.maxReqSize, 20);
    expect(config.minReadTime, 800);
    expect(config.maxReadTime, 3000);
    expect(config.autoStart, false);
    expect(config.startFromCurrent, false);
    expect(config.hasAgreed, false);
  });

  test('ReadBoost 配置会持久化并归一化非法范围', () async {
    final notifier = await _createNotifier();

    await notifier.saveConfig(
      const ReadBoostConfig(
        baseDelay: -1,
        randomDelayRange: -1,
        minReqSize: 30,
        maxReqSize: 10,
        minReadTime: 5000,
        maxReadTime: 1000,
        autoStart: true,
        startFromCurrent: true,
        hasAgreed: true,
      ),
    );

    final reloaded = await _createNotifier(
      initialValues: {
        'read_boost_base_delay': 0,
        'read_boost_random_delay_range': 0,
        'read_boost_min_req_size': 30,
        'read_boost_max_req_size': 30,
        'read_boost_min_read_time': 5000,
        'read_boost_max_read_time': 5000,
        'read_boost_auto_start': true,
        'read_boost_start_from_current': true,
        'read_boost_has_agreed': true,
      },
    );

    expect(notifier.state.config.baseDelay, 0);
    expect(notifier.state.config.randomDelayRange, 0);
    expect(notifier.state.config.minReqSize, 30);
    expect(notifier.state.config.maxReqSize, 30);
    expect(notifier.state.config.minReadTime, 5000);
    expect(notifier.state.config.maxReadTime, 5000);
    expect(reloaded.state.config.autoStart, true);
    expect(reloaded.state.config.startFromCurrent, true);
    expect(reloaded.state.config.hasAgreed, true);
  });

  test('ReadBoost 重置默认值时保留风险确认', () async {
    final notifier = await _createNotifier(
      initialValues: {'read_boost_has_agreed': true},
    );

    await notifier.resetConfig();

    expect(notifier.state.config.hasAgreed, true);
    expect(notifier.state.config.baseDelay, 2500);
    expect(notifier.state.config.minReqSize, 8);
  });
}
