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
          CategoryListView(cardType: CardType.debit),
          CategoryListView(cardType: CardType.credit),
          CategoryListView(cardType: CardType.document),
        ],
      ),
    );
  }
}
