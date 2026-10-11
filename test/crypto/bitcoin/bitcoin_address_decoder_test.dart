import 'dart:typed_data';

import 'package:base58check/base58check.dart';
import 'package:bech32/bech32.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_address_decoder.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final decoder = BitcoinAddressDecoder();
  final expectedHash = _fromHex('751e76e8199196d454941c45d1b3a323f1433bd6');

  test('P2PKHアドレスからネットワークと公開鍵ハッシュを取得できる', () {
    final decoded = decoder.decode('1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH');

    expect(decoded.network, Network.mainnet);
    expect(decoded.type, BitcoinAddressType.p2pkh);
    expect(decoded.publicKeyHash, orderedEquals(expectedHash));
  });

  test('P2WPKHアドレスからネットワークと公開鍵ハッシュを取得できる', () {
    final decoded = decoder.decode(
      'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
    );

    expect(decoded.network, Network.mainnet);
    expect(decoded.type, BitcoinAddressType.p2wpkh);
    expect(decoded.publicKeyHash, orderedEquals(expectedHash));
  });

  test('testnetのP2PKHとP2WPKHを判定できる', () {
    final p2pkh = Base58CheckCodec.bitcoin().encode(
      Base58CheckPayload(0x6f, expectedHash),
    );
    final p2wpkh = const SegwitCodec().encode(Segwit('tb', 0, expectedHash));

    expect(decoder.decode(p2pkh).network, Network.testnet);
    expect(decoder.decode(p2wpkh).network, Network.testnet);
  });

  test('チェックサムが不正なアドレスを拒否する', () {
    expect(
      () => decoder.decode('1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMJ'),
      throwsFormatException,
    );
    expect(
      () => decoder.decode('bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5'),
      throwsFormatException,
    );
  });

  test('未対応のアドレスタイプを拒否する', () {
    final p2sh = Base58CheckCodec.bitcoin().encode(
      Base58CheckPayload(0x05, expectedHash),
    );
    final p2wsh = const SegwitCodec().encode(Segwit('bc', 0, Uint8List(32)));

    expect(() => decoder.decode(p2sh), throwsUnsupportedError);
    expect(() => decoder.decode(p2wsh), throwsUnsupportedError);
  });
}

Uint8List _fromHex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);
