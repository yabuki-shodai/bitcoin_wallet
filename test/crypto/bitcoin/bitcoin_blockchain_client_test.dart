import 'dart:convert';

import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_blockchain_client.dart';
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
