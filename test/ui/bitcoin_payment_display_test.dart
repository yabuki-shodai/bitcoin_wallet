import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_transaction_serializer.dart';
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

  final payment = BitcoinTransaction(
    inputs: [
      TxInput(
        utxo: BitcoinUtxo(
          txid: '22' * 32,
          vout: 0,
          value: 10000,
          confirmed: true,
          scriptPubkey: Uint8List.fromList([0x51]),
        ),
        scriptSig: [1],
      ),
    ],
    outputs: [
      TxOutput(value: 9800, scriptPubKey: Uint8List.fromList([0x51])),
    ],
  );
  final sent = <BitcoinTransaction>[];

  @override
  Future<BitcoinTransaction> preparePayment({
    required BitcoinAddress from,
    required String toAddress,
    required String amount,
    required String feeRate,
  }) async => payment;

  @override
  Future<String> sendPayment(BitcoinTransaction payment) async {
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
            loadUtxos: () async => [
              BitcoinUtxo(
                txid: 'confirmed-txid',
                vout: 0,
                value: 10000,
                confirmed: true,
                scriptPubkey: Uint8List(0),
              ),
              BitcoinUtxo(
                txid: 'unconfirmed-txid',
                vout: 1,
                value: 1,
                confirmed: false,
                scriptPubkey: Uint8List(0),
              ),
            ],
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
    expect(find.text('0.00010000 BTC'), findsOneWidget);
    expect(find.text('0.00000001 BTC'), findsOneWidget);
    expect(find.text('承認済み'), findsOneWidget);
    expect(find.text('未承認'), findsOneWidget);
    await tester.ensureVisible(find.text('取引履歴'));
    await tester.tap(find.text('取引履歴'));
    await tester.pumpAndSettle();
    expect(find.text('入金: +1.00000001 BTC'), findsOneWidget);
    expect(find.text('出金: -0.00006000 BTC'), findsOneWidget);
    expect(find.text('残高変化なし: 0.00000000 BTC'), findsOneWidget);
  });

  testWidgets('取得失敗後にUTXOを再取得し空なら残高ゼロを表示する', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddressQrDialog(
            name: '貯蓄用',
            address: 'address',
            loadUtxos: () async {
              calls++;
              if (calls == 1) throw StateError('connection lost');
              return [];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('残高を取得できませんでした。'), findsOneWidget);
    await tester.tap(find.text('残高を再取得'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('残高: 0.00000000 BTC'), findsOneWidget);
    expect(find.text('UTXOはありません'), findsOneWidget);
    expect(find.text('残高を取得できませんでした。'), findsNothing);
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
    await tester.enterText(
      find.byKey(const Key('send-address')),
      ' destination ',
    );
    await tester.enterText(
      find.byKey(const Key('send-amount')),
      ' 0.00009800 ',
    );
    await tester.tap(find.text('送金内容を確認'));
    await tester.pumpAndSettle();
    expect(find.text('送金額: 0.00009800 BTC'), findsOneWidget);
    expect(find.text('手数料: 0.00000200 BTC (200 sat)'), findsOneWidget);
    expect(find.text('合計: 0.00010000 BTC'), findsOneWidget);
    expect(find.text('destination'), findsOneWidget);
    expect(find.text('実際の手数料率: 3.23 sat/vB'), findsOneWidget);
    await tester.tap(find.text('確認して送信'));
    await tester.pumpAndSettle();
    expect(
      find.text('https://blockstream.info/tx/${wallet.payment.txid}'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('同じ取引を再送信'));
    await tester.tap(find.text('同じ取引を再送信'));
    await tester.pumpAndSettle();
    expect(find.text('送信完了'), findsOneWidget);
    expect(wallet.sent, [same(wallet.payment), same(wallet.payment)]);
  });
}
