import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/discourse/discourse_service.dart';
import 'core_providers.dart';
import 'theme_provider.dart';

enum ReadBoostStatus { idle, running, stopping, completed, failed }

class ReadBoostConfig {
  final int baseDelay;
  final int randomDelayRange;
  final int minReqSize;
  final int maxReqSize;
  final int minReadTime;
  final int maxReadTime;
  final bool autoStart;
  final bool startFromCurrent;
  final bool hasAgreed;

  const ReadBoostConfig({
    this.baseDelay = 2500,
    this.randomDelayRange = 800,
    this.minReqSize = 8,
    this.maxReqSize = 20,
    this.minReadTime = 800,
    this.maxReadTime = 3000,
    this.autoStart = false,
    this.startFromCurrent = false,
    this.hasAgreed = false,
  });

  ReadBoostConfig copyWith({
    int? baseDelay,
    int? randomDelayRange,
    int? minReqSize,
    int? maxReqSize,
    int? minReadTime,
    int? maxReadTime,
    bool? autoStart,
    bool? startFromCurrent,
    bool? hasAgreed,
  }) {
    return ReadBoostConfig(
      baseDelay: baseDelay ?? this.baseDelay,
      randomDelayRange: randomDelayRange ?? this.randomDelayRange,
      minReqSize: minReqSize ?? this.minReqSize,
      maxReqSize: maxReqSize ?? this.maxReqSize,
      minReadTime: minReadTime ?? this.minReadTime,
      maxReadTime: maxReadTime ?? this.maxReadTime,
      autoStart: autoStart ?? this.autoStart,
      startFromCurrent: startFromCurrent ?? this.startFromCurrent,
      hasAgreed: hasAgreed ?? this.hasAgreed,
    ).normalized();
  }

  ReadBoostConfig normalized() {
    final normalizedMinReq = minReqSize.clamp(1, 200).toInt();
    final normalizedMaxReq = maxReqSize.clamp(normalizedMinReq, 300).toInt();
    final normalizedMinRead = minReadTime.clamp(100, 60000).toInt();
    final normalizedMaxRead = maxReadTime
        .clamp(normalizedMinRead, 120000)
        .toInt();
    return ReadBoostConfig(
      baseDelay: baseDelay.clamp(0, 600000).toInt(),
      randomDelayRange: randomDelayRange.clamp(0, 600000).toInt(),
      minReqSize: normalizedMinReq,
      maxReqSize: normalizedMaxReq,
      minReadTime: normalizedMinRead,
      maxReadTime: normalizedMaxRead,
      autoStart: autoStart,
      startFromCurrent: startFromCurrent,
      hasAgreed: hasAgreed,
    );
  }

  static const defaults = ReadBoostConfig();
}

class ReadBoostState {
  final ReadBoostConfig config;
  final ReadBoostStatus status;
  final String message;
  final int? topicId;
  final int currentPosition;
  final int totalReplies;
  final int processedEnd;
  final Object? error;

  const ReadBoostState({
    required this.config,
    this.status = ReadBoostStatus.idle,
    this.message = 'ReadBoost',
    this.topicId,
    this.currentPosition = 0,
    this.totalReplies = 0,
    this.processedEnd = 0,
    this.error,
  });

  bool get isRunning =>
      status == ReadBoostStatus.running || status == ReadBoostStatus.stopping;

  double? get progress {
    if (totalReplies <= 0 || processedEnd <= 0) return null;
    return (processedEnd / totalReplies).clamp(0.0, 1.0);
  }

