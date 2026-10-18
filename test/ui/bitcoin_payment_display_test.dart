import 'dart:typed_data';

import 'package:bitcoin_wallet/src/core/secure/private_key_store.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_wallet.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/index.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/repository/bitcoin_repository.dart';
import 'package:bitcoin_wallet/src/ui/pages/bitcoin/bitcoin_send_page.dart';
import 'package:bitcoin_wallet/src/ui/widgets/address/address_qr_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repository extends Fake implements BitcoinAddressRepository {}

class _KeyStore extends Fake implements PrivateKeyStore {}

class _Wallet extends BitcoinWallet {
  _Wallet()
    : super(
        network: Network.mainnet,
        repostory: _Repository(),
        store: _KeyStore(),
      );

  final payment = const PreparedBitcoinPayment(
    rawHex: 'signed-transaction',
    txid: 'payment-txid',
    toAddress: 'destination',
    amount: 9800,
    fee: 200,
    virtualSize: 140,
  );
  final sent = <PreparedBitcoinPayment>[];

  @override
  Future<PreparedBitcoinPayment> preparePayment({
    required BitcoinAddress from,
    required String toAddress,
    required String amount,
    required String feeRate,
  }) async => payment;

  @override
  Future<String> sendPayment(PreparedBitcoinPayment payment) async {
    sent.add(payment);
    if (sent.length == 1) throw StateError('connection lost');
    return payment.txid;
  }
}

void main() {
  testWidgets('既存モデルから残高・UTXO・入出金履歴を表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddressQrDialog(
            name: '貯蓄用',
            address: 'address',
            loadBalance: () async => BitcoinBalance(
              total: 10001,
              confirmed: 10000,
              utxos: [
                BitcoinUtxo(
                  txid: 'utxo-txid',
                  vout: 0,
                  value: 1,
                  confirmed: false,
                  scriptPubkey: Uint8List(0),
                ),
              ],
            ),
            loadHistory: () async => const [
              BitcoinHistoryEntry(
                txid: 'incoming',
                balanceChange: 100000001,
                confirmed: true,
              ),
              BitcoinHistoryEntry(
                txid: 'outgoing',
                balanceChange: -6000,
                confirmed: false,
              ),
              BitcoinHistoryEntry(
                txid: 'zero',
                balanceChange: 0,
                confirmed: false,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('残高: 0.00010001 BTC'), findsOneWidget);
    expect(find.text('0.00000001 BTC'), findsOneWidget);
    await tester.ensureVisible(find.text('取引履歴'));
    await tester.tap(find.text('取引履歴'));
    await tester.pumpAndSettle();
    expect(find.text('入金: +1.00000001 BTC'), findsOneWidget);
    expect(find.text('出金: -0.00006000 BTC'), findsOneWidget);
    expect(find.text('残高変化なし: 0.00000000 BTC'), findsOneWidget);
  });

  testWidgets('送金確認を整形し通信失敗後も同じ取引を再送する', (tester) async {
    final wallet = _Wallet();
    addTearDown(wallet.blockchainClient.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BitcoinSendPage(
          from: BitcoinAddress(
            address: 'source',
            network: Network.mainnet,
            publicKey: Uint8List(33),
            type: BitcoinAddressType.p2pkh,
          ),
          wallet: wallet,
        ),
      ),
    );
    await tester.tap(find.text('送金内容を確認'));
    await tester.pumpAndSettle();
    expect(find.text('送金額: 0.00009800 BTC'), findsOneWidget);
    expect(find.text('手数料: 0.00000200 BTC (200 sat)'), findsOneWidget);
    expect(find.text('合計: 0.00010000 BTC'), findsOneWidget);
    expect(find.text('実際の手数料率: 1.43 sat/vB'), findsOneWidget);
    await tester.tap(find.text('確認して送信'));
    await tester.pumpAndSettle();
    expect(
      find.text('https://blockstream.info/tx/payment-txid'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('同じ取引を再送信'));
    await tester.tap(find.text('同じ取引を再送信'));
    await tester.pumpAndSettle();
    expect(find.text('送信完了'), findsOneWidget);
    expect(wallet.sent, [same(wallet.payment), same(wallet.payment)]);
  });
}
