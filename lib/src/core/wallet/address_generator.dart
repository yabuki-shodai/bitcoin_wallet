import 'dart:typed_data';

abstract class AddressGenerator<T> {
  Future<T> create(Uint8List publicKey, String displayName);
}
