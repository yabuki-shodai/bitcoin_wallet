import 'dart:convert';
import 'dart:typed_data';

import 'package:bitcoin_wallet/src/core/api/blockchain_client.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_address_decoder.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_utxo.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_history_entry.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_transaction.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/tx_input.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/tx_output.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_transaction_serializer.dart';
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

  Future<dynamic> _getTransactionData(
    String txid, {
    String suffix = '',
    bool allowMissing = false,
  }) async {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(txid)) {
      throw const FormatException('txidが不正です');
    }
    final url = _apiUrl('tx/$txid$suffix');
    final response = await _client
        .get(url)
        .timeout(const Duration(seconds: 20));
    if (allowMissing && response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw http.ClientException(
        '取引取得に失敗しました (HTTP ${response.statusCode})',
        url,
      );
    }
    return jsonDecode(response.body);
  }

  /// 未送信と未承認を区別するため、取引本体の存在と承認状態を取得する。
  /// /status は存在しないtxidにも confirmed=false を返すことがある。
  Future<bool?> getTransactionConfirmation(String txid) async {
    final data =
        await _getTransactionData(txid, allowMissing: true)
            as Map<String, dynamic>?;
    if (data == null) return null;
    final status = data['status'];
    if (data['txid'] != txid ||
        status is! Map<String, dynamic> ||
        status['confirmed'] is! bool) {
      throw const FormatException('取得した取引の状態が不正です');
    }
    return status['confirmed'] as bool;
  }

  Future<List<String?>> getSpendingTransactionIds(String txid) async {
    final data =
        await _getTransactionData(txid, suffix: '/outspends') as List<dynamic>;
    return data.map((item) {
      final output = item as Map<String, dynamic>;
      return output['spent'] == true ? output['txid'] as String : null;
    }).toList();
  }

  Future<BitcoinTransaction> getTransaction(String txid) async {
    final data = await _getTransactionData(txid) as Map<String, dynamic>;
    final transaction = BitcoinTransaction(
      version: data['version'] as int,
      lockTime: data['locktime'] as int,
      inputs: [
        for (final item in data['vin'] as List<dynamic>)
          TxInput(
            utxo: BitcoinUtxo(
              txid: item['txid'] as String,
              vout: item['vout'] as int,
              value: item['prevout']['value'] as int,
              confirmed: false,
              scriptPubkey: Uint8List.fromList(
                convert.hex.decode(item['prevout']['scriptpubkey'] as String),
              ),
            ),
            sequence: item['sequence'] as int,
            scriptSig: convert.hex.decode(item['scriptsig'] as String),
            witness: (item['witness'] as List<dynamic>?)
                ?.map(
                  (value) =>
                      Uint8List.fromList(convert.hex.decode(value as String)),
                )
                .toList(),
          ),
      ],
      outputs: [
        for (final item in data['vout'] as List<dynamic>)
          TxOutput(
            value: item['value'] as int,
            scriptPubKey: Uint8List.fromList(
              convert.hex.decode(item['scriptpubkey'] as String),
            ),
          ),
      ],
    );
    if (transaction.txid != txid || transaction.fee != data['fee']) {
      throw const FormatException('取得した取引の内容が一致しません');
    }
    return transaction;
  }

  Future<List<BitcoinHistoryEntry>> getTransactionHistory(
    String address,
  ) async {
    BitcoinAddressDecoder().toScriptPubKey(address, network: network);

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
    final inputs = json['vin'] as List<dynamic>;
    final outputs = json['vout'] as List<dynamic>;
    final canReplace =
        !confirmed &&
        inputs.isNotEmpty &&
        inputs.every(
          (input) =>
              input['sequence'] == 0xfffffffd &&
              input['prevout']?['scriptpubkey_address'] == address,
        ) &&
        outputs.length == 2 &&
        outputs[1]['scriptpubkey_address'] == address &&
        outputs.first['scriptpubkey_address'] != null &&
        const [
          'p2pkh',
          'v0_p2wpkh',
        ].contains(outputs.first['scriptpubkey_type']);
    return BitcoinHistoryEntry(
      txid: json['txid'] as String,
      balanceChange: received - spent,
      confirmed: confirmed,
      toAddress: canReplace
          ? outputs.first['scriptpubkey_address'] as String
          : null,
      canReplace: canReplace,
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
    BitcoinAddressDecoder().toScriptPubKey(address, network: network);

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
