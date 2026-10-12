sealed class BitcoinPaymentPreparation {
  const BitcoinPaymentPreparation();
}

final class BitcoinPaymentInputErrors extends BitcoinPaymentPreparation {
  const BitcoinPaymentInputErrors({this.toAddress, this.amount, this.feeRate});

  final String? toAddress;
  final String? amount;
  final String? feeRate;
}

final class BitcoinPaymentPreview extends BitcoinPaymentPreparation {
  const BitcoinPaymentPreview({
    required this.rawHex,
    required this.txid,
    required this.toAddress,
    required this.amountText,
    required this.feeText,
    required this.totalText,
    required this.feeRateText,
    required this.explorerUrl,
  });

  final String rawHex;
  final String txid;
  final String toAddress;
  final String amountText;
  final String feeText;
  final String totalText;
  final String feeRateText;
  final Uri explorerUrl;
}
