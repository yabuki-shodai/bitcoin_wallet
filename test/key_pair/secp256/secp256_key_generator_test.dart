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
}
