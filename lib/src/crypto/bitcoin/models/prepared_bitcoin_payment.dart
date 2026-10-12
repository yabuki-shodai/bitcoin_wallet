import 'package:freezed_annotation/freezed_annotation.dart';

part 'prepared_bitcoin_payment.freezed.dart';

@Freezed(copyWith: false)
abstract class PreparedBitcoinPayment with _$PreparedBitcoinPayment {
  const factory PreparedBitcoinPayment({
    required String rawHex,
    required String txid,
    required String toAddress,
    required int amount,
    required int fee,
    required int virtualSize,
  }) = _PreparedBitcoinPayment;
}
