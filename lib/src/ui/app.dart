import 'package:flutter/material.dart';

import '../crypto/bitcoin/bitcoin_wallet.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

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
