import 'dart:io';
import 'dart:typed_data';

import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address_type.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/repository/bitcoin_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  final address = BitcoinAddress(
    displayName: '貯蓄用',
    address: 'test-address',
    network: Network.testnet,
    publicKey: Uint8List.fromList([2, 3]),
    type: BitcoinAddressType.p2wpkh,
  );

  setUp(() async {
    final directory = await Directory.systemTemp.createTemp('wallet_test_');
    addTearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });
    Hive.init(directory.path);
  });

  test('openで保存領域を準備し開き直しても名前とアドレスを復元できる', () async {
    final repository = await BitcoinAddressRepositoryImpl.open();
    await repository.saveAddress(address);
    await Hive.close();

    final reopened = await BitcoinAddressRepositoryImpl.open();
    expect(await reopened.getAddresses(), [address]);
    await reopened.deleteAddress(address);
    expect(await reopened.getAddresses(), isEmpty);
  });

  test('従来の保存領域とJSON形式で保存されたアドレスを読み込める', () async {
    final box = await Hive.openBox<String>('bitcoin_address');
    await box.put(
      'test-address',
      '{"displayName":"貯蓄用","address":"test-address",'
          '"network":"testnet","publicKey":[2,3],"type":"p2wpkh"}',
    );
    await box.close();

    final repository = await BitcoinAddressRepositoryImpl.open();
    expect(await repository.getAddresses(), [address]);
  });

  test('保存領域が開いている状態でもopenを呼べる', () async {
    final first = await BitcoinAddressRepositoryImpl.open();
    await first.saveAddress(address);

    final second = await BitcoinAddressRepositoryImpl.open();
    expect(await second.getAddresses(), [address]);
    await second.deleteAddress(address);
    expect(await first.getAddresses(), isEmpty);
  });
}
