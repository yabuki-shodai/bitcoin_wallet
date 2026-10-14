import 'package:freezed_annotation/freezed_annotation.dart';

part 'bitcoin_history_summary.freezed.dart';

@freezed
abstract class BitcoinHistorySummary with _$BitcoinHistorySummary {
  const factory BitcoinHistorySummary({
    required String txid,
    required String direction,
    required String amountText,
    required bool confirmed,
    DateTime? confirmedAt,
  }) = _BitcoinHistorySummary;
}
