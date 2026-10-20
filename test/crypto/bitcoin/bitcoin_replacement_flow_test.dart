import 'dart:convert';
import 'dart:typed_data';

import 'package:bitcoin_wallet/src/core/secure/private_key_store.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_blockchain_client.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_transaction_builder.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_transaction_serializer.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_wallet.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/index.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/repository/bitcoin_repository.dart';
import 'package:bitcoin_wallet/src/ui/pages/bitcoin/bitcoin_send_page.dart';
import 'package:convert/convert.dart' as convert;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Repository extends Fake implements BitcoinAddressRepository {}

class _KeyStore extends Fake implements PrivateKeyStore {
  @override
  Future<Uint8List?> readPrivateKey(String address) async =>
      Uint8List(32)..[31] = 1;
}

// Wallet/API/UIをつなぎ、存在しないtxidにも/statusがfalseを返す実APIの挙動を再現する。
class _ReplacementApi {
  static const sourceAddress = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
  static const destination = '1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH';
  final source = BitcoinAddress(
    address: sourceAddress,
    network: Network.mainnet,
    publicKey: Uint8List(33),
    type: BitcoinAddressType.p2wpkh,
  );
  late final original = BitcoinTransactionBuilder(network: Network.mainnet)
      .buildPayment(
        utxos: [
          BitcoinUtxo(
            txid: '11' * 32,
            vout: 0,
            value: 100000,
            confirmed: true,
            scriptPubkey: Uint8List.fromList(
              convert.hex.decode(
                '0014751e76e8199196d454941c45d1b3a323f1433bd6',
              ),
            ),
          ),
        ],
        privateKey: Uint8List(32)..[31] = 1,
        toAddress: destination,
        amount: 5000,
        feeRate: 2,
        changeAddress: sourceAddress,
        replaceable: true,
      );
  BitcoinTransaction? replacement;
  bool accepted = false;
  bool confirmed = false;
  bool loseResponse = false;
  bool rejectBroadcast = false;
  bool lookupUnavailable = false;
  final posts = <String>[];
  final requests = <String>[];
  late final client = BitcoinBlockchainClient(
    network: Network.mainnet,
    client: MockClient((request) async {
      final path = request.url.path;
      requests.add('${request.method} $path');
      if (request.method == 'POST') {
        posts.add(request.body);
        if (rejectBroadcast) return http.Response('replacement rejected', 400);
        accepted = true;
        if (loseResponse) {
          loseResponse = false;
          throw http.ClientException('response lost after acceptance');
        }
        return http.Response(replacement!.txid, 200);
      }
      if (path.endsWith('/status')) {
        return http.Response('{"confirmed":false}', 200);
      }
      if (path.endsWith('/outspends')) {
        final txid = path.split('/')[3];
        if (txid == original.inputs.single.utxo.txid) {
          return http.Response(
            jsonEncode([
              {
                'spent': true,
                'txid': accepted ? replacement!.txid : original.txid,
              },
            ]),
            200,
          );
        }
        return http.Response('[{"spent":false},{"spent":false}]', 200);
      }
      if (path == '/api/tx/${original.txid}' && !accepted) {
        return http.Response(jsonEncode(_data(original, false)), 200);
      }
      if (replacement != null && path == '/api/tx/${replacement!.txid}') {
        if (lookupUnavailable) return http.Response('unavailable', 503);
        if (accepted) {
          return http.Response(jsonEncode(_data(replacement!, confirmed)), 200);
        }
      }
      return http.Response('Transaction not found', 404);
    }),
  );
  late final wallet = BitcoinWallet(
    network: Network.mainnet,
    repostory: _Repository(),
    store: _KeyStore(),
    blockchainClient: client,
  );

  Future<BitcoinTransaction> prepare() async =>
      replacement = await wallet.prepareReplacement(
        from: source,
        txid: original.txid,
        toAddress: destination,
        feeRate: '20',
      );

  Map<String, dynamic> _data(BitcoinTransaction tx, bool confirmed) => {
    'txid': tx.txid,
    'version': tx.version,
    'locktime': tx.lockTime,
    'fee': tx.fee,
    'status': {'confirmed': confirmed},
    'vin': [
      for (final input in tx.inputs)
        {
          'txid': input.utxo.txid,
          'vout': input.utxo.vout,
          'sequence': input.sequence,
          'scriptsig': convert.hex.encode(input.scriptSig),
          'witness': input.witness?.map(convert.hex.encode).toList(),
          'prevout': {
            'value': input.utxo.value,
            'scriptpubkey': convert.hex.encode(input.utxo.scriptPubkey),
          },
        },
    ],
    'vout': [
      for (final output in tx.outputs)
        {
          'value': output.value,
          'scriptpubkey': convert.hex.encode(output.scriptPubKey),
        },
    ],
  };
}

