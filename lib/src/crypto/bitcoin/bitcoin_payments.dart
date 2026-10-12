import 'models/bitcoin_address.dart';
import 'models/bitcoin_balance_summary.dart';
import 'models/bitcoin_payment_preparation.dart';

abstract class BitcoinPayments {
  Future<BitcoinBalanceSummary> getBalance(BitcoinAddress address);
  Future<BitcoinPaymentPreparation> preparePayment({
    required BitcoinAddress from,
    required String toAddress,
    required String amount,
    required String feeRate,
  });
  Future<String> sendPayment(BitcoinPaymentPreview payment);
}
