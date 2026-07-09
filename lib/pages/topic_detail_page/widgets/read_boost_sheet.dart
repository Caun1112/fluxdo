import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_icons/app_icons.dart';

import '../../../l10n/s.dart';
import '../../../providers/read_boost_provider.dart';
import '../../../services/toast_service.dart';

class ReadBoostSheet extends ConsumerStatefulWidget {
  final ReadBoostTopicInfo topicInfo;

  const ReadBoostSheet({super.key, required this.topicInfo});

  @override
  ConsumerState<ReadBoostSheet> createState() => _ReadBoostSheetState();
}

class _ReadBoostSheetState extends ConsumerState<ReadBoostSheet> {
  late final TextEditingController _baseDelayController;
  late final TextEditingController _randomDelayRangeController;
  late final TextEditingController _minReqSizeController;
  late final TextEditingController _maxReqSizeController;
  late final TextEditingController _minReadTimeController;
  late final TextEditingController _maxReadTimeController;
  bool _autoStart = false;
  bool _startFromCurrent = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(readBoostProvider).config;
    _baseDelayController = TextEditingController(
      text: config.baseDelay.toString(),
    );
    _randomDelayRangeController = TextEditingController(
      text: config.randomDelayRange.toString(),
    );
    _minReqSizeController = TextEditingController(
      text: config.minReqSize.toString(),
    );
    _maxReqSizeController = TextEditingController(
      text: config.maxReqSize.toString(),
    );
    _minReadTimeController = TextEditingController(
      text: config.minReadTime.toString(),
    );
    _maxReadTimeController = TextEditingController(
      text: config.maxReadTime.toString(),
    );
    _autoStart = config.autoStart;
    _startFromCurrent = config.startFromCurrent;
  }

  @override
  void dispose() {
    _baseDelayController.dispose();
    _randomDelayRangeController.dispose();
    _minReqSizeController.dispose();
    _maxReqSizeController.dispose();
    _minReadTimeController.dispose();
    _maxReadTimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readBoostProvider);
    final config = state.config;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Symbols.rocket_launch_rounded),
          const SizedBox(width: 8),
          Text(context.l10n.topicDetail_readBoost),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusCard(state: state),
              const SizedBox(height: 12),
              if (!config.hasAgreed) _buildRiskCard(context, theme),
              if (config.hasAgreed) ...[
                _buildSwitches(context),
                const SizedBox(height: 12),
                _buildNumberGrid(context),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (config.hasAgreed)
          TextButton(
            onPressed: state.isRunning ? null : _resetConfig,
            child: Text(context.l10n.readBoost_resetDefaults),
          ),
        if (config.hasAgreed)
          TextButton(
            onPressed: state.isRunning ? null : _saveConfig,
            child: Text(context.l10n.readBoost_saveSettings),
          ),
        if (!config.hasAgreed)
          FilledButton(
            onPressed: () => ref.read(readBoostProvider.notifier).acceptRisk(),
            child: Text(context.l10n.readBoost_acceptRisk),
          )
        else if (state.isRunning)
          FilledButton.tonal(
            onPressed: () => ref.read(readBoostProvider.notifier).stop(),
            child: Text(context.l10n.readBoost_stop),
          )
        else
          FilledButton(
            onPressed: _start,
            child: Text(context.l10n.readBoost_start),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.common_close),
        ),
      ],
    );
  }

  Widget _buildRiskCard(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        context.l10n.readBoost_riskWarning,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }

  Widget _buildSwitches(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _autoStart,
          title: Text(context.l10n.readBoost_autoStart),
          onChanged: (value) => setState(() => _autoStart = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _startFromCurrent,
          title: Text(context.l10n.readBoost_startFromCurrent),
          subtitle: Text(
            context.l10n.readBoost_currentPosition(
              widget.topicInfo.currentPosition,
              widget.topicInfo.totalReplies,
            ),
          ),
          onChanged: (value) => setState(() => _startFromCurrent = value),
        ),
      ],
    );
  }

  Widget _buildNumberGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 420;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildNumberField(
              context,
              controller: _baseDelayController,
              label: context.l10n.readBoost_baseDelay,
              twoColumns: twoColumns,
            ),
            _buildNumberField(
              context,
              controller: _randomDelayRangeController,
              label: context.l10n.readBoost_randomDelayRange,
              twoColumns: twoColumns,
            ),
            _buildNumberField(
              context,
              controller: _minReqSizeController,
              label: context.l10n.readBoost_minReqSize,
              twoColumns: twoColumns,
            ),
            _buildNumberField(
              context,
              controller: _maxReqSizeController,
              label: context.l10n.readBoost_maxReqSize,
              twoColumns: twoColumns,
            ),
            _buildNumberField(
              context,
              controller: _minReadTimeController,
              label: context.l10n.readBoost_minReadTime,
              twoColumns: twoColumns,
            ),
            _buildNumberField(
              context,
              controller: _maxReadTimeController,
              label: context.l10n.readBoost_maxReadTime,
              twoColumns: twoColumns,
            ),
          ],
        );
      },
    );
  }

  Widget _buildNumberField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required bool twoColumns,
  }) {
    return SizedBox(
      width: twoColumns ? 250 : double.infinity,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Future<void> _saveConfig() async {
    final current = ref.read(readBoostProvider).config;
    final next = current.copyWith(
      baseDelay: _readInt(_baseDelayController, current.baseDelay),
      randomDelayRange: _readInt(
        _randomDelayRangeController,
        current.randomDelayRange,
      ),
      minReqSize: _readInt(_minReqSizeController, current.minReqSize),
      maxReqSize: _readInt(_maxReqSizeController, current.maxReqSize),
      minReadTime: _readInt(_minReadTimeController, current.minReadTime),
      maxReadTime: _readInt(_maxReadTimeController, current.maxReadTime),
      autoStart: _autoStart,
      startFromCurrent: _startFromCurrent,
    );
    await ref.read(readBoostProvider.notifier).saveConfig(next);
    if (mounted) {
      ToastService.showSuccess(context.l10n.readBoost_settingsSaved);
    }
  }

  Future<void> _resetConfig() async {
    await ref.read(readBoostProvider.notifier).resetConfig();
    final config = ref.read(readBoostProvider).config;
    _baseDelayController.text = config.baseDelay.toString();
    _randomDelayRangeController.text = config.randomDelayRange.toString();
    _minReqSizeController.text = config.minReqSize.toString();
    _maxReqSizeController.text = config.maxReqSize.toString();
    _minReadTimeController.text = config.minReadTime.toString();
    _maxReadTimeController.text = config.maxReadTime.toString();
    setState(() {
      _autoStart = config.autoStart;
      _startFromCurrent = config.startFromCurrent;
    });
  }

  Future<void> _start() async {
    await _saveConfig();
    await ref.read(readBoostProvider.notifier).start(widget.topicInfo);
  }

  int _readInt(TextEditingController controller, int fallback) {
    return int.tryParse(controller.text.trim()) ?? fallback;
  }
}

class _StatusCard extends StatelessWidget {
  final ReadBoostState state;

  const _StatusCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(state.message, style: theme.textTheme.titleSmall),
          if (state.progress != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: state.progress),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 8),
            Text(
              state.error.toString(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
