import 'dart:typed_data';

import 'package:base58check/base58check.dart';
import 'package:bech32/bech32.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_address_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final decoder = BitcoinAddressDecoder();
  final hash = _fromHex('751e76e8199196d454941c45d1b3a323f1433bd6');
  final p2pkhScript = [0x76, 0xa9, 0x14, ...hash, 0x88, 0xac];
  final p2wpkhScript = [0x00, 0x14, ...hash];

  test('mainnetのP2PKHとP2WPKHを出力スクリプトに変換する', () {
    expect(
      decoder.toScriptPubKey(
        '1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH',
        network: Network.mainnet,
      ),
      orderedEquals(p2pkhScript),
    );
    expect(
      decoder.toScriptPubKey(
        'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
        network: Network.mainnet,
      ),
      orderedEquals(p2wpkhScript),
    );
  });

  test('testnetのP2PKHとP2WPKHを変換し異なるネットワークを拒否する', () {
    final p2pkh = Base58CheckCodec.bitcoin().encode(
      Base58CheckPayload(0x6f, hash),
    );
    final p2wpkh = const SegwitCodec().encode(Segwit('tb', 0, hash));
    expect(
      decoder.toScriptPubKey(p2pkh, network: Network.testnet),
      orderedEquals(p2pkhScript),
    );
    expect(
      decoder.toScriptPubKey(p2wpkh, network: Network.testnet),
      orderedEquals(p2wpkhScript),
    );
    for (final address in [p2pkh, p2wpkh]) {
      expect(
        () => decoder.toScriptPubKey(address, network: Network.mainnet),
        throwsArgumentError,
      );
    }
    for (final address in [
      '1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH',
      'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
    ]) {
      expect(
        () => decoder.toScriptPubKey(address, network: Network.testnet),
        throwsArgumentError,
      );
    }
  });

  test('チェックサムが不正なアドレスを拒否する', () {
    for (final address in [
      '1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMJ',
      'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5',
    ]) {
      expect(
        () => decoder.toScriptPubKey(address, network: Network.mainnet),
        throwsFormatException,
      );
    }
  });

  test('未対応の種別・長さ・witnessバージョンを拒否する', () {
    for (final address in [
      Base58CheckCodec.bitcoin().encode(Base58CheckPayload(0x05, hash)),
      const SegwitCodec().encode(Segwit('bc', 0, Uint8List(32))),
      const SegwitCodec().encode(Segwit('bc', 1, hash)),
    ]) {
      expect(
        () => decoder.toScriptPubKey(address, network: Network.mainnet),
        throwsUnsupportedError,
      );
    }
    final invalidLength = Base58CheckCodec.bitcoin().encode(
      Base58CheckPayload(0x00, Uint8List(19)),
    );
    expect(
      () => decoder.toScriptPubKey(invalidLength, network: Network.mainnet),
      throwsFormatException,
    );
  });

  test('変換したスクリプトは変更できない', () {
    final script = decoder.toScriptPubKey(
      '1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH',
      network: Network.mainnet,
    );
    expect(() => script[0] = 0, throwsUnsupportedError);
  });
}

Uint8List _fromHex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);
