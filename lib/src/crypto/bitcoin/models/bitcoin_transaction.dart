import 'package:freezed_annotation/freezed_annotation.dart';

import 'tx_input.dart';
import 'tx_output.dart';

part 'bitcoin_transaction.freezed.dart';

@freezed
abstract class BitcoinTransaction with _$BitcoinTransaction {
  const factory BitcoinTransaction({
    required List<TxInput> inputs,
    required List<TxOutput> outputs,
    @Default(2) int version,
    @Default(0) int lockTime,
  }) = _BitcoinTransaction;
}
