import 'dart:async';
import 'dart:typed_data';

import 'package:bitcoin_wallet/src/core/secure/private_key_store.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_wallet.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address_type.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/repository/bitcoin_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class TestKeyStore extends PrivateKeyStore {
  TestKeyStore() : super(asset: 'bitcoin');
  final saved = Completer<void>();

  @override
  Future<void> savePrivateKey(String address, Uint8List privateKey) =>
      saved.future;
}

class TestRepository implements BitcoinAddressRepository {
  @override
  Future<List<BitcoinAddress>> getAddresses() async => [];

  @override
  Future<void> saveAddress(BitcoinAddress address) async {}

  @override
  Future<void> deleteAddress(BitcoinAddress address) async {}
}

void main() {
  test('秘密鍵の保存完了を待ち、指定ネットワークと名前で生成する', () async {
    final store = TestKeyStore();
    final wallet = BitcoinWallet(
      network: Network.mainnet,
      repostory: TestRepository(),
      store: store,
    );
    bool completed = false;
    final generation = wallet.generateAddress('貯蓄用').then((address) {
      completed = true;
      return address;
    });
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    store.saved.complete();
    final address = await generation;
    expect(address.network, Network.mainnet);
    expect(address.address, startsWith('bc1'));
    expect(address.displayName, '貯蓄用');
  });

  test('秘密鍵の保存失敗を生成の失敗として返す', () async {
    final store = TestKeyStore();
    final wallet = BitcoinWallet(
      network: Network.testnet,
      repostory: TestRepository(),
      store: store,
    );
    final expectation = expectLater(
      wallet.generateAddress('普段使い'),
      throwsStateError,
    );
    await Future<void>.delayed(Duration.zero);
    store.saved.completeError(StateError('secure storage failed'));
    await expectation;
  });

  test('選んだP2PKH形式でアドレスを生成する', () async {
    final store = TestKeyStore();
    final wallet = BitcoinWallet(
      network: Network.testnet,
      repostory: TestRepository(),
      store: store,
    );
    final generation = wallet.generateAddressOfType(
      '普段使い',
      BitcoinAddressType.p2pkh,
    );
    store.saved.complete();
    final address = await generation;
    expect(address.type, BitcoinAddressType.p2pkh);
    expect(address.address, anyOf(startsWith('m'), startsWith('n')));
    expect(address.displayName, '普段使い');
  });
}
