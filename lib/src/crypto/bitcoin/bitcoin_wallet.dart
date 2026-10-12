import 'package:bitcoin_wallet/src/core/key_pair/secp256/secp256_key_generator.dart';
import 'package:bitcoin_wallet/src/core/secure/private_key_store.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_address_generator.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address.dart';
import 'package:bitcoin_wallet/src/core/wallet/wallet.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address_type.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/repository/bitcoin_repository.dart';
import 'bitcoin_blockchain_client.dart';
import 'bitcoin_payments.dart';
import 'bitcoin_transaction_builder.dart';

class BitcoinWallet implements Wallet<BitcoinAddress>, BitcoinPayments {
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

  void _checkNetwork(BitcoinAddress address) {
    if (address.network != network) throw ArgumentError('アドレスのネットワークが一致しません');
  }

  @override
  Future<BitcoinBalance> getBalance(BitcoinAddress address) async {
    _checkNetwork(address);
    final utxos = await blockchainClient.getUtxos(address.address);
    return BitcoinBalance(
      utxos: List.unmodifiable(utxos),
      total: utxos.fold(0, (sum, u) => sum + u.value),
      confirmed: utxos
          .where((u) => u.confirmed)
          .fold(0, (sum, u) => sum + u.value),
    );
  }

  @override
  Future<PreparedBitcoinPayment> preparePayment({
    required BitcoinAddress from,
    required String toAddress,
    required int amount,
    required int feeRate,
  }) async {
    _checkNetwork(from);
    final privateKey = await store.readPrivateKey(from.address);
    if (privateKey == null) throw StateError('送信元の秘密鍵が見つかりません');
    final utxos = await blockchainClient.getUtxos(from.address);
    return BitcoinTransactionBuilder(network: network).buildPayment(
      utxos: utxos,
      privateKey: privateKey,
      toAddress: toAddress,
      amount: amount,
      feeRate: feeRate,
      changeAddress: from.address,
    );
  }

  @override
  Future<String> sendPayment(PreparedBitcoinPayment payment) async {
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
    await repostory.deleteAddress(address);
  }
}
