import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import '../../../l10n/s.dart';
import '../../../models/topic.dart';
import '../../../providers/preferences_provider.dart';
import '../../../widgets/topic/topic_progress.dart';
import 'topic_bottom_bar.dart';
import 'topic_progress_gestures.dart';

/// 话题详情页浮层
/// 包含进度栏、底部操作栏和悬浮回复按钮
class TopicDetailOverlay extends StatelessWidget {
  final bool showBottomBar;
  final bool isLoggedIn;
  final int currentStreamIndex;
  final int totalCount;
  final TopicDetail detail;
  final VoidCallback onScrollToTop;
  final VoidCallback onShare;
  final VoidCallback? onShareAsImage;
  final VoidCallback? onExport;
  final VoidCallback onOpenInBrowser;
  final VoidCallback onReply;
  final bool isReadBoostActive;
  final double? readBoostProgress;
  final VoidCallback onShowReadBoost;
  final VoidCallback onProgressTap;
  final ValueChanged<ProgressGestureAction>? onProgressGesture;
  final bool isSummaryMode;
  final bool isAuthorOnlyMode;
  final bool isTopLevelMode;
  final bool isNestedMode;
  final bool isLoading;
  final VoidCallback? onShowTopReplies;
  final VoidCallback? onShowAuthorOnly;
  final VoidCallback? onShowTopLevelReplies;
  final VoidCallback? onCancelFilter;
  final VoidCallback? onShowNestedView;

  const TopicDetailOverlay({
    super.key,
    required this.showBottomBar,
    required this.isLoggedIn,
    required this.currentStreamIndex,
    required this.totalCount,
    required this.detail,
    required this.onScrollToTop,
    required this.onShare,
    this.onShareAsImage,
    this.onExport,
    required this.onOpenInBrowser,
    required this.onReply,
    required this.isReadBoostActive,
    this.readBoostProgress,
    required this.onShowReadBoost,
    required this.onProgressTap,
    this.onProgressGesture,
    this.isSummaryMode = false,
    this.isAuthorOnlyMode = false,
    this.isTopLevelMode = false,
    this.isNestedMode = false,
    this.isLoading = false,
    this.onShowTopReplies,
    this.onShowAuthorOnly,
    this.onShowTopLevelReplies,
    this.onCancelFilter,
    this.onShowNestedView,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final progressPercent = totalCount > 1
        ? (currentStreamIndex - 1) / (totalCount - 1)
        : 0.0;

    return Stack(
      children: [
        // 固定的进度栏（嵌套模式下隐藏）
        if (!isNestedMode)
          AnimatedPositioned(
            key: const ValueKey('progress_bar'),
            duration: const Duration(milliseconds: 200),
            bottom: showBottomBar ? 96 : 24 + bottomPadding,
            left: 0,
            right: 0,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!showBottomBar) ...[
                    _ReadBoostFloatingButton(
                      isActive: isReadBoostActive,
                      progress: readBoostProgress,
                      onPressed: onShowReadBoost,
                    ),
                    const SizedBox(width: 8),
                  ],
                  TopicProgressGestures(
                    onAction: onProgressGesture ?? (_) {},
                    child: TopicProgress(
                      currentIndex: currentStreamIndex,
                      totalCount: totalCount,
                      progressPercent: progressPercent,
                      onTap: onProgressTap,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (isNestedMode && !showBottomBar)
          AnimatedPositioned(
            key: const ValueKey('read_boost_fab_nested'),
            duration: const Duration(milliseconds: 200),
            left: 0,
            right: 0,
            bottom: 24 + bottomPadding,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ReadBoostFloatingButton(
                    isActive: isReadBoostActive,
                    progress: readBoostProgress,
                    onPressed: onShowReadBoost,
                  ),
                ],
              ),
            ),
          ),
        // 底部操作栏
        AnimatedPositioned(
          key: const ValueKey('bottom_bar'),
          duration: const Duration(milliseconds: 200),
          left: 0,
          right: 0,
          bottom: showBottomBar ? 0 : -80,
          child: TopicBottomBar(
            onScrollToTop: onScrollToTop,
            onShare: onShare,
            onShareAsImage: onShareAsImage,
            onExport: onExport,
            onOpenInBrowser: onOpenInBrowser,
            isReadBoostActive: isReadBoostActive,
            readBoostProgress: readBoostProgress,
            onShowReadBoost: onShowReadBoost,
            hasSummary: detail.hasSummary,
            isSummaryMode: isSummaryMode,
            isAuthorOnlyMode: isAuthorOnlyMode,
            isTopLevelMode: isTopLevelMode,
            isNestedMode: isNestedMode,
            isLoading: isLoading,
            isPrivateMessage: detail.isPrivateMessage,
            onShowTopReplies: onShowTopReplies,
            onShowAuthorOnly: onShowAuthorOnly,
            onShowTopLevelReplies: onShowTopLevelReplies,
            onCancelFilter: onCancelFilter,
            onShowNestedView: onShowNestedView,
          ),
        ),
        // 悬浮回复按钮
        if (isLoggedIn)
          AnimatedPositioned(
            key: const ValueKey('fab_reply'),
            duration: const Duration(milliseconds: 200),
            right: 16,
            bottom: showBottomBar
                ? bottomPadding + (80 - bottomPadding - 56) / 2
                : 16 + bottomPadding,
            child: FloatingActionButton(
              heroTag: 'replyTopic',
              onPressed: onReply,
              child: const Icon(Symbols.reply_rounded),
            ),
          ),
      ],
    );
  }
}

class _ReadBoostFloatingButton extends StatelessWidget {
  final bool isActive;
  final double? progress;
  final VoidCallback onPressed;

  const _ReadBoostFloatingButton({
    required this.isActive,
    required this.progress,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progressValue = progress?.clamp(0.0, 1.0).toDouble();
    final hasProgress = progressValue != null;
    final progressLabel = progressValue == null
        ? null
        : '${(progressValue * 100).round()}%';

    return Tooltip(
      message: context.l10n.topicDetail_readBoost,
      child: Material(
        elevation: 4,
        shadowColor: Colors.black26,
        color: isActive
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surface,
        shape: hasProgress
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))
            : const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: hasProgress
              ? SizedBox(
                  width: 84,
                  height: 40,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isActive
                              ? Symbols.stop_circle_rounded
                              : Symbols.rocket_launch_rounded,
                          size: 20,
                          color: isActive
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          progressLabel!,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: isActive
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : SizedBox.square(
                  dimension: 40,
                  child: Icon(
                    isActive
                        ? Symbols.stop_circle_rounded
                        : Symbols.rocket_launch_rounded,
                    color: isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
      ),
    );
  }
}
