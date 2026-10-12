import 'package:flutter/material.dart';

import '../../../crypto/bitcoin/bitcoin_wallet.dart';
import 'address_delete_page.dart';

class BitcoinMenuPage extends StatelessWidget {
  const BitcoinMenuPage({super.key, required this.wallet});

  final BitcoinWallet wallet;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('メニュー')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('アドレスの削除'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => AddressDeletePage(wallet: wallet),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
