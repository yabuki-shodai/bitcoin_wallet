import 'dart:typed_data';

import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address_type.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_utxo.dart';
import 'package:convert/convert.dart' as convert;
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

import 'bitcoin_transaction_serializer.dart';
import 'models/bitcoin_transaction.dart';
import 'models/tx_input.dart';

class BitcoinTransactionSigner {
  static const int sighashAll = 0x01;

  BitcoinTransaction sign({
    required BitcoinTransaction transaction,
    required List<BitcoinUtxo> utxos,
    required Uint8List privateKey,
    required Uint8List compressedPublicKey,
    required Uint8List uncompressedPublicKey,
  }) {
    if (transaction.inputs.length != utxos.length) {
      throw ArgumentError('InputとUTXOの数が一致しません');
    }

    final signedInputs = <TxInput>[];
    for (var index = 0; index < utxos.length; index++) {
      final input = transaction.inputs[index];
      final utxo = utxos[index];
      final type = scriptType(utxo.scriptPubkey);
      final publicKey = matchingPublicKey(
        utxo,
        compressedPublicKey,
        uncompressedPublicKey,
      );
      final digest = switch (type) {
        BitcoinAddressType.p2pkh => signatureHashLegacy(
          transaction,
          index,
          utxo.scriptPubkey,
        ),
        BitcoinAddressType.p2wpkh => signatureHashSegwitV0(
          transaction,
          index,
          utxo.value,
          utxo.scriptPubkey.sublist(2),
        ),
        _ => throw UnsupportedError('未対応のUTXOスクリプトです'),
      };
      final signature = Uint8List.fromList([
        ..._signEcdsa(digest, privateKey),
        sighashAll,
      ]).asUnmodifiableView();
      final txid = Uint8List.fromList(input.txid).asUnmodifiableView();

      if (type == BitcoinAddressType.p2pkh) {
        signedInputs.add(
          input.copyWith(
            txid: txid,
            scriptSig: List<int>.unmodifiable([
              signature.length,
              ...signature,
              publicKey.length,
              ...publicKey,
            ]),
          ),
        );
      } else {
        signedInputs.add(
          input.copyWith(
            txid: txid,
            witness: List<Uint8List>.unmodifiable([
              signature,
              Uint8List.fromList(publicKey).asUnmodifiableView(),
            ]),
          ),
        );
      }
    }
    return transaction.copyWith(inputs: List.unmodifiable(signedInputs));
  }

  Uint8List signatureHashLegacy(
    BitcoinTransaction transaction,
    int inputIndex,
    Uint8List scriptCode,
  ) {
    final preimage = <int>[
      ...uintLittleEndian(transaction.version, 4),
      ...compactSize(transaction.inputs.length),
      for (var index = 0; index < transaction.inputs.length; index++) ...[
        ...transaction.inputs[index].txid,
        ...uintLittleEndian(transaction.inputs[index].vout, 4),
        ...compactSize(index == inputIndex ? scriptCode.length : 0),
        if (index == inputIndex) ...scriptCode,
        ...uintLittleEndian(transaction.inputs[index].sequence, 4),
      ],
      ...compactSize(transaction.outputs.length),
      for (final output in transaction.outputs) ...serializeOutput(output),
      ...uintLittleEndian(transaction.lockTime, 4),
      ...uintLittleEndian(sighashAll, 4),
    ];
    return _doubleSha256(preimage);
  }

  Uint8List signatureHashSegwitV0(
    BitcoinTransaction transaction,
    int inputIndex,
    int value,
    Uint8List publicKeyHash,
  ) {
    if (publicKeyHash.length != 20) {
      throw ArgumentError.value(publicKeyHash, 'publicKeyHash');
    }
    final hashPrevouts = _doubleSha256([
      for (final input in transaction.inputs) ...[
        ...input.txid,
        ...uintLittleEndian(input.vout, 4),
      ],
    ]);
    final hashSequence = _doubleSha256([
      for (final input in transaction.inputs)
        ...uintLittleEndian(input.sequence, 4),
    ]);
    final hashOutputs = _doubleSha256([
      for (final output in transaction.outputs) ...serializeOutput(output),
    ]);
    final input = transaction.inputs[inputIndex];
    final scriptCode = <int>[0x76, 0xa9, 0x14, ...publicKeyHash, 0x88, 0xac];
    final preimage = <int>[
      ...uintLittleEndian(transaction.version, 4),
      ...hashPrevouts,
      ...hashSequence,
      ...input.txid,
      ...uintLittleEndian(input.vout, 4),
      ...compactSize(scriptCode.length),
      ...scriptCode,
      ...uintLittleEndian(value, 8),
      ...uintLittleEndian(input.sequence, 4),
      ...hashOutputs,
      ...uintLittleEndian(transaction.lockTime, 4),
      ...uintLittleEndian(sighashAll, 4),
    ];
    return _doubleSha256(preimage);
  }

  Uint8List _signEcdsa(Uint8List digest, Uint8List privateKey) {
    if (digest.length != 32 || privateKey.length != 32) {
      throw ArgumentError('署名用ハッシュと秘密鍵は32バイトである必要があります');
    }
    final curve = ECCurve_secp256k1();
    final d = BigInt.parse(convert.hex.encode(privateKey), radix: 16);
    if (d < BigInt.one || d >= curve.n) {
      throw ArgumentError.value(privateKey, 'privateKey');
    }
    final signer = ECDSASigner(null, HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter<ECPrivateKey>(ECPrivateKey(d, curve)));
    final signature = (signer.generateSignature(digest) as ECSignature)
        .normalize(curve);
    final r = _derInteger(signature.r);
    final s = _derInteger(signature.s);
    return Uint8List.fromList([
      0x30,
      r.length + s.length + 4,
      0x02,
      r.length,
      ...r,
      0x02,
      s.length,
      ...s,
    ]);
  }

  List<int> _derInteger(BigInt value) {
    var hex = value.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    final bytes = convert.hex.decode(hex);
    return bytes.first & 0x80 != 0 ? [0x00, ...bytes] : bytes;
  }

  Uint8List _doubleSha256(List<int> bytes) =>
      Uint8List.fromList(sha256.convert(sha256.convert(bytes).bytes).bytes);
}

BitcoinAddressType scriptType(Uint8List script) {
  if (script.length == 25 &&
      script[0] == 0x76 &&
      script[1] == 0xa9 &&
      script[2] == 0x14 &&
      script[23] == 0x88 &&
      script[24] == 0xac) {
    return BitcoinAddressType.p2pkh;
  }
  if (script.length == 22 && script[0] == 0x00 && script[1] == 0x14) {
    return BitcoinAddressType.p2wpkh;
  }
  throw UnsupportedError('未対応のUTXOスクリプトです');
}

Uint8List matchingPublicKey(
  BitcoinUtxo utxo,
  Uint8List compressed,
  Uint8List uncompressed,
) {
  final type = scriptType(utxo.scriptPubkey);
  final expectedHash = type == BitcoinAddressType.p2pkh
      ? utxo.scriptPubkey.sublist(3, 23)
      : utxo.scriptPubkey.sublist(2);
  if (_bytesEqual(expectedHash, _hash160(compressed))) return compressed;
  if (type == BitcoinAddressType.p2pkh &&
      _bytesEqual(expectedHash, _hash160(uncompressed))) {
    return uncompressed;
  }
  throw ArgumentError('UTXOの公開鍵ハッシュが秘密鍵と一致しません');
}

Uint8List _hash160(Uint8List bytes) =>
    RIPEMD160Digest().process(Uint8List.fromList(sha256.convert(bytes).bytes));

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
