import 'package:flutter/material.dart';

import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_wallet.dart';
import 'package:bitcoin_wallet/src/ui/router/app_router.dart';
import 'package:bitcoin_wallet/src/ui/theme/app_theme.dart';

class App extends StatelessWidget {
  const App({super.key, required this.bitcoinWallet});

  final BitcoinWallet bitcoinWallet;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '暗号資産ウォレット',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routes: AppRouter.routes(bitcoinWallet),
      onGenerateRoute: (settings) =>
          AppRouter.createRoute(settings, bitcoinWallet),
    );
  }
}
