import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_utxo.dart';

part 'bitcoin_balance.freezed.dart';

@freezed
abstract class BitcoinBalance with _$BitcoinBalance {
  const factory BitcoinBalance({
    required int total,
    required int confirmed,
    @Default(<BitcoinUtxo>[]) List<BitcoinUtxo> utxos,
  }) = _BitcoinBalance;
}
