String formatBitcoinAmount(int satoshis) {
  final value = satoshis.abs();
  final sign = satoshis < 0 ? '-' : '';
  final fraction = (value % 100000000).toString().padLeft(8, '0');
  return '$sign${value ~/ 100000000}.$fraction BTC';
}
