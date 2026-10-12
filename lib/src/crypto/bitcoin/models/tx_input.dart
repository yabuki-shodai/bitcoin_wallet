import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'tx_input.freezed.dart';

@freezed
abstract class TxInput with _$TxInput {
  const factory TxInput({
    required Uint8List txid,
    required int vout,
    @Default(<int>[]) List<int> scriptSig,
    List<Uint8List>? witness,
    @Default(0xffffffff) int sequence,
  }) = _TxInput;
}
