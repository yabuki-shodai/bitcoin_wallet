import 'dart:convert';
import 'dart:typed_data';

import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BitcoinAddressをJSON文字列に保存して復元できる', () {
    final address = BitcoinAddress(
      displayName: '貯蓄用',
      address: 'test-address',
      network: Network.testnet,
      publicKey: Uint8List.fromList([0, 2, 127, 128, 255]),
      type: BitcoinAddressType.p2wpkh,
    );

    final encoded = jsonEncode(address.toJson());
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    final restored = BitcoinAddress.fromJson(decoded);

    expect(decoded['publicKey'], [0, 2, 127, 128, 255]);
    expect(restored.displayName, '貯蓄用');
    expect(restored, address);
    expect(restored.publicKey, isA<Uint8List>());
  });

  test('名前のない既存のJSONも読み込める', () {
    final address = BitcoinAddress.fromJson({
      'address': 'legacy-address',
      'network': 'testnet',
      'publicKey': [2, 3],
      'type': 'p2wpkh',
    });

    expect(address.displayName, isEmpty);
    expect(address.address, 'legacy-address');
  });
}
