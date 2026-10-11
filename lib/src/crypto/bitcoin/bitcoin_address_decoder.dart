import 'dart:typed_data';

import 'package:base58check/base58check.dart';
import 'package:bech32/bech32.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address_type.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/decode_bitcoin_address.dart';

class BitcoinAddressDecoder {
  DecodeBitcoinAddress decode(String address) {
    final lowerAddress = address.toLowerCase();
    if (lowerAddress.startsWith('bc1') || lowerAddress.startsWith('tb1')) {
      return _decodeSegwit(address);
    }
    return _decodeBase58(address);
  }

  DecodeBitcoinAddress _decodeSegwit(String address) {
    late Segwit decoded;
    try {
      decoded = const SegwitCodec().decode(address);
    } on Exception catch (error) {
      throw FormatException('無効なSegWitアドレスです: $error', address);
    }

    if (decoded.version != 0 || decoded.program.length != 20) {
      throw UnsupportedError('未対応のSegWitアドレスタイプです');
    }

    return DecodeBitcoinAddress(
      network: decoded.hrp == 'bc' ? Network.mainnet : Network.testnet,
      type: BitcoinAddressType.p2wpkh,
      publicKeyHash: Uint8List.fromList(decoded.program),
    );
  }

  DecodeBitcoinAddress _decodeBase58(String address) {
    late Base58CheckPayload decoded;
    try {
      decoded = Base58CheckCodec.bitcoin().decode(address);
    } on Exception catch (error) {
      throw FormatException('無効なBase58Checkアドレスです: $error', address);
    }

    final network = switch (decoded.version) {
      0x00 => Network.mainnet,
      0x6f => Network.testnet,
      _ => throw UnsupportedError('未対応のBase58Checkアドレスタイプです'),
    };

    if (decoded.payload.length != 20) {
      throw FormatException('公開鍵ハッシュの長さが不正です', address);
    }

    return DecodeBitcoinAddress(
      network: network,
      type: BitcoinAddressType.p2pkh,
      publicKeyHash: Uint8List.fromList(decoded.payload),
    );
  }
}
