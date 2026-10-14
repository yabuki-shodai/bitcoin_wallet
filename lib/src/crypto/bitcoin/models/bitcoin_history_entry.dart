/// A transaction's effect on the balance of one address, including fees.
class BitcoinHistoryEntry {
  const BitcoinHistoryEntry({
    required this.txid,
    required this.balanceChange,
    required this.confirmed,
    this.confirmedAt,
  });

  final String txid;
  final int balanceChange;
  final bool confirmed;
  final DateTime? confirmedAt;

  String get direction => balanceChange > 0
      ? '入金'
      : balanceChange < 0
      ? '出金'
      : '残高変化なし';

  String get amountText {
    final amount = balanceChange.abs();
    final sign = balanceChange > 0
        ? '+'
        : balanceChange < 0
        ? '-'
        : '';
    return '$sign${amount ~/ 100000000}.${(amount % 100000000).toString().padLeft(8, '0')} BTC';
  }

  factory BitcoinHistoryEntry.fromJson(
    Map<String, dynamic> json,
    String address,
  ) {
    var received = 0;
    var spent = 0;
    for (final output in json['vout'] as List<dynamic>) {
      if (output['scriptpubkey_address'] == address) {
        received += output['value'] as int;
      }
    }
    for (final input in json['vin'] as List<dynamic>) {
      final previousOutput = input['prevout'];
      if (previousOutput != null &&
          previousOutput['scriptpubkey_address'] == address) {
        spent += previousOutput['value'] as int;
      }
    }
    final status = json['status'] as Map<String, dynamic>;
    final confirmed = status['confirmed'] as bool;
    final blockTime = status['block_time'] as int?;
    return BitcoinHistoryEntry(
      txid: json['txid'] as String,
      balanceChange: received - spent,
      confirmed: confirmed,
      confirmedAt: confirmed && blockTime != null
          ? DateTime.fromMillisecondsSinceEpoch(blockTime * 1000, isUtc: true)
          : null,
    );
  }
}
