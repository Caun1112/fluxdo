import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_ui/m3e_ui.dart';

import '../../l10n/s.dart';
import '../../models/category.dart';
import '../../providers/category_provider.dart';
import '../../providers/pinned_categories_provider.dart';
import '../../providers/topic_list/filter_provider.dart';
import '../../providers/topic_list/sort_provider.dart';
import '../../providers/topic_list/tab_state_provider.dart';
import 'sort_and_tags_bar.dart' show filterLabel;

/// 首页右下分类/标签 FAB 对应的锚定悬浮面板。
class HomeBrowseQuickPanel extends ConsumerStatefulWidget {
  const HomeBrowseQuickPanel({
    super.key,
    required this.onClose,
    required this.onCategorySelected,
    required this.onEditCategories,
    required this.onEditTags,
  });

  final VoidCallback onClose;
  final ValueChanged<int?> onCategorySelected;
  final VoidCallback onEditCategories;
  final VoidCallback onEditTags;

  @override
  ConsumerState<HomeBrowseQuickPanel> createState() =>
      _HomeBrowseQuickPanelState();
}

class _HomeBrowseQuickPanelState extends ConsumerState<HomeBrowseQuickPanel> {
  bool _showTags = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      key: const ValueKey('home-browse-quick-panel'),
      width: 292,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
            child: Row(
              children: [
                ChoiceChip(
                  label: Text(context.l10n.category_categories),
                  selected: !_showTags,
                  onSelected: (_) => setState(() => _showTags = false),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(context.l10n.tag_tabTags),
                  selected: _showTags,
                  onSelected: (_) => setState(() => _showTags = true),
                  visualDensity: VisualDensity.compact,
                ),
                const Spacer(),
                IconButton(
                  key: const ValueKey('home-quick-panel-edit'),
                  tooltip: context.l10n.common_edit,
                  visualDensity: VisualDensity.compact,
                  onPressed: _showTags
                      ? widget.onEditTags
                      : widget.onEditCategories,
                  icon: Icon(
                    Symbols.edit_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: _showTags ? _buildTags(context) : _buildCategories(context),
          ),
        ],
      ),
    );
  }

  Widget _buildCategories(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentCategoryId = ref.watch(currentTabCategoryIdProvider);
    final pinnedIds = ref.watch(pinnedCategoriesProvider);
    final categoryMapAsync = ref.watch(categoryMapProvider);

    return categoryMapAsync.when(
      loading: () => const Center(
        child: Padding(padding: EdgeInsets.all(24), child: LoadingSpinner()),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(context.l10n.common_loadFailed),
      ),
      data: (categoryMap) {
        final pinned = pinnedIds
            .map((id) => categoryMap[id])
            .whereType<Category>()
            .toList(growable: false);
        return ListView(
          key: const ValueKey('home-common-categories-list'),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
          children: [
            _QuickChoiceTile(
              key: const ValueKey('home-category-all'),
              icon: Symbols.dynamic_feed_rounded,
              label: context.l10n.category_allTopics,
              selected: currentCategoryId == null,
              onTap: () {
                widget.onClose();
                widget.onCategorySelected(null);
              },
            ),
            for (final category in pinned)
              _QuickChoiceTile(
                key: ValueKey('home-category-${category.id}'),
                leading: _CategoryDot(
                  color: _parseCategoryColor(
                    category.color,
                    colorScheme.primary,
                  ),
                ),
                label: category.name,
                selected: currentCategoryId == category.id,
                onTap: () {
                  widget.onClose();
                  widget.onCategorySelected(category.id);
                },
              ),
            if (pinned.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Text(
                  context.l10n.category_editHint,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTags(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final categoryId = ref.watch(currentTabCategoryIdProvider);
    final selectedTags = ref.watch(tabTagsProvider(categoryId));
    final tagsAsync = ref.watch(tagsProvider);

    return tagsAsync.when(
      loading: () => const Center(
        child: Padding(padding: EdgeInsets.all(24), child: LoadingSpinner()),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(context.l10n.common_loadFailed),
      ),
      data: (tags) {
        final commonTags = <String>{...selectedTags, ...tags}.take(10).toList();
        if (commonTags.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              context.l10n.tag_noTags,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          );
        }
        return SingleChildScrollView(
          key: const ValueKey('home-common-tags-list'),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in commonTags)
                FilterChip(
                  key: ValueKey('home-tag-$tag'),
                  label: Text(tag, overflow: TextOverflow.ellipsis),
                  selected: selectedTags.contains(tag),
                  onSelected: (_) {
                    final next = [...selectedTags];
                    if (next.contains(tag)) {
                      next.remove(tag);
                    } else {
                      next.add(tag);
                    }
                    ref.read(tabTagsProvider(categoryId).notifier).state = next;
                  },
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 首页右下范围 FAB 对应的锚定悬浮面板。
class HomeTopicRangeQuickPanel extends ConsumerWidget {
  const HomeTopicRangeQuickPanel({
    super.key,
    required this.isLoggedIn,
    required this.onClose,
    this.onDismissAll,
  });

  final bool isLoggedIn;
  final VoidCallback onClose;
  final VoidCallback? onDismissAll;

  static const _filters = [
    TopicListFilter.latest,
    TopicListFilter.unread,
    TopicListFilter.unseen,
    TopicListFilter.top,
    TopicListFilter.hot,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentFilter = ref.watch(topicFilterProvider);
    final currentOrder = ref.watch(topicSortOrderProvider);
    final ascending = ref.watch(topicSortAscendingProvider);
    final visibleFilters = _filters.where(
      (filter) =>
          isLoggedIn ||
          (filter != TopicListFilter.unread &&
              filter != TopicListFilter.unseen),
    );
    final canDismiss =
        onDismissAll != null &&
        (currentFilter == TopicListFilter.newTopics ||
            currentFilter == TopicListFilter.unread);

    return SizedBox(
      key: const ValueKey('home-topic-range-quick-panel'),
      width: 292,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.topic_filterTooltip(filterLabel(currentFilter)),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final filter in visibleFilters)
                  ChoiceChip(
                    key: ValueKey('home-topic-filter-${filter.name}'),
                    label: Text(filterLabel(filter)),
                    selected: currentFilter == filter,
                    onSelected: (_) {
                      ref.read(topicFilterProvider.notifier).setFilter(filter);
                      onClose();
                    },
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Icon(
                  Symbols.sort_rounded,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.topic_sortTooltip(currentOrder.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                IconButton(
                  key: const ValueKey('home-topic-sort-direction'),
                  tooltip: ascending ? '↑' : '↓',
                  visualDensity: VisualDensity.compact,
                  onPressed: currentOrder == TopicSortOrder.defaultOrder
                      ? null
                      : () => ref
                            .read(topicSortAscendingProvider.notifier)
                            .toggle(),
                  icon: Icon(
                    ascending
                        ? Symbols.arrow_upward_rounded
                        : Symbols.arrow_downward_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              key: const ValueKey('home-topic-sort-options'),
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final order in TopicSortOrder.values)
                  ChoiceChip(
                    key: ValueKey('home-topic-sort-${order.name}'),
                    label: Text(order.label),
                    selected: currentOrder == order,
                    onSelected: (_) => ref
                        .read(topicSortOrderProvider.notifier)
                        .setOrder(order),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (canDismiss) ...[
              const Divider(height: 16),
              TextButton.icon(
                onPressed: () {
                  onClose();
                  onDismissAll?.call();
                },
                icon: const Icon(Symbols.done_all_rounded),
                label: Text(context.l10n.topics_dismiss),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickChoiceTile extends StatelessWidget {
  const _QuickChoiceTile({
    super.key,
    this.icon,
    this.leading,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData? icon;
  final Widget? leading;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      selected: selected,
      selectedTileColor: colorScheme.secondaryContainer,
      leading:
          leading ?? Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: selected
          ? Icon(Symbols.check_rounded, size: 20, color: colorScheme.primary)
          : null,
      onTap: onTap,
    );
  }
}

class _CategoryDot extends StatelessWidget {
  const _CategoryDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const SizedBox(width: 10, height: 10),
        ),
      ),
    );
  }
}

Color _parseCategoryColor(String value, Color fallback) {
  final hex = value.replaceFirst('#', '');
  final parsed = int.tryParse('FF$hex', radix: 16);
  return parsed == null ? fallback : Color(parsed);
}
