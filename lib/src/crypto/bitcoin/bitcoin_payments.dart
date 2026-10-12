import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_balance_summary.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_payment_preview.dart';

abstract class BitcoinPayments {
  Future<BitcoinBalanceSummary> getBalance(BitcoinAddress address);
  Future<BitcoinPaymentPreview> preparePayment({
    required BitcoinAddress from,
    required String toAddress,
    required String amount,
    required String feeRate,
  });
  Future<String> sendPayment(BitcoinPaymentPreview payment);
}
