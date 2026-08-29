import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../widgets/category_list_view.dart';

/// Top-level wallet screen with the debit/credit tab pair; the selected tab
/// survives navigation within the session.
class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 40,
        title: const Text('卡包'),
        titleTextStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        bottom: TabBar(
          controller: _tabController,
          indicator: _CapsuleTabIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(text: '借记卡'),
            Tab(text: '信用卡'),
            Tab(text: '证件卡'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _LayeredTab(
            controller: _tabController,
            index: 0,
            child: CategoryListView(cardType: CardType.debit),
          ),
          _LayeredTab(
            controller: _tabController,
            index: 1,
            child: CategoryListView(cardType: CardType.credit),
          ),
          _LayeredTab(
            controller: _tabController,
            index: 2,
            child: CategoryListView(cardType: CardType.document),
          ),
        ],
      ),
    );
  }
}

/// Paints a short rounded capsule below the selected category label.
class _CapsuleTabIndicator extends Decoration {
  const _CapsuleTabIndicator({required this.color});

  final Color color;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _CapsuleTabIndicatorPainter(color);
}

class _CapsuleTabIndicatorPainter extends BoxPainter {
  _CapsuleTabIndicatorPainter(this.color);

  final Color color;

  static const _height = 6.0;
  static const _horizontalInset = 8.0;
  static const _bottomInset = 2.0;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.width <= _horizontalInset * 2) return;
    final rect = Rect.fromLTWH(
      offset.dx + _horizontalInset,
      offset.dy + size.height - _height - _bottomInset,
      size.width - _horizontalInset * 2,
      _height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(_height / 2)),
      Paint()..color = color,
    );
  }
}

class _LayeredTab extends StatelessWidget {
  const _LayeredTab({
    required this.controller,
    required this.index,
    required this.child,
  });

  final TabController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller.animation!,
    builder: (context, _) {
      final distance = (controller.animation!.value - index).abs().clamp(
        0.0,
        1.0,
      );
      return Transform.translate(
        offset: Offset((index - controller.animation!.value) * 10, 0),
        child: Transform.scale(scale: 1 - distance * .018, child: child),
      );
    },
  );
}
