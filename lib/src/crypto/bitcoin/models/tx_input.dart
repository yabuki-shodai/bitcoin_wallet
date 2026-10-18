import 'dart:typed_data';

import 'package:convert/convert.dart' as convert;
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_utxo.dart';

part 'tx_input.freezed.dart';

@freezed
abstract class TxInput with _$TxInput {
  const TxInput._();

  const factory TxInput({
    required BitcoinUtxo utxo,
    @Default(<int>[]) List<int> scriptSig,
    List<Uint8List>? witness,
    @Default(0xffffffff) int sequence,
  }) = _TxInput;

  /// シリアライズ時のバイト順で返す。
  Uint8List get txid => Uint8List.fromList(
    convert.hex.decode(utxo.txid).reversed.toList(),
  ).asUnmodifiableView();

  int get vout => utxo.vout;
}
