import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'package:bitcoin_wallet/src/core/key_pair/models/key_pair.dart';

abstract class KeyPairGenerator {
  KeyPair generate();
}

class Secp256k1KeyPairGenerator implements KeyPairGenerator {
  @override
  KeyPair generate() {
    final random = Random.secure();
    final curve = ECCurve_secp256k1();
    late Uint8List privateKey;
    late BigInt d;

    do {
      privateKey = Uint8List.fromList(
        List.generate(32, (_) => random.nextInt(256)),
      );
      d = _privateKeyToBigInt(privateKey);
    } while (d == BigInt.zero || d >= curve.n);

    return KeyPair(
      privateKey: Uint8List.fromList(privateKey).asUnmodifiableView(),
      publicKey: derivePublicKey(
        privateKey,
        compressed: false,
      ).asUnmodifiableView(),
    );
  }

  Uint8List derivePublicKey(Uint8List privateKey, {required bool compressed}) {
    if (privateKey.length != 32) {
      throw ArgumentError.value(privateKey, 'privateKey', '32バイトである必要があります');
    }

    final curve = ECCurve_secp256k1();
    final d = _privateKeyToBigInt(privateKey);
    if (d == BigInt.zero || d >= curve.n) {
      throw ArgumentError.value(privateKey, 'privateKey', 'secp256k1の有効範囲外です');
    }

    final point = (curve.G * d)!;
    final x = _bigIntToBytes(point.x!.toBigInteger()!, 32);
    final y = point.y!.toBigInteger()!;

    if (compressed) {
      return Uint8List.fromList([y.isEven ? 0x02 : 0x03, ...x]);
    }

    return Uint8List.fromList([0x04, ...x, ..._bigIntToBytes(y, 32)]);
  }

  static BigInt _privateKeyToBigInt(Uint8List privateKey) {
    return BigInt.parse(
      privateKey.map((e) => e.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    );
  }

  static Uint8List _bigIntToBytes(BigInt value, int length) {
    final hex = value.toRadixString(16).padLeft(length * 2, '0');
    return Uint8List.fromList(
      List.generate(
        length,
        (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
      ),
    );
  }
}
