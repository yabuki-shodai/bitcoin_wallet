import 'dart:typed_data';

import 'package:bitcoin_wallet/src/core/secure/private_key_store.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_wallet.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address_type.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/repository/bitcoin_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryRepository implements BitcoinAddressRepository {
  final addresses = <BitcoinAddress>[];
  bool failDeletion = false;

  @override
  Future<List<BitcoinAddress>> getAddresses() async => addresses;

  @override
  Future<void> saveAddress(BitcoinAddress address) async =>
      addresses.add(address);

  @override
  Future<void> deleteAddress(BitcoinAddress address) async {
    if (failDeletion) throw StateError('address deletion failed');
    addresses.removeWhere((item) => item.address == address.address);
  }
}

class FailingKeyStore extends PrivateKeyStore {
  FailingKeyStore() : super(asset: 'bitcoin');

  @override
  Future<void> deletePrivateKey(String address) async {
    throw StateError('key deletion failed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final address = BitcoinAddress(
    address: 'test-address',
    network: Network.testnet,
    publicKey: Uint8List(33),
    type: BitcoinAddressType.p2wpkh,
  );
  final privateKey = Uint8List(32)..[31] = 1;
  late PrivateKeyStore store;
  late MemoryRepository repository;
  late BitcoinWallet wallet;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    store = PrivateKeyStore(asset: 'bitcoin');
    repository = MemoryRepository()..addresses.add(address);
    wallet = BitcoinWallet(
      network: Network.testnet,
      repostory: repository,
      store: store,
    );
    await store.savePrivateKey(address.address, privateKey);
    await store.savePrivateKey('other-address', privateKey);
  });

  test('完全削除は対象の秘密鍵とアドレスだけを削除する', () async {
    await wallet.deleteAddress(address);
    expect(repository.addresses, isEmpty);
    expect(await store.readPrivateKey(address.address), isNull);
    expect(await store.readPrivateKey('other-address'), privateKey);
  });

  test('秘密鍵の削除失敗時はアドレスを保持する', () async {
    final failingWallet = BitcoinWallet(
      network: Network.testnet,
      repostory: repository,
      store: FailingKeyStore(),
    );
    await expectLater(failingWallet.deleteAddress(address), throwsStateError);
    expect(repository.addresses, [address]);
    expect(await store.readPrivateKey(address.address), privateKey);
  });

  test('アドレス削除の失敗時は秘密鍵を復元する', () async {
    repository.failDeletion = true;
    await expectLater(wallet.deleteAddress(address), throwsStateError);
    expect(repository.addresses, [address]);
    expect(await store.readPrivateKey(address.address), privateKey);
  });
}
