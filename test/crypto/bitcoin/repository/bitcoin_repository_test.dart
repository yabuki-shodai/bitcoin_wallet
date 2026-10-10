import 'dart:io';
import 'dart:typed_data';

import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address_type.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/repository/bitcoin_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  test('保存領域を開き直しても名前とアドレスを復元できる', () async {
    final directory = await Directory.systemTemp.createTemp('wallet_test_');
    addTearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });
    Hive.init(directory.path);
    var box = await Hive.openBox<String>(BitcoinAddressRepositoryImpl.boxName);
    final address = BitcoinAddress(
      displayName: '貯蓄用',
      address: 'test-address',
      network: Network.testnet,
      publicKey: Uint8List.fromList([2, 3]),
      type: BitcoinAddressType.p2wpkh,
    );
    await BitcoinAddressRepositoryImpl(box).saveAddress(address);
    await box.close();
    box = await Hive.openBox<String>(BitcoinAddressRepositoryImpl.boxName);
    final restored = await BitcoinAddressRepositoryImpl(box).getAddresses();
    expect(restored, [address]);
  });
}
