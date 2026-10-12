import 'models/bitcoin_address.dart';
import 'models/bitcoin_balance.dart';
import 'models/prepared_bitcoin_payment.dart';

abstract class BitcoinPayments {
  Future<BitcoinBalance> getBalance(BitcoinAddress address);
  Future<PreparedBitcoinPayment> preparePayment({
    required BitcoinAddress from,
    required String toAddress,
    required int amount,
    required int feeRate,
  });
  Future<String> sendPayment(PreparedBitcoinPayment payment);
}

String formatBitcoin(int satoshis) =>
    '${satoshis ~/ 100000000}.${(satoshis % 100000000).toString().padLeft(8, '0')}';

int? parseBitcoin(String text) {
  final match = RegExp(r'^(\d{1,8})(?:\.(\d{1,8}))?$').firstMatch(text.trim());
  if (match == null) return null;
  final value =
      int.parse(match[1]!) * 100000000 +
      int.parse((match[2] ?? '').padRight(8, '0'));
  return value > 0 && value <= 21000000 * 100000000 ? value : null;
}
