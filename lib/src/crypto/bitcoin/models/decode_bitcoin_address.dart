import 'dart:typed_data';

import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address_type.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'decode_bitcoin_address.freezed.dart';

@freezed
abstract class DecodeBitcoinAddress with _$DecodeBitcoinAddress {
  const factory DecodeBitcoinAddress({
    required Network network,
    required BitcoinAddressType type,
    required Uint8List publicKeyHash,
  }) = _DecodeBitcoinAddress;
}
