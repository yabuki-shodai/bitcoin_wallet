import 'dart:convert';
import 'dart:typed_data';

import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_blockchain_client.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_transaction_builder.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_transaction_serializer.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_utxo.dart';
import 'package:convert/convert.dart' as convert;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const mainnetAddress = '1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH';
  const testnetAddress = 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx';
  const txid =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const script = '0014751e76e8199196d454941c45d1b3a323f1433bd6';

  test('APIの取引詳細から既存モデルを復元し、txidと手数料を検証する', () async {
    final original = BitcoinTransactionBuilder(network: Network.mainnet)
        .buildPayment(
          utxos: [
            BitcoinUtxo(
              txid: '11' * 32,
              vout: 0,
              value: 10000,
              confirmed: true,
              scriptPubkey: Uint8List.fromList(convert.hex.decode(script)),
            ),
          ],
          privateKey: Uint8List(32)..[31] = 1,
          toAddress: mainnetAddress,
          amount: 5000,
          feeRate: 2,
          changeAddress: mainnetAddress,
          replaceable: true,
        );
    final data = {
      'txid': original.txid,
      'version': original.version,
      'locktime': original.lockTime,
      'fee': original.fee,
      'status': {'confirmed': false},
      'vin': [
        for (final input in original.inputs)
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
        for (final output in original.outputs)
          {
            'value': output.value,
            'scriptpubkey': convert.hex.encode(output.scriptPubKey),
          },
      ],
    };
    var missing = false;
    final client = BitcoinBlockchainClient(
      network: Network.mainnet,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/status')) {
          return http.Response('{"confirmed":false}', 200);
        }
        if (request.url.path.endsWith('/outspends')) {
          return http.Response(
            '[{"spent":false},{"spent":true,"txid":"child"}]',
            200,
          );
        }
        return missing
            ? http.Response('Transaction not found', 404)
            : http.Response(jsonEncode(data), 200);
      }),
    );
    addTearDown(client.close);
    final loaded = await client.getTransaction(original.txid);
    expect(loaded.rawHex, original.rawHex);
    expect(loaded.fee, original.fee);
    expect(loaded.virtualSize, original.virtualSize);
    expect(await client.getTransactionConfirmation(original.txid), isFalse);
    missing = true;
    expect(await client.getTransactionConfirmation(original.txid), isNull);
    expect(await client.getSpendingTransactionIds(original.txid), [
      null,
      'child',
    ]);
    missing = false;
    data['fee'] = original.fee + 1;
    await expectLater(
      client.getTransaction(original.txid),
      throwsFormatException,
    );
    await expectLater(client.getTransaction('22' * 32), throwsFormatException);
  });

  test('取引本体の404だけを未送信とし、不正応答や通信障害を未承認扱いしない', () async {
    var statusCode = 200;
    Map<String, dynamic> data = {
      'txid': txid,
      'status': {'confirmed': false},
    };
    final client = BitcoinBlockchainClient(
      network: Network.testnet,
      client: MockClient((request) async {
        expect(request.url.path, '/testnet4/api/tx/$txid');
        return http.Response(jsonEncode(data), statusCode);
      }),
    );
    addTearDown(client.close);
    expect(await client.getTransactionConfirmation(txid), isFalse);
    data['status'] = {'confirmed': true};
    expect(await client.getTransactionConfirmation(txid), isTrue);
    statusCode = 404;
    expect(await client.getTransactionConfirmation(txid), isNull);
    statusCode = 503;
    await expectLater(
      client.getTransactionConfirmation(txid),
      throwsA(isA<http.ClientException>()),
    );
    statusCode = 200;
    for (final invalid in [
      {
        'txid': 'bb' * 32,
        'status': {'confirmed': false},
      },
      {'txid': txid},
      {
        'txid': txid,
        'status': {'confirmed': 'false'},
      },
    ]) {
      data = invalid;
      await expectLater(
        client.getTransactionConfirmation(txid),
        throwsFormatException,
      );
    }
  });

  test('履歴では未承認で自分の入力とお釣りを持つ変更可能な送金だけを対象にする', () async {
    for (final entry in [
      (0xfffffffd, false, mainnetAddress, true, true),
      (0xffffffff, false, mainnetAddress, true, false),
      (0xfffffffd, true, mainnetAddress, true, false),
      (0xfffffffd, false, 'other', true, false),
      (0xfffffffd, false, mainnetAddress, false, false),
    ]) {
      final data = {
        'txid': txid,
        'vin': [
          {
            'sequence': entry.$1,
            'prevout': {'scriptpubkey_address': entry.$3, 'value': 10000},
          },
        ],
        'vout': [
          {
            'scriptpubkey_address': testnetAddress,
            'scriptpubkey_type': 'v0_p2wpkh',
            'value': 5000,
          },
          if (entry.$4) {'scriptpubkey_address': mainnetAddress, 'value': 4000},
        ],
        'status': {'confirmed': entry.$2},
      };
      final client = BitcoinBlockchainClient(
        network: Network.mainnet,
        client: MockClient((_) async => http.Response(jsonEncode([data]), 200)),
      );
      addTearDown(client.close);
      final history = (await client.getTransactionHistory(
        mainnetAddress,
      )).single;
      expect(history.canReplace, entry.$5);
      expect(history.toAddress, entry.$5 ? testnetAddress : null);
    }
  });

  Map<String, dynamic> historyTransaction(
    int index, {
    bool confirmed = true,
  }) => {
    'txid': index.toRadixString(16).padLeft(64, '0'),
    'vin': [
      {'prevout': null, 'is_coinbase': true},
    ],
    'vout': [
      {'scriptpubkey_address': mainnetAddress, 'value': 1000},
    ],
    'status': {'confirmed': confirmed, if (confirmed) 'block_time': 1700000000},
  };

  test('全ページの取引履歴を取得して重複を除く', () async {
    final paths = <String>[];
    final first = List.generate(25, (i) => historyTransaction(i + 1));
    final second = List.generate(25, (i) => historyTransaction(i + 26));
    final last = [second.last, historyTransaction(51)];
    final responses = [
      [historyTransaction(0, confirmed: false), ...first],
      second,
      last,
    ];
    final client = BitcoinBlockchainClient(
      network: Network.mainnet,
      client: MockClient((request) async {
        paths.add(request.url.path);
        return http.Response(jsonEncode(responses[paths.length - 1]), 200);
      }),
    );
    addTearDown(client.close);
    final entries = await client.getTransactionHistory(mainnetAddress);
    expect(entries, hasLength(52));
    expect(entries.first.confirmed, isFalse);
    expect(entries.first.confirmedAt, isNull);
    expect(entries.last.balanceChange, 1000);
    expect(
      entries.last.confirmedAt,
      DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
    );
    expect(paths, [
      '/api/address/$mainnetAddress/txs',
      '/api/address/$mainnetAddress/txs/chain/${first.last['txid']}',
      '/api/address/$mainnetAddress/txs/chain/${second.last['txid']}',
    ]);
  });

  test('履歴の出金額はお釣りを除いた残高変化として計算する', () async {
    final transaction = historyTransaction(1);
    transaction['vin'] = [
      {
        'prevout': {'scriptpubkey_address': mainnetAddress, 'value': 10000},
      },
      {
        'prevout': {'scriptpubkey_address': 'other', 'value': 50000},
      },
    ];
    transaction['vout'] = [
      {'scriptpubkey_address': mainnetAddress, 'value': 3000},
      {'scriptpubkey_address': mainnetAddress, 'value': 1000},
      {'scriptpubkey_address': 'other', 'value': 55000},
    ];
    final client = BitcoinBlockchainClient(
      network: Network.mainnet,
      client: MockClient(
        (_) async => http.Response(jsonEncode([transaction]), 200),
      ),
    );
    addTearDown(client.close);
    final entry = (await client.getTransactionHistory(mainnetAddress)).single;
    expect(entry.balanceChange, -6000);
  });

  test('testnet4の空の履歴を取得しネットワーク違いは通信しない', () async {
    var calls = 0;
    final client = BitcoinBlockchainClient(
      network: Network.testnet,
      client: MockClient((request) async {
        calls++;
        expect(
          request.url.toString(),
          'https://mempool.space/testnet4/api/address/$testnetAddress/txs',
        );
        return http.Response('[]', 200);
      }),
    );
    addTearDown(client.close);
    expect(await client.getTransactionHistory(testnetAddress), isEmpty);
    await expectLater(
      client.getTransactionHistory(mainnetAddress),
      throwsArgumentError,
    );
    expect(calls, 1);
  });

  test('続きの取得失敗時は不完全な履歴を返さない', () async {
    var calls = 0;
    final client = BitcoinBlockchainClient(
      network: Network.mainnet,
      client: MockClient((_) async {
        calls++;
        return calls == 1
            ? http.Response(
                jsonEncode(List.generate(25, (i) => historyTransaction(i))),
                200,
              )
            : http.Response('error', 503);
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.getTransactionHistory(mainnetAddress),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('testnetのUTXOとscriptPubKeyを同じAPIから取得する', () async {
    final requestedUrls = <String>[];
    final httpClient = MockClient((request) async {
      requestedUrls.add(request.url.toString());
      if (request.url.path.endsWith('/utxo')) {
        return http.Response(
          jsonEncode([
            {
              'txid': txid,
              'vout': 0,
              'value': 5000,
              'status': {'confirmed': true},
            },
          ]),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'vout': [
            {'scriptpubkey': script},
          ],
        }),
        200,
      );
    });
    final client = BitcoinBlockchainClient(
      network: Network.testnet,
      client: httpClient,
    );
    addTearDown(client.close);

    final utxos = await client.getUtxos(testnetAddress);

    expect(requestedUrls, [
      'https://mempool.space/testnet4/api/address/$testnetAddress/utxo',
      'https://mempool.space/testnet4/api/tx/$txid',
    ]);
    expect(utxos, hasLength(1));
    expect(utxos.single.value, 5000);
    expect(utxos.single.confirmed, isTrue);
    expect(convert.hex.encode(utxos.single.scriptPubkey), script);
  });

  test('mainnetのUTXO取得にはmainnetのURLを使う', () async {
    Uri? requestedUrl;
    final httpClient = MockClient((request) async {
      requestedUrl = request.url;
      return http.Response('[]', 200);
    });
    final client = BitcoinBlockchainClient(
      network: Network.mainnet,
      client: httpClient,
    );
    addTearDown(client.close);

    expect(await client.getUtxos(mainnetAddress), isEmpty);
    expect(
      requestedUrl.toString(),
      'https://blockstream.info/api/address/$mainnetAddress/utxo',
    );
  });

  test('APIエラーを空のUTXO一覧として扱わない', () async {
    final httpClient = MockClient((_) async => http.Response('error', 503));
    final client = BitcoinBlockchainClient(
      network: Network.mainnet,
      client: httpClient,
    );
    addTearDown(client.close);

    await expectLater(
      client.getUtxos(mainnetAddress),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('取引取得の失敗を空のscriptPubKeyとして扱わない', () async {
    final httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/utxo')) {
        return http.Response(
          jsonEncode([
            {
              'txid': txid,
              'vout': 0,
              'value': 5000,
              'status': {'confirmed': true},
            },
          ]),
          200,
        );
      }
      return http.Response('not found', 404);
    });
    final client = BitcoinBlockchainClient(
      network: Network.mainnet,
      client: httpClient,
    );
    addTearDown(client.close);

    await expectLater(
      client.getUtxos(mainnetAddress),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('署名済み取引をtestnetのtx APIに送信してtxidを返す', () async {
    const expectedTxid = txid;
    final httpClient = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://mempool.space/testnet4/api/tx');
      expect(request.headers['content-type'], startsWith('text/plain'));
      expect(request.body, '01020304');
      return http.Response(expectedTxid, 200);
    });
    final client = BitcoinBlockchainClient(
      network: Network.testnet,
      client: httpClient,
    );
    addTearDown(client.close);

    expect(await client.broadcastTransaction('01020304'), expectedTxid);
  });

  test('取引送信のHTTPエラーを通知する', () async {
    final httpClient = MockClient((_) async => http.Response('rejected', 400));
    final client = BitcoinBlockchainClient(
      network: Network.mainnet,
      client: httpClient,
    );
    addTearDown(client.close);

    await expectLater(
      client.broadcastTransaction('01020304'),
      throwsA(isA<http.ClientException>()),
    );
  });
}
