import 'dart:convert';
import 'dart:typed_data';

import 'package:bitcoin_wallet/src/core/secure/secure_store.dart';

class PrivateKeyStore {
  PrivateKeyStore({required this.asset});
  final String asset;
  final _secureStore = SecureStore();

  String _key(String address) => '$asset:privateKey:$address';

  Future<void> deletePrivateKey(String address) =>
      _secureStore.delete(key: _key(address));

  Future<void> savePrivateKey(String address, Uint8List privateKey) async {
    await _secureStore.save(
      key: _key(address),
      value: base64Encode(privateKey),
    );
  }

  Future<Uint8List?> readPrivateKey(String address) async {
    final encodedPrivateKey = await _secureStore.read(key: _key(address));
    return encodedPrivateKey == null ? null : base64Decode(encodedPrivateKey);
  }
}
