import 'package:convert/convert.dart' as convert;
import 'dart:typed_data';

import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_utxo.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/tx_input.dart';

class BitcoinInputBuilder {
  TxInput build(BitcoinUtxo utxo) {
    final decodedTxid = convert.hex.decode(utxo.txid);
    if (decodedTxid.length != 32) {
      throw const FormatException('txidは32バイト必要です');
    }
    if (utxo.vout < 0 || utxo.vout > 0xffffffff) {
      throw RangeError.range(utxo.vout, 0, 0xffffffff, 'vout');
    }

    return TxInput(
      txid: Uint8List.fromList(
        decodedTxid.reversed.toList(),
      ).asUnmodifiableView(),
      vout: utxo.vout,
    );
  }
}
