import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bitcoin_wallet/src/core/secure/private_key_store.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_blockchain_client.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_payments.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_wallet.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address_type.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/repository/bitcoin_repository.dart';
import 'package:bitcoin_wallet/src/ui/app.dart';
import 'package:bitcoin_wallet/src/ui/widgets/address/address_list_tile.dart';
import 'package:bitcoin_wallet/src/ui/widgets/address/address_qr_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const addressText = 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx';
final address = BitcoinAddress(
  displayName: '普段使い',
  address: addressText,
  network: Network.testnet,
  publicKey: Uint8List(33),
  type: BitcoinAddressType.p2wpkh,
);

class MemoryKeys extends PrivateKeyStore {
  MemoryKeys() : super(asset: 'bitcoin');
  bool missing = false;
  @override
  Future<Uint8List?> readPrivateKey(String address) async =>
      missing ? null : (Uint8List(32)..[31] = 1);
}

class MemoryAddresses implements BitcoinAddressRepository {
  @override
  Future<List<BitcoinAddress>> getAddresses() async => [address];
  @override
  Future<void> saveAddress(BitcoinAddress address) async {}
  @override
  Future<void> deleteAddress(BitcoinAddress address) async {}
}

class RecordingWallet extends BitcoinWallet {
  RecordingWallet(BitcoinBlockchainClient client, MemoryKeys keys)
    : super(
        network: Network.testnet,
        repostory: MemoryAddresses(),
        store: keys,
        blockchainClient: client,
      );
  PreparedBitcoinPayment? prepared;
  int preparations = 0;
  @override
  Future<PreparedBitcoinPayment> preparePayment({
    required BitcoinAddress from,
    required String toAddress,
    required int amount,
    required int feeRate,
  }) async {
    preparations++;
    return prepared = await super.preparePayment(
      from: from,
      toAddress: toAddress,
      amount: amount,
      feeRate: feeRate,
    );
  }
}

class Fixture {
  late final RecordingWallet wallet;
  final keys = MemoryKeys();
  final posts = <String>[];
  int balanceRequests = 0;
  bool failBalance = false;
  bool failSend = false;
  bool spent = false;
  Completer<http.Response>? gate;

  Fixture() {
    wallet = RecordingWallet(
      BitcoinBlockchainClient(
        network: Network.testnet,
        client: MockClient((request) async {
          if (request.method == 'POST') {
            posts.add(request.body);
            if (gate != null) return gate!.future;
            if (failSend) return http.Response('rejected', 400);
            spent = true;
            return http.Response(wallet.prepared!.txid, 200);
          }
          if (request.url.path.endsWith('/utxo')) {
            balanceRequests++;
            if (failBalance) return http.Response('unavailable', 503);
            return http.Response(
              jsonEncode(
                spent
                    ? []
                    : [
                        {
                          'txid': '11' * 32,
                          'vout': 0,
                          'value': 10000,
                          'status': {'confirmed': true},
                        },
                        {
                          'txid': '22' * 32,
                          'vout': 0,
                          'value': 2000,
                          'status': {'confirmed': false},
                        },
                      ],
              ),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'vout': [
                {
                  'scriptpubkey':
                      '0014751e76e8199196d454941c45d1b3a323f1433bd6',
                },
              ],
            }),
            200,
          );
        }),
      ),
      keys,
    );
  }
}

Future<void> openDetails(WidgetTester tester) async {
  expect(find.text('送る'), findsNothing);
  expect(find.byTooltip('送金'), findsNothing);
  expect(find.textContaining('残高:'), findsNothing);
  expect(find.textContaining('送金可能:'), findsNothing);
  expect(find.byTooltip('残高を更新'), findsNothing);
  await tester.tap(find.byType(AddressListTile));
  await tester.pumpAndSettle();
}

