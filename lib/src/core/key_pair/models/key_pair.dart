import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'key_pair.freezed.dart';

@Freezed(toStringOverride: false)
abstract class KeyPair with _$KeyPair {
  const factory KeyPair({
    required Uint8List privateKey,
    required Uint8List publicKey,
  }) = _KeyPair;
}
