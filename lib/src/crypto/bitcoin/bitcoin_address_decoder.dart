import 'dart:typed_data';

import 'package:base58check/base58check.dart';
import 'package:bech32/bech32.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';

class BitcoinAddressDecoder {
  /// 対応種別とネットワークを検証し、出力スクリプトへ変換する。
  Uint8List toScriptPubKey(String address, {required Network network}) {
    final lowerAddress = address.toLowerCase();
    if (lowerAddress.startsWith('bc1') || lowerAddress.startsWith('tb1')) {
      return _decodeSegwit(address, network);
    }
    return _decodeBase58(address, network);
  }

  Uint8List _decodeSegwit(String address, Network network) {
    late Segwit decoded;
    try {
      decoded = const SegwitCodec().decode(address);
    } on Exception catch (error) {
      throw FormatException('無効なSegWitアドレスです: $error', address);
    }

    if (decoded.version != 0 || decoded.program.length != 20) {
      throw UnsupportedError('未対応のSegWitアドレスタイプです');
    }
    final expectedHrp = network == Network.mainnet ? 'bc' : 'tb';
    if (decoded.hrp != expectedHrp) {
      throw ArgumentError.value(address, 'address', 'ネットワークが一致しません');
    }
    return Uint8List.fromList([
      0x00, // OP_0
      0x14, // 20-byte push
      ...decoded.program,
    ]).asUnmodifiableView();
  }

  Uint8List _decodeBase58(String address, Network network) {
    late Base58CheckPayload decoded;
    try {
      decoded = Base58CheckCodec.bitcoin().decode(address);
    } on Exception catch (error) {
      throw FormatException('無効なBase58Checkアドレスです: $error', address);
    }

    final actualNetwork = switch (decoded.version) {
      0x00 => Network.mainnet,
      0x6f => Network.testnet,
      _ => throw UnsupportedError('未対応のBase58Checkアドレスタイプです'),
    };
    if (decoded.payload.length != 20) {
      throw FormatException('公開鍵ハッシュの長さが不正です', address);
    }
    if (actualNetwork != network) {
      throw ArgumentError.value(address, 'address', 'ネットワークが一致しません');
    }
    return Uint8List.fromList([
      0x76, // OP_DUP
      0xa9, // OP_HASH160
      0x14, // 20-byte push
      ...decoded.payload,
      0x88, // OP_EQUALVERIFY
      0xac, // OP_CHECKSIG
    ]).asUnmodifiableView();
  }
}