  ReadBoostState copyWith({
    ReadBoostConfig? config,
    ReadBoostStatus? status,
    String? message,
    int? topicId,
    int? currentPosition,
    int? totalReplies,
    int? processedEnd,
    Object? error,
    bool clearTopicId = false,
    bool clearError = false,
  }) {
    return ReadBoostState(
      config: config ?? this.config,
      status: status ?? this.status,
      message: message ?? this.message,
      topicId: clearTopicId ? null : topicId ?? this.topicId,
      currentPosition: currentPosition ?? this.currentPosition,
      totalReplies: totalReplies ?? this.totalReplies,
      processedEnd: processedEnd ?? this.processedEnd,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class ReadBoostTopicInfo {
  final int topicId;
  final int currentPosition;
  final int totalReplies;

  const ReadBoostTopicInfo({
    required this.topicId,
    required this.currentPosition,
    required this.totalReplies,
  });
}

class ReadBoostNotifier extends StateNotifier<ReadBoostState> {
  static const int maxBatchRetries = 6;

  static const _baseDelayKey = 'read_boost_base_delay';
  static const _randomDelayRangeKey = 'read_boost_random_delay_range';
  static const _minReqSizeKey = 'read_boost_min_req_size';
  static const _maxReqSizeKey = 'read_boost_max_req_size';
  static const _minReadTimeKey = 'read_boost_min_read_time';
  static const _maxReadTimeKey = 'read_boost_max_read_time';
  static const _autoStartKey = 'read_boost_auto_start';
  static const _startFromCurrentKey = 'read_boost_start_from_current';
  static const _hasAgreedKey = 'read_boost_has_agreed';

  final SharedPreferences _prefs;
  final DiscourseService _service;
  final Random _random;
  bool _shouldStop = false;

  ReadBoostNotifier(this._prefs, this._service, {Random? random})
    : _random = random ?? Random(),
      super(ReadBoostState(config: _loadConfig(_prefs)));

  static ReadBoostConfig _loadConfig(SharedPreferences prefs) {
    return ReadBoostConfig(
      baseDelay:
          prefs.getInt(_baseDelayKey) ?? ReadBoostConfig.defaults.baseDelay,
      randomDelayRange:
          prefs.getInt(_randomDelayRangeKey) ??
          ReadBoostConfig.defaults.randomDelayRange,
      minReqSize:
          prefs.getInt(_minReqSizeKey) ?? ReadBoostConfig.defaults.minReqSize,
      maxReqSize:
          prefs.getInt(_maxReqSizeKey) ?? ReadBoostConfig.defaults.maxReqSize,
      minReadTime:
          prefs.getInt(_minReadTimeKey) ?? ReadBoostConfig.defaults.minReadTime,
      maxReadTime:
          prefs.getInt(_maxReadTimeKey) ?? ReadBoostConfig.defaults.maxReadTime,
      autoStart:
          prefs.getBool(_autoStartKey) ?? ReadBoostConfig.defaults.autoStart,
      startFromCurrent:
          prefs.getBool(_startFromCurrentKey) ??
          ReadBoostConfig.defaults.startFromCurrent,
      hasAgreed:
          prefs.getBool(_hasAgreedKey) ?? ReadBoostConfig.defaults.hasAgreed,
    ).normalized();
  }

  Future<void> saveConfig(ReadBoostConfig config) async {
    final normalized = config.normalized();
    await Future.wait([
      _prefs.setInt(_baseDelayKey, normalized.baseDelay),
      _prefs.setInt(_randomDelayRangeKey, normalized.randomDelayRange),
      _prefs.setInt(_minReqSizeKey, normalized.minReqSize),
      _prefs.setInt(_maxReqSizeKey, normalized.maxReqSize),
      _prefs.setInt(_minReadTimeKey, normalized.minReadTime),
      _prefs.setInt(_maxReadTimeKey, normalized.maxReadTime),
      _prefs.setBool(_autoStartKey, normalized.autoStart),
      _prefs.setBool(_startFromCurrentKey, normalized.startFromCurrent),
      _prefs.setBool(_hasAgreedKey, normalized.hasAgreed),
    ]);
    state = state.copyWith(config: normalized, clearError: true);
  }

  Future<void> acceptRisk() async {
    await saveConfig(state.config.copyWith(hasAgreed: true));
  }

  Future<void> resetConfig() {
    return saveConfig(
      ReadBoostConfig.defaults.copyWith(hasAgreed: state.config.hasAgreed),
    );
  }

  void stop() {
    if (!state.isRunning) return;
    _shouldStop = true;
    state = state.copyWith(
      status: ReadBoostStatus.stopping,
      message: '正在停止...',
    );
  }

  Future<void> start(ReadBoostTopicInfo info) async {
    if (state.isRunning) {
      state = state.copyWith(message: 'ReadBoost 正在运行中');
      return;
    }

    if (!state.config.hasAgreed) {
      state = state.copyWith(
        status: ReadBoostStatus.failed,
        message: '请先确认 ReadBoost 风险提示',
      );
      return;
    }

    if (info.totalReplies <= 0) {
      state = state.copyWith(
        status: ReadBoostStatus.failed,
        message: '当前帖子没有可处理的楼层',
      );
      return;
    }

    final loggedIn = await _service.isLoggedIn();
    if (!loggedIn) {
      state = state.copyWith(
        status: ReadBoostStatus.failed,
        message: '请先登录后再使用 ReadBoost',
      );
      return;
    }

    _shouldStop = false;
    final config = state.config.normalized();
    final startPosition = config.startFromCurrent
        ? info.currentPosition.clamp(1, info.totalReplies).toInt()
        : 1;

    state = state.copyWith(
      status: ReadBoostStatus.running,
      message: '正在启动...',
      topicId: info.topicId,
      currentPosition: startPosition,
      totalReplies: info.totalReplies,
      processedEnd: startPosition - 1,
      clearError: true,
    );

    try {
      var cursor = startPosition;
      while (cursor <= info.totalReplies) {
        _throwIfStopped();
        final batchSize = _randomInt(config.minReqSize, config.maxReqSize);
        final start = cursor;
        final end = min(cursor + batchSize - 1, info.totalReplies);
        await _sendBatchWithRetry(
          topicId: info.topicId,
          start: start,
          end: end,
          totalReplies: info.totalReplies,
          config: config,
        );
        cursor = end + 1;
      }

      state = state.copyWith(
        status: ReadBoostStatus.completed,
        message: 'ReadBoost 处理完成',
        processedEnd: info.totalReplies,
      );
    } on _ReadBoostStopped {
      state = state.copyWith(
        status: ReadBoostStatus.idle,
        message: 'ReadBoost 已停止',
      );
    } catch (error) {
      state = state.copyWith(
        status: ReadBoostStatus.failed,
        message: 'ReadBoost 执行失败',
        error: error,
      );
    } finally {
      _shouldStop = false;
    }
  }

  Future<void> _sendBatchWithRetry({
    required int topicId,
    required int start,
    required int end,
    required int totalReplies,
    required ReadBoostConfig config,
    int retryCount = maxBatchRetries,
  }) async {
    _throwIfStopped();

    final timings = <int, int>{};
    for (var i = start; i <= end; i++) {
      timings[i] = _randomInt(config.minReadTime, config.maxReadTime);
    }

    final count = end - start + 1;
    final topicTime = _randomInt(
      config.minReadTime * count,
      config.maxReadTime * count,
    );

    final statusCode = await _service.topicsTimings(
      topicId: topicId,
      topicTime: topicTime,
      timings: timings,
      logContext: {
        'readBoost': true,
        'readBoostStart': start,
        'readBoostEnd': end,
      },
    );

    _throwIfStopped();

    if (statusCode == null || statusCode >= 400) {
      if (retryCount > 0) {
        state = state.copyWith(
          status: ReadBoostStatus.running,
          message: '重试 $start-$end，剩余 $retryCount 次',
        );
        await _delayCheckingStop(const Duration(seconds: 2));
        return _sendBatchWithRetry(
          topicId: topicId,
          start: start,
          end: end,
          totalReplies: totalReplies,
          config: config,
          retryCount: retryCount - 1,
        );
      }
      throw StateError('HTTP ${statusCode ?? 'unknown'}');
    }

    state = state.copyWith(
      status: ReadBoostStatus.running,
      message: '处理回复 $start-$end (${(end / totalReplies * 100).round()}%)',
      processedEnd: end,
    );

    final delay = Duration(
      milliseconds: config.baseDelay + _randomInt(0, config.randomDelayRange),
    );
    await _delayCheckingStop(delay);
  }

  Future<void> _delayCheckingStop(Duration delay) async {
    var remaining = delay.inMilliseconds;
    while (remaining > 0) {
      _throwIfStopped();
      final step = min(100, remaining);
      await Future<void>.delayed(Duration(milliseconds: step));
      remaining -= step;
    }
  }

  int _randomInt(int minValue, int maxValue) {
    if (maxValue <= minValue) return minValue;
    return minValue + _random.nextInt(maxValue - minValue + 1);
  }

  void _throwIfStopped() {
    if (_shouldStop) throw const _ReadBoostStopped();
  }
}

class _ReadBoostStopped implements Exception {
  const _ReadBoostStopped();
}

final readBoostProvider =
    StateNotifierProvider<ReadBoostNotifier, ReadBoostState>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider);
      final service = ref.watch(discourseServiceProvider);
      return ReadBoostNotifier(prefs, service);
    });
