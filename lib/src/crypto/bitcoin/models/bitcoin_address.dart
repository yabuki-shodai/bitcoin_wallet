import 'dart:typed_data';

import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address_type.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'bitcoin_address.freezed.dart';
part 'bitcoin_address.g.dart';

@freezed
abstract class BitcoinAddress with _$BitcoinAddress {
  const factory BitcoinAddress({
    @Default('') String displayName,
    required String address,
    required Network network,
    @JsonKey(fromJson: _publicKeyFromJson, toJson: _publicKeyToJson)
    required Uint8List publicKey,
    required BitcoinAddressType type,
  }) = _BitcoinAddress;

  factory BitcoinAddress.fromJson(Map<String, dynamic> json) =>
      _$BitcoinAddressFromJson(json);
}

Uint8List _publicKeyFromJson(List<dynamic> json) =>
    Uint8List.fromList(json.cast<int>());

List<int> _publicKeyToJson(Uint8List publicKey) => publicKey.toList();