Future<void> openSend(WidgetTester tester) async {
  if (find.byType(AddressQrDialog).evaluate().isEmpty) {
    await openDetails(tester);
  }
  final send = find.descendant(
    of: find.byType(AddressQrDialog),
    matching: find.byTooltip('送金'),
  );
  expect(send, findsOneWidget);
  final title = find.descendant(
    of: find.byType(AddressQrDialog),
    matching: find.text('普段使い'),
  );
  expect(tester.getCenter(send).dx, greaterThan(tester.getCenter(title).dx));
  expect(tester.getCenter(send).dy, closeTo(tester.getCenter(title).dy, 1));
  await tester.tap(send);
  await tester.pumpAndSettle();
  expect(find.byType(AddressQrDialog), findsNothing);
  expect(find.text('Bitcoinを送る'), findsOneWidget);
}

Future<void> fillPayment(WidgetTester tester) async {
  await openSend(tester);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('send-address')), addressText);
  await tester.enterText(find.byKey(const Key('send-amount')), '0.00005');
  await tester.ensureVisible(find.text('送金内容を確認'));
  await tester.tap(find.text('送金内容を確認'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('小さい画面とキーボード表示中も送金を確認できる', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final fixture = Fixture();
    addTearDown(fixture.wallet.blockchainClient.close);
    await tester.pumpWidget(App(bitcoinWallet: fixture.wallet));
    await tester.pumpAndSettle();
    await openSend(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.enterText(find.byKey(const Key('send-address')), addressText);
    await tester.enterText(find.byKey(const Key('send-amount')), '0.00005');
    await tester.scrollUntilVisible(
      find.text('送金内容を確認'),
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('送金内容を確認'));
    await tester.pumpAndSettle();
    expect(find.text('送金内容の確認'), findsOneWidget);
    expect(fixture.posts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  test('BTCの入力を浮動小数点を使わずsatoshiへ変換する', () {
    expect(parseBitcoin('0.00000001'), 1);
    expect(parseBitcoin('1.23456789'), 123456789);
    for (final text in ['0', '-1', '1e-8', '0.000000001', '21000001', 'NaN']) {
      expect(parseBitcoin(text), isNull);
    }
    expect(formatBitcoin(1), '0.00000001');
  });

  testWidgets('残高表示から確認・送信を経て残高を更新する', (tester) async {
    final fixture = Fixture();
    addTearDown(fixture.wallet.blockchainClient.close);
    await tester.pumpWidget(App(bitcoinWallet: fixture.wallet));
    await tester.pumpAndSettle();
    await openDetails(tester);
    expect(find.text('残高: 0.00012000 BTC'), findsOneWidget);
    expect(find.text('UTXO'), findsOneWidget);
    expect(find.text('0.00010000 BTC'), findsOneWidget);
    expect(find.text('0.00002000 BTC'), findsOneWidget);
    expect(find.text('txid: ${'11' * 32}'), findsOneWidget);
    expect(find.text('txid: ${'22' * 32}'), findsOneWidget);
    expect(find.text('vout: 0'), findsNWidgets(2));
    expect(fixture.balanceRequests, 1);
    expect(find.textContaining('送金可能:'), findsNothing);
    expect(find.text('送金時に手数料が差し引かれます。'), findsNothing);
    await fillPayment(tester);
    expect(find.text('送金内容の確認'), findsOneWidget);
    expect(fixture.posts, isEmpty);
    expect(
      find.text(
        '手数料: ${formatBitcoin(fixture.wallet.prepared!.fee)} BTC (${fixture.wallet.prepared!.fee} sat)',
      ),
      findsOneWidget,
    );

    fixture.gate = Completer<http.Response>();
    await tester.ensureVisible(find.text('確認して送信'));
    await tester.tap(find.text('確認して送信'));
    await tester.pump();
    expect(fixture.posts, hasLength(1));
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '処理中…'))
          .onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('送金内容の確認'), findsOneWidget);

    fixture.spent = true;
    fixture.gate!.complete(http.Response(fixture.wallet.prepared!.txid, 200));
    await tester.pumpAndSettle();
    expect(find.text('送信完了'), findsOneWidget);
    expect(find.text(fixture.wallet.prepared!.txid), findsOneWidget);
    expect(
      find.text(
        'https://mempool.space/testnet4/tx/${fixture.wallet.prepared!.txid}',
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('アドレス詳細へ戻る'));
    await tester.tap(find.text('アドレス詳細へ戻る'));
    await tester.pumpAndSettle();
    expect(find.text('残高: 0.00000000 BTC'), findsOneWidget);
    expect(find.text('UTXOはありません'), findsOneWidget);
    expect(fixture.balanceRequests, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('残高の通信エラーを再取得し送信エラーでは同じ取引を再送する', (tester) async {
    final fixture = Fixture()..failBalance = true;
    addTearDown(fixture.wallet.blockchainClient.close);
    await tester.pumpWidget(App(bitcoinWallet: fixture.wallet));
    await tester.pumpAndSettle();
    await openDetails(tester);
    expect(find.text('残高を取得できませんでした。'), findsOneWidget);
    fixture.failBalance = false;
    await tester.tap(find.text('残高を再取得'));
    await tester.pumpAndSettle();
    expect(find.text('残高: 0.00012000 BTC'), findsOneWidget);
    await fillPayment(tester);
    fixture.failSend = true;
    await tester.ensureVisible(find.text('確認して送信'));
    await tester.tap(find.text('確認して送信'));
    await tester.pumpAndSettle();
    expect(find.textContaining('送信結果を確認できませんでした'), findsOneWidget);
    expect(find.text(fixture.wallet.prepared!.txid), findsOneWidget);
    expect(find.text('入力を修正'), findsNothing);
    fixture.failSend = false;
    await tester.ensureVisible(find.text('同じ取引を再送信'));
    await tester.tap(find.text('同じ取引を再送信'));
    await tester.pumpAndSettle();
    expect(fixture.posts, hasLength(2));
    expect(fixture.posts[0], fixture.posts[1]);
    expect(fixture.wallet.preparations, 1);
    expect(find.text('送信完了'), findsOneWidget);
  });

  testWidgets('ネットワーク違い・小数点以下9桁・手数料ゼロを送信しない', (tester) async {
    final fixture = Fixture();
    addTearDown(fixture.wallet.blockchainClient.close);
    await tester.pumpWidget(App(bitcoinWallet: fixture.wallet));
    await tester.pumpAndSettle();
    await openSend(tester);
    await tester.enterText(
      find.byKey(const Key('send-address')),
      '1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH',
    );
    await tester.enterText(find.byKey(const Key('send-amount')), '0.000000001');
    await tester.enterText(find.byKey(const Key('send-fee-rate')), '0');
    await tester.ensureVisible(find.text('送金内容を確認'));
    await tester.tap(find.text('送金内容を確認'));
    await tester.pumpAndSettle();
    expect(find.text('送信元と同じネットワークのアドレスを入力してください'), findsOneWidget);
    expect(find.text('有効な送金額を入力してください'), findsOneWidget);
    expect(find.text('1以上の整数を入力してください'), findsOneWidget);
    expect(fixture.wallet.preparations, 0);
    expect(fixture.posts, isEmpty);
  });

  testWidgets('残高不足と秘密鍵の欠落を表示し送信しない', (tester) async {
    final fixture = Fixture();
    addTearDown(fixture.wallet.blockchainClient.close);
    await tester.pumpWidget(App(bitcoinWallet: fixture.wallet));
    await tester.pumpAndSettle();
    await openSend(tester);
    await tester.enterText(find.byKey(const Key('send-address')), addressText);
    await tester.enterText(find.byKey(const Key('send-amount')), '1');
    await tester.ensureVisible(find.text('送金内容を確認'));
    await tester.tap(find.text('送金内容を確認'));
    await tester.pumpAndSettle();
    expect(find.text('手数料を含む残高が不足しています'), findsOneWidget);
    fixture.keys.missing = true;
    await tester.tap(find.text('送金内容を確認'));
    await tester.pumpAndSettle();
    expect(find.text('送信元の秘密鍵が見つかりません'), findsOneWidget);
    expect(fixture.posts, isEmpty);
  });
}
