import 'package:bitcoin_wallet/src/core/key_pair/index.dart';
import 'package:bitcoin_wallet/src/core/secure/index.dart';
import 'package:bitcoin_wallet/src/core/wallet/index.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/index.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/index.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/repository/index.dart';

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
  }) async {
    _checkNetwork(from);
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
    final feeRateText = feeRate.trim();
    final rate = RegExp(r'^\d+$').hasMatch(feeRateText)
        ? int.tryParse(feeRateText)
        : null;
    if (rate == null || rate <= 0) {
      throw ArgumentError.value(feeRate, 'feeRate', '1以上の整数を入力してください');
    }

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
    );
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
