import 'package:freezed_annotation/freezed_annotation.dart';

part 'bitcoin_history_entry.freezed.dart';

/// A transaction's effect on the balance of one address, including fees.
@freezed
abstract class BitcoinHistoryEntry with _$BitcoinHistoryEntry {
  const factory BitcoinHistoryEntry({
    required String txid,
    required int balanceChange,
    required bool confirmed,
    DateTime? confirmedAt,
    String? toAddress,
    @Default(false) bool canReplace,
  }) = _BitcoinHistoryEntry;
}
