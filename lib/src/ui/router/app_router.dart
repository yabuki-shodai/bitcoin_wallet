import 'package:flutter/material.dart';

import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_wallet.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address.dart';
import 'package:bitcoin_wallet/src/ui/pages/bitcoin/address_create_page.dart';
import 'package:bitcoin_wallet/src/ui/pages/bitcoin/bitcoin_page.dart';

class AppRouter {
  static const bitcoin = '/bitcoin';
  static const bitcoinCreate = '/bitcoin/addresses/new';

  static Map<String, WidgetBuilder> routes(BitcoinWallet wallet) => {
    Navigator.defaultRouteName: (_) => BitcoinPage(wallet: wallet),
    bitcoin: (_) => BitcoinPage(wallet: wallet),
  };

  static Route<BitcoinAddress>? createRoute(
    RouteSettings settings,
    BitcoinWallet wallet,
  ) {
    if (settings.name != bitcoinCreate) return null;
    return MaterialPageRoute<BitcoinAddress>(
      settings: settings,
      builder: (_) => AddressCreatePage(
        network: wallet.network,
        onGenerate: wallet.generateAddressOfType,
        onSave: wallet.saveAddress,
      ),
    );
  }
}
