import 'dart:convert';
import 'dart:typed_data';

import 'package:bitcoin_wallet/src/core/api/blockchain_client.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_address_decoder.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_utxo.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_history_entry.dart';
import 'package:convert/convert.dart' as convert;
import 'package:http/http.dart' as http;

class BitcoinBlockchainClient implements BlockchainClient {
  static const baseUrl = 'https://mempool.space/testnet4/api/';
  static const explorerBaseUrl = 'https://mempool.space/testnet4';

  final Network network;
  final http.Client _client;

  BitcoinBlockchainClient({required this.network, http.Client? client})
    : _client = client ?? http.Client();

  String get _apiBaseUrl => switch (network) {
    Network.mainnet => 'https://blockstream.info/api/',
    Network.testnet => baseUrl,
  };

  Uri _apiUrl(String path) => Uri.parse(_apiBaseUrl).resolve(path);

  void close() => _client.close();

  Future<List<BitcoinHistoryEntry>> getTransactionHistory(
    String address,
  ) async {
    if (BitcoinAddressDecoder().decode(address).network != network) {
      throw ArgumentError.value(address, 'address', 'クライアントとネットワークが一致しません');
    }

    Future<List<BitcoinHistoryEntry>> fetch(String path) async {
      final url = _apiUrl(path);
      final response = await _client
          .get(url)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw http.ClientException(
          '取引履歴取得に失敗しました (HTTP ${response.statusCode})',
          url,
        );
      }
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map(
            (item) => _parseHistoryEntry(item as Map<String, dynamic>, address),
          )
          .toList();
    }

    final firstPage = await fetch('address/$address/txs');
    final entries = {for (final entry in firstPage) entry.txid: entry};
    var confirmed = firstPage.where((entry) => entry.confirmed).toList();
    final cursors = <String>{};
    while (confirmed.length >= 25) {
      final cursor = confirmed.last.txid;
      if (!cursors.add(cursor)) throw StateError('取引履歴の取得が進みませんでした');
      confirmed = await fetch('address/$address/txs/chain/$cursor');
      for (final entry in confirmed) {
        entries[entry.txid] = entry;
      }
    }
    return List.unmodifiable(entries.values);
  }

  BitcoinHistoryEntry _parseHistoryEntry(
    Map<String, dynamic> json,
    String address,
  ) {
    var received = 0;
    var spent = 0;
    for (final output in json['vout'] as List<dynamic>) {
      if (output['scriptpubkey_address'] == address) {
        received += output['value'] as int;
      }
    }
    for (final input in json['vin'] as List<dynamic>) {
      final previousOutput = input['prevout'];
      if (previousOutput != null &&
          previousOutput['scriptpubkey_address'] == address) {
        spent += previousOutput['value'] as int;
      }
    }
    final status = json['status'] as Map<String, dynamic>;
    final confirmed = status['confirmed'] as bool;
    final blockTime = status['block_time'] as int?;
    return BitcoinHistoryEntry(
      txid: json['txid'] as String,
      balanceChange: received - spent,
      confirmed: confirmed,
      confirmedAt: confirmed && blockTime != null
          ? DateTime.fromMillisecondsSinceEpoch(blockTime * 1000, isUtc: true)
          : null,
    );
  }

  @override
  Future<String> broadcastTransaction(String signedTransactionHex) async {
    final bytes = convert.hex.decode(signedTransactionHex);
    if (bytes.isEmpty) {
      throw const FormatException('署名済み取引が空です');
    }

    final url = _apiUrl('tx');
    final response = await _client
        .post(
          url,
          headers: {'Content-Type': 'text/plain'},
          body: signedTransactionHex,
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        '取引の送信に失敗しました (HTTP ${response.statusCode}): ${response.body}',
        url,
      );
    }
    final txid = response.body.trim();
    if (txid.length != 64 || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(txid)) {
      throw FormatException('送信結果のtxidが不正です', txid);
    }
    return txid;
  }

  Future<List<BitcoinUtxo>> getUtxos(String address) async {
    if (BitcoinAddressDecoder().decode(address).network != network) {
      throw ArgumentError.value(address, 'address', 'クライアントとネットワークが一致しません');
    }

    final url = _apiUrl('address/$address/utxo');
    final response = await _client
        .get(url)
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw http.ClientException(
        'UTXO取得に失敗しました (HTTP ${response.statusCode})',
        url,
      );
    }
    final data = jsonDecode(response.body) as List<dynamic>;
    final bitcoinUtxos = await Future.wait<BitcoinUtxo>(
      data.map((item) async {
        final e = item as Map<String, dynamic>;
        final txid = e['txid'] as String;
        final vout = e['vout'] as int;
        final scriptPubKey = await _fetchScriptPubKey(txid: txid, vout: vout);
        final status = e['status'] as Map<String, dynamic>;

        return BitcoinUtxo(
          txid: txid,
          vout: vout,
          value: e['value'] as int,
          confirmed: status['confirmed'] as bool,
          scriptPubkey: scriptPubKey,
        );
      }),
    );

    return bitcoinUtxos;
  }

  Future<Uint8List> _fetchScriptPubKey({
    required String txid,
    required int vout,
  }) async {
    final url = _apiUrl('tx/$txid');
    final response = await _client
        .get(url)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw http.ClientException(
        '取引取得に失敗しました (HTTP ${response.statusCode})',
        url,
      );
    }
    final Map<String, dynamic> data = jsonDecode(response.body);
    final voutList = data['vout'] as List<dynamic>;
    if (vout < 0 || vout >= voutList.length) {
      throw FormatException('取引に指定されたvoutがありません: $txid:$vout');
    }
    final voutItem = voutList[vout] as Map<String, dynamic>;
    final scriptHex = voutItem['scriptpubkey'] as String?;
    if (scriptHex == null || scriptHex.isEmpty) {
      throw FormatException('取引のscriptpubkeyがありません: $txid:$vout');
    }
    return Uint8List.fromList(convert.hex.decode(scriptHex));
  }
}
