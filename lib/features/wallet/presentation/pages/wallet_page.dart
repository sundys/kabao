import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../widgets/category_list_view.dart';

/// Wallet screen with a centered, swipeable three-tab selector.
class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  static const _tabLabels = ['借记卡', '信用卡', '证件卡'];
  static const _tabTypes = [CardType.debit, CardType.credit, CardType.document];
  static const _pageCount = 1000000;

  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    const middlePage = _pageCount ~/ 2;
    _pageController = PageController(
      initialPage: middlePage - (middlePage % _tabLabels.length),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int _logicalIndex(int page) => page % _tabLabels.length;

  void _onPageChanged(int page) {
    final logical = _logicalIndex(page);
    if (logical != _currentIndex && mounted) {
      setState(() => _currentIndex = logical);
    }
  }

  void _selectTab(int targetIndex) {
    final page = _pageController.page?.round() ?? (_pageCount ~/ 2);
    final current = _logicalIndex(page);
    var delta = (targetIndex - current) % _tabLabels.length;
    if (delta == 2) delta = -1;
    _pageController.animateToPage(
      page + delta,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: Material(
          color: theme.colorScheme.surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 51,
                child: _CenteredTabHeader(
                  labels: _tabLabels,
                  selectedIndex: _currentIndex,
                  onSelected: _selectTab,
                ),
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: .45),
              ),
            ],
          ),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: _pageCount,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, page) {
          final type = _tabTypes[_logicalIndex(page)];
          return CategoryListView(key: ValueKey(type), cardType: type);
        },
      ),
    );
  }
}

class _CenteredTabHeader extends StatelessWidget {
  const _CenteredTabHeader({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedColor = theme.colorScheme.primary;
    final sideColor = theme.colorScheme.onSurfaceVariant;
    // Reorder the repeating sequence around the focused tab so the selected
    // label is physically centered for every logical page (including debit
    // and document, where a static [debit, credit, document] row would place
    // the focus at an edge).
    final displayIndices = [
      (selectedIndex + labels.length - 1) % labels.length,
      selectedIndex,
      (selectedIndex + 1) % labels.length,
    ];
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final index in displayIndices) ...[
            if (index != displayIndices.first) const SizedBox(width: 18),
            _TabLabel(
              label: labels[index],
              selected: index == selectedIndex,
              selectedColor: selectedColor,
              sideColor: sideColor,
              onTap: () => onSelected(index),
            ),
          ],
        ],
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.sideColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final Color sideColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: selected ? selectedColor : sideColor.withValues(alpha: .55),
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          child: selected
              ? text
              : ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 1.2, sigmaY: 1.2),
                  child: text,
                ),
        ),
      ),
    );
  }
}
