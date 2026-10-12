import 'package:freezed_annotation/freezed_annotation.dart';

part 'bitcoin_balance_summary.freezed.dart';

@freezed
abstract class BitcoinBalanceSummary with _$BitcoinBalanceSummary {
  const factory BitcoinBalanceSummary({
    required String totalText,
    required String confirmedText,
    required List<BitcoinUtxoSummary> utxos,
  }) = _BitcoinBalanceSummary;
}

@freezed
abstract class BitcoinUtxoSummary with _$BitcoinUtxoSummary {
  const factory BitcoinUtxoSummary({
    required String txid,
    required int vout,
    required String valueText,
    required bool confirmed,
  }) = _BitcoinUtxoSummary;
}
