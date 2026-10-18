import 'package:flutter/material.dart';

import 'package:bitcoin_wallet/src/core/secure/private_key_store.dart';
import 'package:bitcoin_wallet/src/core/storage/hive_initializer.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_wallet.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/repository/bitcoin_repository.dart';
import 'package:bitcoin_wallet/src/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveInitializer.init();
  final repository = await BitcoinAddressRepositoryImpl.open();
  runApp(
    App(
      bitcoinWallet: BitcoinWallet(
        network: Network.testnet,
        repostory: repository,
        store: PrivateKeyStore(asset: 'bitcoin'),
      ),
    ),
  );
}
