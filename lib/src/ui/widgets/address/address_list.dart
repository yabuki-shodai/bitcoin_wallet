import 'package:flutter/material.dart';

import 'package:bitcoin_wallet/src/ui/widgets/address/address_empty_state.dart';

class AddressList extends StatelessWidget {
  const AddressList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) return const AddressEmptyState();

    return ListView.separated(
      padding: const EdgeInsets.only(top: 8, bottom: 88),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      separatorBuilder: (_, _) => const Divider(indent: 20, endIndent: 20),
    );
  }
}
