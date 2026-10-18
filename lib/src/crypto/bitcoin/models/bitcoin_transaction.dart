import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:bitcoin_wallet/src/crypto/bitcoin/models/tx_input.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/tx_output.dart';

part 'bitcoin_transaction.freezed.dart';

@freezed
abstract class BitcoinTransaction with _$BitcoinTransaction {
  const BitcoinTransaction._();

  const factory BitcoinTransaction({
    required List<TxInput> inputs,
    required List<TxOutput> outputs,
    @Default(2) int version,
    @Default(0) int lockTime,
  }) = _BitcoinTransaction;

  int get fee =>
      inputs.fold<int>(0, (sum, input) => sum + input.utxo.value) -
      outputs.fold<int>(0, (sum, output) => sum + output.value);
}