void main() {
  test('存在しない取引へのstatus=falseでも実際にPOSTし、受理済みの再試行では送信を重複させない', () async {
    final api = _ReplacementApi();
    addTearDown(api.client.close);
    final payment = await api.prepare();
    expect(
      await api.wallet.sendReplacement(
        from: api.source,
        originalTxid: api.original.txid,
        payment: payment,
      ),
      payment.txid,
    );
    expect(api.posts, [payment.rawHex]);
    expect(
      await api.wallet.getReplacementStatus(
        original: api.original,
        payment: payment,
      ),
      BitcoinReplacementStatus.accepted,
    );
    // 上書き前の取引本体は404になっても、再試行では受理済みと判断できる。
    expect(
      await api.wallet.sendReplacement(
        from: api.source,
        originalTxid: api.original.txid,
        payment: payment,
      ),
      payment.txid,
    );
    expect(api.posts, hasLength(1));
    api.confirmed = true;
    expect(
      await api.wallet.getReplacementStatus(
        original: api.original,
        payment: payment,
      ),
      BitcoinReplacementStatus.confirmed,
    );
  });

  test('受理後に送信応答を失っても同じ取引の再試行で復旧する', () async {
    final api = _ReplacementApi()..loseResponse = true;
    addTearDown(api.client.close);
    final payment = await api.prepare();
    await expectLater(
      api.wallet.sendReplacement(
        from: api.source,
        originalTxid: api.original.txid,
        payment: payment,
      ),
      throwsA(isA<http.ClientException>()),
    );
    expect(api.accepted, isTrue);
    expect(
      await api.wallet.sendReplacement(
        from: api.source,
        originalTxid: api.original.txid,
        payment: payment,
      ),
      payment.txid,
    );
    expect(api.posts, hasLength(1));
  });

  test('取引照会の通信失敗と送信拒否を成功にしない', () async {
    final api = _ReplacementApi();
    addTearDown(api.client.close);
    final payment = await api.prepare();
    api.lookupUnavailable = true;
    await expectLater(
      api.wallet.sendReplacement(
        from: api.source,
        originalTxid: api.original.txid,
        payment: payment,
      ),
      throwsA(isA<http.ClientException>()),
    );
    expect(api.posts, isEmpty);
    api.lookupUnavailable = false;
    api.rejectBroadcast = true;
    await expectLater(
      api.wallet.sendReplacement(
        from: api.source,
        originalTxid: api.original.txid,
        payment: payment,
      ),
      throwsA(isA<http.ClientException>()),
    );
    expect(api.posts, [payment.rawHex]);
    expect(api.accepted, isFalse);
  });

  testWidgets('実際の生成・送信・確認を経て上書き成功を表示し、連続上書き中に呼び出し元へ戻らない', (tester) async {
    final api = _ReplacementApi();
    addTearDown(api.client.close);
    await tester.runAsync(api.prepare);
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var returned = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => BitcoinSendPage(
                      from: api.source,
                      wallet: api.wallet,
                      original: BitcoinHistoryEntry(
                        txid: api.original.txid,
                        balanceChange: -5000 - api.original.fee,
                        confirmed: false,
                        toAddress: _ReplacementApi.destination,
                        canReplace: true,
                      ),
                    ),
                  ),
                );
                returned = true;
              },
              child: const Text('開く'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('send-fee-rate')), '20');
    await tester.tap(find.text('変更内容を確認'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確認して送信'));
    await tester.pumpAndSettle();
    expect(api.posts, hasLength(1));
    expect(find.text('変更取引を送信しました'), findsOneWidget);
    expect(find.text('ブロック承認待ち'), findsOneWidget);
    expect(find.text('手数料を上書き'), findsNothing);
    await tester.tap(find.text('取引詳細へ戻る'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('手数料を上書き'));
    await tester.tap(find.text('手数料を上書き'));
    await tester.pumpAndSettle();
    expect(returned, isFalse);
    expect(find.byKey(const Key('send-fee-rate')), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('send-address')))
          .controller!
          .text,
      _ReplacementApi.destination,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(returned, isTrue);
  });
}
