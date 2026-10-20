import 'package:bitcoin_wallet/src/core/key_pair/index.dart';
import 'package:bitcoin_wallet/src/core/secure/index.dart';
import 'package:bitcoin_wallet/src/core/wallet/index.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/index.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/index.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/repository/index.dart';
import 'package:convert/convert.dart' as convert;

enum BitcoinReplacementStatus {
  pending,
  notFound,
  originalActive,
  conflicted,
  accepted,
  confirmed,
}

class BitcoinWallet implements Wallet<BitcoinAddress> {
  final Network network;
  final BitcoinAddressRepository repostory;
  final PrivateKeyStore store;
  final BitcoinBlockchainClient blockchainClient;

  BitcoinWallet({
    required this.network,
    required this.repostory,
    required this.store,
    BitcoinBlockchainClient? blockchainClient,
  }) : blockchainClient =
           blockchainClient ?? BitcoinBlockchainClient(network: network);

  int? _parseBitcoin(String text) {
    final match = RegExp(
      r'^(\d{1,8})(?:\.(\d{1,8}))?$',
    ).firstMatch(text.trim());
    if (match == null) return null;
    final value =
        int.parse(match[1]!) * 100000000 +
        int.parse((match[2] ?? '').padRight(8, '0'));
    return value > 0 && value <= 21000000 * 100000000 ? value : null;
  }

  String _explorerBaseUrl(Network network) => switch (network) {
    Network.mainnet => 'https://blockstream.info',
    Network.testnet => BitcoinBlockchainClient.explorerBaseUrl,
  };

  Uri addressExplorerUrl(BitcoinAddress address) => Uri.parse(
    '${_explorerBaseUrl(address.network)}/address/${Uri.encodeComponent(address.address)}',
  );

  Uri transactionExplorerUrl(String txid) =>
      Uri.parse('${_explorerBaseUrl(network)}/tx/${Uri.encodeComponent(txid)}');

  void _checkNetwork(BitcoinAddress address) {
    if (address.network != network) throw ArgumentError('アドレスのネットワークが一致しません');
  }

  Future<List<BitcoinHistoryEntry>> getTransactionHistory(
    BitcoinAddress address,
  ) async {
    _checkNetwork(address);
    return blockchainClient.getTransactionHistory(address.address);
  }

  Future<List<BitcoinUtxo>> getUtxos(BitcoinAddress address) async {
    _checkNetwork(address);
    return blockchainClient.getUtxos(address.address);
  }

  Future<BitcoinTransaction> preparePayment({
    required BitcoinAddress from,
    required String toAddress,
    required String amount,
    required String feeRate,
    bool replaceable = false,
  }) async {
    _checkNetwork(from);
    final destination = _validateDestination(toAddress);
    final amountSats = _parseBitcoin(amount);
    if (amountSats == null) {
      throw ArgumentError.value(amount, 'amount', '有効な送金額を入力してください');
    }
    if (amountSats < 546) {
      throw ArgumentError.value(
        amount,
        'amount',
        '送金額は0.00000546 BTC以上で入力してください',
      );
    }
    final rate = _parseFeeRate(feeRate);

    final privateKey = await store.readPrivateKey(from.address);
    if (privateKey == null) throw StateError('送信元の秘密鍵が見つかりません');
    final utxos = await blockchainClient.getUtxos(from.address);
    return BitcoinTransactionBuilder(network: network).buildPayment(
      utxos: utxos,
      privateKey: privateKey,
      toAddress: destination,
      amount: amountSats,
      feeRate: rate,
      changeAddress: from.address,
      replaceable: replaceable,
    );
  }

  String _validateDestination(String toAddress) {
    final destination = toAddress.trim();
    try {
      BitcoinAddressDecoder().toScriptPubKey(destination, network: network);
    } on ArgumentError {
      throw ArgumentError.value(
        toAddress,
        'toAddress',
        '送信元と同じネットワークのアドレスを入力してください',
      );
    } on FormatException {
      throw ArgumentError.value(
        toAddress,
        'toAddress',
        '有効なP2PKHまたはP2WPKHアドレスを入力してください',
      );
    } on UnsupportedError {
      throw ArgumentError.value(
        toAddress,
        'toAddress',
        '有効なP2PKHまたはP2WPKHアドレスを入力してください',
      );
    }
    return destination;
  }

