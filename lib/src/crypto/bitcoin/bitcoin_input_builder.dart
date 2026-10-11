import 'package:convert/convert.dart' as convert;
import 'dart:typed_data';

import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_utxo.dart';

class TxInput {
  final Uint8List txid;
  final int vout;
  Uint8List scriptSig;
  List<Uint8List>? witness;
  final int sequence;

  TxInput({
    required this.txid,
    required this.vout,
    Uint8List? scriptSig,
    this.witness,
    this.sequence = 0xffffffff,
  }) : scriptSig = scriptSig ?? Uint8List(0);
}

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
      txid: Uint8List.fromList(decodedTxid.reversed.toList()),
      vout: utxo.vout,
    );
  }
}
