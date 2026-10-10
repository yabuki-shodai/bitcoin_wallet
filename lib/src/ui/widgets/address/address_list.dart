import 'package:flutter/material.dart';

import 'address_empty_state.dart';

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
      padding: EdgeInsets.zero,
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      separatorBuilder: (_, _) => const Divider(indent: 20, endIndent: 20),
    );
  }
}