  int _parseFeeRate(String feeRate) {
    final feeRateText = feeRate.trim();
    final rate = RegExp(r'^\d+$').hasMatch(feeRateText)
        ? int.tryParse(feeRateText)
        : null;
    if (rate == null || rate <= 0) {
      throw ArgumentError.value(feeRate, 'feeRate', '1以上の整数を入力してください');
    }
    return rate;
  }

  Future<BitcoinTransaction> getReplaceableTransaction({
    required BitcoinAddress from,
    required String txid,
  }) async {
    _checkNetwork(from);
    final original = await blockchainClient.getTransaction(txid);
    _checkReplaceableTransaction(from, original);
    await _checkReplacementStatus(original);
    return original;
  }

  void _checkReplaceableTransaction(
    BitcoinAddress from,
    BitcoinTransaction payment,
  ) {
    final sourceScript = convert.hex.encode(
      BitcoinAddressDecoder().toScriptPubKey(from.address, network: network),
    );
    if (payment.inputs.isEmpty ||
        payment.inputs.any(
          (input) =>
              input.sequence != 0xfffffffd ||
              convert.hex.encode(input.utxo.scriptPubkey) != sourceScript,
        )) {
      throw StateError('変更可能な送金ではありません');
    }
    if (payment.outputs.length != 2 ||
        convert.hex.encode(payment.outputs[1].scriptPubKey) != sourceScript) {
      throw StateError('送金の変更に利用できるお釣りがありません');
    }
    scriptType(payment.outputs.first.scriptPubKey);
  }

  Future<void> _checkReplacementStatus(
    BitcoinTransaction original, {
    String? replacementTxid,
  }) async {
    final confirmed = await blockchainClient.getTransactionConfirmation(
      original.txid,
    );
    if (confirmed == null) throw StateError('取引が見つかりません。取引履歴を再取得してください');
    if (confirmed) {
      throw StateError('承認済みのため送金内容を変更できません');
    }
    final outputs = await blockchainClient.getSpendingTransactionIds(
      original.txid,
    );
    if (outputs.any((txid) => txid != null)) {
      throw StateError('この取引の出力は使用済みのため送金内容を変更できません');
    }
    final previousTransactions = <String, List<String?>>{};
    for (final input in original.inputs) {
      final txid = input.utxo.txid;
      final spends = previousTransactions[txid] ??= await blockchainClient
          .getSpendingTransactionIds(txid);
      if (input.utxo.vout >= spends.length ||
          (spends[input.utxo.vout] != original.txid &&
              (replacementTxid == null ||
                  spends[input.utxo.vout] != replacementTxid))) {
        throw StateError('取引が更新されています。取引履歴を再取得してください');
      }
    }
  }

  Future<BitcoinTransaction> prepareReplacement({
    required BitcoinAddress from,
    required String txid,
    required String toAddress,
    required String feeRate,
  }) async {
    _checkNetwork(from);
    final destination = _validateDestination(toAddress);
    final rate = _parseFeeRate(feeRate);
    final original = await getReplaceableTransaction(from: from, txid: txid);
    final privateKey = await store.readPrivateKey(from.address);
    if (privateKey == null) throw StateError('送信元の秘密鍵が見つかりません');
    return BitcoinTransactionBuilder(network: network).buildReplacement(
      original: original,
      toAddress: destination,
      privateKey: privateKey,
      feeRate: rate,
    );
  }

  Future<String> sendReplacement({
    required BitcoinAddress from,
    required String originalTxid,
    required BitcoinTransaction payment,
  }) async {
    _checkNetwork(from);
    // 通信結果が不明だった場合も、同じ取引が受理済みなら成功として扱う。
    if (await blockchainClient.getTransactionConfirmation(payment.txid) !=
        null) {
      return payment.txid;
    }
    final original = await blockchainClient.getTransaction(originalTxid);
    _checkReplaceableTransaction(from, original);
    if (payment.outputs.isEmpty ||
        payment.outputs.length > 2 ||
        (payment.outputs.length == 2 &&
            convert.hex.encode(payment.outputs[1].scriptPubKey) !=
                convert.hex.encode(original.outputs[1].scriptPubKey)) ||
        payment.outputs.first.value != original.outputs.first.value ||
        payment.inputs.length != original.inputs.length ||
        payment.version != original.version ||
        payment.lockTime != original.lockTime ||
        payment.fee < original.fee + payment.virtualSize ||
        payment.fee * original.virtualSize <=
            original.fee * payment.virtualSize) {
      throw StateError('置換取引の内容が一致しません');
    }
    scriptType(payment.outputs.first.scriptPubKey);
    for (var index = 0; index < original.inputs.length; index++) {
      final before = original.inputs[index];
      final after = payment.inputs[index];
      if (before.utxo.txid != after.utxo.txid ||
          before.utxo.vout != after.utxo.vout ||
          before.utxo.value != after.utxo.value ||
          convert.hex.encode(before.utxo.scriptPubkey) !=
              convert.hex.encode(after.utxo.scriptPubkey) ||
          before.sequence != after.sequence) {
        throw StateError('置換取引の入力が一致しません');
      }
    }
    await _checkReplacementStatus(original, replacementTxid: payment.txid);
    return sendPayment(payment);
  }

