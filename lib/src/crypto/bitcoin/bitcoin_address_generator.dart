import 'dart:typed_data';

import 'package:bitcoin_wallet/src/core/wallet/address_generator.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address_type.dart';
import 'package:base58check/base58check.dart';
import 'package:bech32/bech32.dart';
import 'package:pointycastle/export.dart';
import 'package:crypto/crypto.dart';

class BitcoinAddressGenerator implements AddressGenerator {
  final Network network;
  final BitcoinAddressType type;

  BitcoinAddressGenerator({required this.network, required this.type});

  @override
  Future<BitcoinAddress> create(Uint8List publicKey, String displayName) async {
    final String address = switch (type) {
      BitcoinAddressType.p2wpkh => _generateP2WPKHAddress(publicKey),
      BitcoinAddressType.p2pkh => _generateP2PKH(publicKey),
      _ => throw UnsupportedError('未対応のアドレスタイプです: $type'),
    };

    return BitcoinAddress(
      displayName: displayName,
      address: address,
      network: network,
      publicKey: publicKey,
      type: type,
    );
  }

  String _generateP2PKH(Uint8List publicKey) {
    final sha256Hash = sha256.convert(publicKey).bytes;
    final pubKeyHash = RIPEMD160Digest().process(
      Uint8List.fromList(sha256Hash),
    );

    final version = network == Network.testnet ? 0x6f : 0x00;

    final address = Base58CheckCodec.bitcoin().encode(
      Base58CheckPayload(version, pubKeyHash),
    );

    return address;
  }

  String _generateP2WPKHAddress(Uint8List publicKey) {
    // 公開鍵を33バイトの圧縮形式に変換
    final compressedPublicKey = _compressPublicKey(publicKey);

    // SHA-256 → RIPEMD-160
    final sha256Hash = sha256.convert(compressedPublicKey).bytes;
    final pubKeyHash = RIPEMD160Digest().process(
      Uint8List.fromList(sha256Hash),
    );

    final hrp = network == Network.testnet ? 'tb' : 'bc';

    final address = const SegwitCodec().encode(Segwit(hrp, 0, pubKeyHash));

    return address;
  }

  Uint8List _compressPublicKey(Uint8List publicKey) {
    // すでに圧縮公開鍵の場合
    if (publicKey.length == 33) {
      if (publicKey[0] != 0x02 && publicKey[0] != 0x03) {
        throw ArgumentError('Invalid compressed public key');
      }

      return Uint8List.fromList(publicKey);
    }

    // 非圧縮公開鍵の場合
    if (publicKey.length == 65 && publicKey[0] == 0x04) {
      // X座標
      final x = publicKey.sublist(1, 33);

      // Y座標の最下位ビットで偶奇を判定
      final prefix = publicKey[64].isEven ? 0x02 : 0x03;

      return Uint8List.fromList([prefix, ...x]);
    }

    throw ArgumentError('Invalid public key format');
  }
}
