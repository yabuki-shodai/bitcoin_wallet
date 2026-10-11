import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bitcoin_wallet/src/core/key_pair/secp256/secp256_key_generator.dart';

void main() {
  test('Secp256KeyGeneratorが正しい長さの鍵ペアを生成することを検証', () {
    final generator = Secp256k1KeyPairGenerator();
    final keyPair = generator.generate();

    // 秘密鍵の長さが32バイトか確認
    expect(keyPair.privateKey.length, 32, reason: '秘密鍵の長さが32バイトであること');
    // 公開鍵の長さが65バイト(非圧縮形式)か確認 (0x04 + 32バイトX + 32バイトY)
    expect(keyPair.publicKey.length, 65, reason: '公開鍵の長さが65バイトであること');

    // 先頭バイトが0x04(非圧縮形式)であることを確認
    expect(keyPair.publicKey[0], 0x04, reason: '公開鍵の先頭バイトが0x04であること');
  });

  test('秘密鍵1から圧縮・非圧縮公開鍵を導出できる', () {
    final generator = Secp256k1KeyPairGenerator();
    final privateKey = Uint8List(32)..[31] = 1;

    final compressed = generator.derivePublicKey(privateKey, compressed: true);
    final uncompressed = generator.derivePublicKey(
      privateKey,
      compressed: false,
    );

    expect(
      _toHex(compressed),
      '0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
    );
    expect(
      _toHex(uncompressed),
      '0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798'
      '483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8',
    );
  });

  test('無効な秘密鍵は拒否する', () {
    final generator = Secp256k1KeyPairGenerator();
    final curveOrder = _fromHex(
      'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
    );

    for (final privateKey in [Uint8List(31), Uint8List(32), curveOrder]) {
      expect(
        () => generator.derivePublicKey(privateKey, compressed: true),
        throwsArgumentError,
      );
    }
  });
}

String _toHex(Uint8List bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Uint8List _fromHex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);
