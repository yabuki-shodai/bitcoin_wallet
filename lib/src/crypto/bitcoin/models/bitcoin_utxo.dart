import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'bitcoin_utxo.freezed.dart';

@freezed
abstract class BitcoinUtxo with _$BitcoinUtxo {
  const factory BitcoinUtxo({
    required String txid,
    required int vout,
    required int value,
    required bool confirmed,
    required Uint8List scriptPubkey,
  }) = _BitcoinUtxo;
}
