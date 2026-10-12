import 'package:freezed_annotation/freezed_annotation.dart';

part 'bitcoin_payment_preview.freezed.dart';

@Freezed(copyWith: false)
abstract class BitcoinPaymentPreview with _$BitcoinPaymentPreview {
  const factory BitcoinPaymentPreview({
    required String rawHex,
    required String txid,
    required String toAddress,
    required String amountText,
    required String feeText,
    required String totalText,
    required String feeRateText,
    required Uri explorerUrl,
  }) = _BitcoinPaymentPreview;
}