  Future<BitcoinReplacementStatus> getReplacementStatus({
    required BitcoinTransaction original,
    required BitcoinTransaction payment,
  }) async {
    if (original.txid == payment.txid ||
        original.inputs.isEmpty ||
        original.inputs.length != payment.inputs.length) {
      throw ArgumentError('上書き前後の取引が一致しません');
    }
    for (var index = 0; index < original.inputs.length; index++) {
      final before = original.inputs[index].utxo;
      final after = payment.inputs[index].utxo;
      if (before.txid != after.txid || before.vout != after.vout) {
        throw ArgumentError('上書き前後の入力が一致しません');
      }
    }
    final confirmed = await blockchainClient.getTransactionConfirmation(
      payment.txid,
    );
    if (confirmed == null) return BitcoinReplacementStatus.notFound;
    if (await blockchainClient.getTransactionConfirmation(original.txid) ==
        true) {
      return BitcoinReplacementStatus.conflicted;
    }
    var originalActive = true;
    var replacementActive = true;
    final previousTransactions = <String, List<String?>>{};
    for (final input in original.inputs) {
      final utxo = input.utxo;
      final spends = previousTransactions[utxo.txid] ??= await blockchainClient
          .getSpendingTransactionIds(utxo.txid);
      if (utxo.vout >= spends.length) return BitcoinReplacementStatus.pending;
      final spender = spends[utxo.vout];
      if (spender != null &&
          spender != original.txid &&
          spender != payment.txid) {
        return BitcoinReplacementStatus.conflicted;
      }
      originalActive = originalActive && spender == original.txid;
      replacementActive = replacementActive && spender == payment.txid;
    }
    if (originalActive) return BitcoinReplacementStatus.originalActive;
    if (!replacementActive) return BitcoinReplacementStatus.pending;
    return confirmed
        ? BitcoinReplacementStatus.confirmed
        : BitcoinReplacementStatus.accepted;
  }

  Future<String> sendPayment(BitcoinTransaction payment) async {
    if (payment.inputs.any(
      (input) => input.scriptSig.isEmpty && (input.witness?.isEmpty ?? true),
    )) {
      throw StateError('未署名の取引は送信できません');
    }
    final txid = await blockchainClient.broadcastTransaction(payment.rawHex);
    if (txid.toLowerCase() != payment.txid) {
      throw StateError('送信結果のtxidが一致しません');
    }
    return txid;
  }

  @override
  Future<List<BitcoinAddress>> getAddresses() async {
    return repostory.getAddresses();
  }

  @override
  Future<BitcoinAddress> generateAddress(String displayName) =>
      generateAddressOfType(displayName, BitcoinAddressType.p2wpkh);

  Future<BitcoinAddress> generateAddressOfType(
    String displayName,
    BitcoinAddressType type,
  ) async {
    final keyPairGenerator = Secp256k1KeyPairGenerator();
    final keyPair = keyPairGenerator.generate();

    // アドレスを生成する処理
    final bitcoinGenerator = BitcoinAddressGenerator(
      network: network,
      type: type,
    );
    final address = await bitcoinGenerator.create(
      keyPair.publicKey,
      displayName,
    );

    // 秘密鍵の保存
    await store.savePrivateKey(address.address, keyPair.privateKey);

    return address;
  }

  @override
  Future<void> saveAddress(BitcoinAddress address) async {
    await repostory.saveAddress(address);
  }

  @override
  Future<void> deleteAddress(BitcoinAddress address) async {
    // Keep the address accessible if secure storage refuses deletion.
    final privateKey = await store.readPrivateKey(address.address);
    await store.deletePrivateKey(address.address);
    try {
      await repostory.deleteAddress(address);
    } catch (_) {
      if (privateKey != null) {
        await store.savePrivateKey(address.address, privateKey);
      }
      rethrow;
    }
  }
}
