import 'dart:typed_data';

import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/core/key_pair/secp256/secp256_key_generator.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_input_builder.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_output_builder.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_transaction.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_transaction_builder.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_transaction_signer.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_utxo.dart';
import 'package:convert/convert.dart' as convert;
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

Uint8List _bytes(String hex) => Uint8List.fromList(convert.hex.decode(hex));

void main() {
  test('重複UTXOを使った取引を拒否する', () {
    final utxo = BitcoinUtxo(
      txid: '11' * 32,
      vout: 0,
      value: 10000,
      confirmed: true,
      scriptPubkey: _bytes('0014751e76e8199196d454941c45d1b3a323f1433bd6'),
    );
    expect(
      () => BitcoinTransactionBuilder(network: Network.testnet).build(
        utxos: [utxo, utxo],
        privateKey: Uint8List(32)..[31] = 1,
        toAddress: 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
        amount: 15000,
        feeRate: 1,
        changeAddress: 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
      ),
      throwsArgumentError,
    );
  });

  test('圧縮P2PKHでは非圧縮公開鍵のサイズによる残高不足を起こさない', () {
    final utxo = BitcoinUtxo(
      txid: '22' * 32,
      vout: 0,
      value: 10000,
      confirmed: true,
      scriptPubkey: _bytes(
        '76a914751e76e8199196d454941c45d1b3a323f1433bd688ac',
      ),
    );
    final payment = BitcoinTransactionBuilder(network: Network.mainnet)
        .buildPayment(
          utxos: [utxo],
          privateKey: Uint8List(32)..[31] = 1,
          toAddress: '1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH',
          amount: 9800,
          feeRate: 1,
          changeAddress: '1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH',
        );
    expect(payment.fee, 200);
    expect(payment.virtualSize, lessThanOrEqualTo(200));
    expect(payment.txid, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('BIP143 Native P2WPKH の公開テストベクトルと署名ハッシュが一致する', () {
    // https://bips.dev/143/#native-p2wpkh
    final transaction = BitcoinTransaction(
      version: 1,
      lockTime: 17,
      inputs: [
        TxInput(
          txid: _bytes(
            'fff7f7881a8099afa6940d42d1e7f6362bec38171ea3edf433541db4e4ad969f',
          ),
          vout: 0,
          sequence: 0xffffffee,
        ),
        TxInput(
          txid: _bytes(
            'ef51e1b804cc89d182d279655c3aa89e815b1b309fe287d9b2b55d57b90ec68a',
          ),
          vout: 1,
        ),
      ],
      outputs: [
        TxOutput(
          value: 112340000,
          scriptPubKey: _bytes(
            '76a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac',
          ),
        ),
        TxOutput(
          value: 223450000,
          scriptPubKey: _bytes(
            '76a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac',
          ),
        ),
      ],
    );

    final digest = BitcoinTransactionSigner().signatureHashSegwitV0(
      transaction,
      1,
      600000000,
      _bytes('1d0f172a0ecb48aee1be1f2687d2963ae33f71a1'),
    );

    expect(
      convert.hex.encode(digest),
      'c37af31116d1b27caf68aae9e3ac82f1477929014d5b917657d0eb49478cb670',
    );
  });

  test('P2WPKH UTXOから署名済みSegWit取引を構築する', () {
    final privateKey = Uint8List(32)..[31] = 1;
    final utxo = BitcoinUtxo(
      txid: '11' * 32,
      vout: 1,
      value: 10000,
      confirmed: true,
      scriptPubkey: _bytes('0014751e76e8199196d454941c45d1b3a323f1433bd6'),
    );

    final raw = BitcoinTransactionBuilder(network: Network.testnet).build(
      utxos: [utxo],
      privateKey: privateKey,
      toAddress: 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
      amount: 5000,
      feeRate: 2,
      changeAddress: 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
    );

    expect(raw, startsWith('02000000000101'));
    expect(raw, contains('0014751e76e8199196d454941c45d1b3a323f1433bd6'));
    expect(
      raw,
      contains(
        '210279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
      ),
    );
    expect(raw, endsWith('00000000'));
  });

  test('P2PKH UTXOから署名済みlegacy取引を構築する', () {
    final privateKey = Uint8List(32)..[31] = 1;
    final utxo = BitcoinUtxo(
      txid: '22' * 32,
      vout: 0,
      value: 10000,
      confirmed: true,
      scriptPubkey: _bytes(
        '76a914751e76e8199196d454941c45d1b3a323f1433bd688ac',
      ),
    );

    final raw = BitcoinTransactionBuilder(network: Network.mainnet).build(
      utxos: [utxo],
      privateKey: privateKey,
      toAddress: '1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH',
      amount: 5000,
      feeRate: 2,
      changeAddress: '1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH',
    );

    expect(raw, startsWith('0200000001'));
    expect(raw, isNot(startsWith('020000000001')));
    expect(
      raw,
      contains(
        '210279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
      ),
    );
    expect(raw, endsWith('00000000'));
  });

  test('秘密鍵と異なるUTXOは署名対象にしない', () {
    final privateKey = Uint8List(32)..[31] = 1;
    final utxo = BitcoinUtxo(
      txid: '33' * 32,
      vout: 0,
      value: 10000,
      confirmed: true,
      scriptPubkey: _bytes('00140000000000000000000000000000000000000000'),
    );

    expect(
      () => BitcoinTransactionBuilder(network: Network.testnet).build(
        utxos: [utxo],
        privateKey: privateKey,
        toAddress: 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
        amount: 5000,
        feeRate: 2,
        changeAddress: 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
      ),
      throwsArgumentError,
    );
  });

  test('P2PKHとP2WPKHの署名を公開鍵で検証できる', () {
    final privateKey = Uint8List(32)..[31] = 1;
    final generator = Secp256k1KeyPairGenerator();
    final compressed = generator.derivePublicKey(privateKey, compressed: true);
    final uncompressed = generator.derivePublicKey(
      privateKey,
      compressed: false,
    );
    final signer = BitcoinTransactionSigner();
    final curve = ECCurve_secp256k1();
    final verifier = ECDSASigner()
      ..init(
        false,
        PublicKeyParameter<ECPublicKey>(ECPublicKey(curve.G, curve)),
      );

    for (final script in [
      '76a914751e76e8199196d454941c45d1b3a323f1433bd688ac',
      '0014751e76e8199196d454941c45d1b3a323f1433bd6',
    ]) {
      final utxo = BitcoinUtxo(
        txid: '44' * 32,
        vout: 0,
        value: 10000,
        confirmed: true,
        scriptPubkey: _bytes(script),
      );
      final transaction = BitcoinTransaction(
        inputs: [BitcoinInputBuilder().build(utxo)],
        outputs: [TxOutput(value: 9000, scriptPubKey: utxo.scriptPubkey)],
      );
      final digest = script.startsWith('76')
          ? signer.signatureHashLegacy(transaction, 0, utxo.scriptPubkey)
          : signer.signatureHashSegwitV0(
              transaction,
              0,
              utxo.value,
              utxo.scriptPubkey.sublist(2),
            );

      signer.sign(
        transaction: transaction,
        utxos: [utxo],
        privateKey: privateKey,
        compressedPublicKey: compressed,
        uncompressedPublicKey: uncompressed,
      );

      final signature = script.startsWith('76')
          ? transaction.inputs.single.scriptSig.sublist(
              1,
              1 + transaction.inputs.single.scriptSig[0],
            )
          : transaction.inputs.single.witness!.first;
      expect(signature.last, 0x01);
      expect(signature[0], 0x30);
      final rLength = signature[3];
      final r = BigInt.parse(
        convert.hex.encode(signature.sublist(4, 4 + rLength)),
        radix: 16,
      );
      final sLengthOffset = 5 + rLength;
      expect(signature[sLengthOffset - 1], 0x02);
      final sLength = signature[sLengthOffset];
      final s = BigInt.parse(
        convert.hex.encode(
          signature.sublist(sLengthOffset + 1, sLengthOffset + 1 + sLength),
        ),
        radix: 16,
      );
      expect(s <= curve.n ~/ BigInt.two, isTrue);
      expect(verifier.verifySignature(digest, ECSignature(r, s)), isTrue);
    }
  });
}
