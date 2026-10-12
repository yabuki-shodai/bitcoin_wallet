class BitcoinBalanceSummary {
  BitcoinBalanceSummary({
    required this.totalText,
    required this.confirmedText,
    required List<BitcoinUtxoSummary> utxos,
  }) : utxos = List.unmodifiable(utxos);

  final String totalText;
  final String confirmedText;
  final List<BitcoinUtxoSummary> utxos;
}

class BitcoinUtxoSummary {
  const BitcoinUtxoSummary({
    required this.txid,
    required this.vout,
    required this.valueText,
    required this.confirmed,
  });

  final String txid;
  final int vout;
  final String valueText;
  final bool confirmed;
}
