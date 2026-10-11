import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart' as convert;

import 'bitcoin_transaction.dart';
import 'models/bitcoin_address.dart';
import 'models/bitcoin_utxo.dart';

class BitcoinBalance {
  final int total;
  final int confirmed;
  final List<BitcoinUtxo> utxos;
  const BitcoinBalance({
    required this.total,
    required this.confirmed,
    this.utxos = const [],
  });
}

class PreparedBitcoinPayment {
  final String rawHex;
  final String txid;
  final String toAddress;
  final int amount;
  final int fee;
  final int virtualSize;

  PreparedBitcoinPayment({
    required BitcoinTransaction transaction,
    required this.toAddress,
    required this.amount,
    required this.fee,
  }) : rawHex = convert.hex.encode(transaction.serialize()),
       txid = convert.hex.encode(
         sha256
             .convert(
               sha256
                   .convert(transaction.serialize(includeWitness: false))
                   .bytes,
             )
             .bytes
             .reversed
             .toList(),
       ),
       virtualSize = transaction.virtualSize;
}

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
