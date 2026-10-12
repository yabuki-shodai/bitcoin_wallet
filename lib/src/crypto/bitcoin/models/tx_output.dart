import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'tx_output.freezed.dart';

@freezed
abstract class TxOutput with _$TxOutput {
  const factory TxOutput({
    required int value,
    required Uint8List scriptPubKey,
  }) = _TxOutput;
}
