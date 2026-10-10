import 'package:bitcoin_wallet/src/core/secure/private_key_store.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_wallet.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/repository/bitcoin_repository.dart';
import 'package:bitcoin_wallet/src/ui/app.dart';
import 'package:bitcoin_wallet/src/ui/pages/bitcoin/bitcoin_page.dart';
import 'package:bitcoin_wallet/src/ui/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class TestRepository implements BitcoinAddressRepository {
  @override
  Future<List<BitcoinAddress>> getAddresses() async => [];

  @override
  Future<void> saveAddress(BitcoinAddress address) async {}

  @override
  Future<void> deleteAddress(BitcoinAddress address) async {}
}

void main() {
  testWidgets('アプリ起動時と名前付きルートでBitcoinページを開く', (tester) async {
    await tester.pumpWidget(
      App(
        bitcoinWallet: BitcoinWallet(
          network: Network.testnet,
          repostory: TestRepository(),
          store: PrivateKeyStore(asset: 'bitcoin'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BitcoinPage), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    Navigator.of(
      tester.element(find.byType(BitcoinPage)),
    ).pushNamed(AppRouter.bitcoin);
    await tester.pumpAndSettle();
    expect(find.byType(BitcoinPage), findsOneWidget);
    expect(find.text('アドレスがありません'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
