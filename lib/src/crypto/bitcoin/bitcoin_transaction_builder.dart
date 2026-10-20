import 'dart:typed_data';

import 'package:bitcoin_wallet/src/core/builder/transaction_builder.dart';
import 'package:bitcoin_wallet/src/core/key_pair/secp256/secp256_key_generator.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_input_builder.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_output_builder.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_transaction_signer.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address_type.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_utxo.dart';

import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_transaction_serializer.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_transaction.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/tx_output.dart';

class BitcoinTransactionBuilder implements TransactionBuilder {
  static const int _minimumChange = 546;

  final Network network;

  BitcoinTransactionBuilder({required this.network});

  String build({
    required List<BitcoinUtxo> utxos,
    required Uint8List privateKey,
    required String toAddress,
    required int amount,
    required int feeRate,
    required String changeAddress,
  }) => buildPayment(
    utxos: utxos,
    privateKey: privateKey,
    toAddress: toAddress,
    amount: amount,
    feeRate: feeRate,
    changeAddress: changeAddress,
  ).rawHex;

  BitcoinTransaction buildPayment({
    required List<BitcoinUtxo> utxos,
    required Uint8List privateKey,
    required String toAddress,
    required int amount,
    required int feeRate,
    required String changeAddress,
    bool replaceable = false,
  }) {
    if (amount <= 0) throw RangeError.value(amount, 'amount');
    if (feeRate <= 0) throw RangeError.value(feeRate, 'feeRate');

    final keyGenerator = Secp256k1KeyPairGenerator();
    final compressedPublicKey = keyGenerator.derivePublicKey(
      privateKey,
      compressed: true,
    );
    final uncompressedPublicKey = keyGenerator.derivePublicKey(
      privateKey,
      compressed: false,
    );

    final candidates = utxos.where((utxo) => utxo.confirmed).toList();
    if (candidates.isEmpty) throw StateError('利用可能なUTXOがありません');
    final outpoints = <String>{};
    for (final utxo in candidates) {
      if (!outpoints.add('${utxo.txid.toLowerCase()}:${utxo.vout}')) {
        throw ArgumentError('UTXOが重複しています');
      }
      matchingPublicKey(utxo, compressedPublicKey, uncompressedPublicKey);
    }
    _compressedP2pkh = candidates
        .where(
          (u) =>
              scriptType(u.scriptPubkey) == BitcoinAddressType.p2pkh &&
              matchingPublicKey(
                    u,
                    compressedPublicKey,
                    uncompressedPublicKey,
                  ).length ==
                  33,
        )
        .map((u) => '${u.txid}:${u.vout}')
        .toSet();

    final outputBuilder = BitcoinOutputBuilder(network: network);
    final paymentOutput = outputBuilder.build(toAddress, amount);
    if (amount < _minimumChange) {
      throw RangeError.value(amount, 'amount', 'dust未満の送金額です');
    }
    final changeOutput = outputBuilder.build(changeAddress, 0);
    final selected = _selectUtxos(
      utxos: candidates,
      amountSats: paymentOutput.value,
      feeRateSatPerVbyte: feeRate,
      outputsForEstimate: [paymentOutput, changeOutput],
    );

    final inputTotal = selected.fold<int>(0, (sum, utxo) => sum + utxo.value);
    final feeWithChange =
        _estimateVbytes(selected, [paymentOutput, changeOutput]) * feeRate;
    final changeValue = inputTotal - amount - feeWithChange;
    final outputs = changeValue >= _minimumChange
        ? [
            paymentOutput,
            TxOutput(
              value: changeValue,
              scriptPubKey: changeOutput.scriptPubKey,
            ),
          ]
        : [paymentOutput];

    if (outputs.length == 1) {
      final minimumFee = _estimateVbytes(selected, outputs) * feeRate;
      if (inputTotal - amount < minimumFee) {
        throw StateError('手数料を含む残高が不足しています');
      }
    }

    final inputBuilder = BitcoinInputBuilder();
    final unsignedTransaction = BitcoinTransaction(
      inputs: List.unmodifiable(
        selected.map((utxo) {
          final input = inputBuilder.build(utxo);
          return replaceable ? input.copyWith(sequence: 0xfffffffd) : input;
        }),
      ),
      outputs: List.unmodifiable(outputs),
    );
    final transaction = BitcoinTransactionSigner().sign(
      transaction: unsignedTransaction,
      privateKey: privateKey,
      compressedPublicKey: compressedPublicKey,
      uncompressedPublicKey: uncompressedPublicKey,
    );

    final actualFee = transaction.fee;
    final virtualSize = transaction.virtualSize;
    if (actualFee < virtualSize * feeRate) {
      throw StateError('署名後の取引手数料が指定レートを下回りました');
    }

    return transaction;
  }

  BitcoinTransaction buildReplacement({
    required BitcoinTransaction original,
    required String toAddress,
    required Uint8List privateKey,
    required int feeRate,
  }) {
    if (feeRate <= 0) throw ArgumentError('1以上の整数を入力してください');
    if (original.inputs.isEmpty ||
        original.inputs.any((input) => input.sequence != 0xfffffffd)) {
      throw StateError('変更可能な送金ではありません');
    }
    if (original.outputs.length != 2) {
      throw StateError('送金の変更に利用できるお釣りがありません');
    }
    final paymentOutput = BitcoinOutputBuilder(
      network: network,
    ).build(toAddress, original.outputs.first.value);
    if (paymentOutput == original.outputs.first &&
        feeRate * original.virtualSize <= original.fee) {
      throw ArgumentError('現在より高い手数料率を入力してください');
    }
    final keyGenerator = Secp256k1KeyPairGenerator();
    final compressed = keyGenerator.derivePublicKey(
      privateKey,
      compressed: true,
    );
    final uncompressed = keyGenerator.derivePublicKey(
      privateKey,
      compressed: false,
    );
    final utxos = original.inputs.map((input) => input.utxo).toList();
    _compressedP2pkh = {
      for (final utxo in utxos)
        if (scriptType(utxo.scriptPubkey) == BitcoinAddressType.p2pkh &&
            matchingPublicKey(utxo, compressed, uncompressed).length == 33)
          '${utxo.txid}:${utxo.vout}',
    };
    final size = _estimateVbytes(utxos, [paymentOutput, original.outputs[1]]);
    // 1 sat/vBの追加分を確保し、旧取引の手数料率も必ず上回る。
    var fee = size * feeRate;
    final minimumFee = original.fee + size;
    if (fee < minimumFee) fee = minimumFee;
    final minimumRateFee = original.fee * size ~/ original.virtualSize + 1;
    if (fee < minimumRateFee) fee = minimumRateFee;
    final change = original.outputs[1];
    final changeValue = change.value - (fee - original.fee);
    if (changeValue < 0) throw StateError('手数料の変更に必要なお釣りが不足しています');
    final replacement = original.copyWith(
      inputs: List.unmodifiable(
        original.inputs.map(
          (input) => input.copyWith(scriptSig: const [], witness: null),
        ),
      ),
      outputs: List.unmodifiable([
        paymentOutput,
        if (changeValue >= _minimumChange) change.copyWith(value: changeValue),
      ]),
    );
    final signed = BitcoinTransactionSigner().sign(
      transaction: replacement,
      privateKey: privateKey,
      compressedPublicKey: compressed,
      uncompressedPublicKey: uncompressed,
    );
    if (signed.fee < signed.virtualSize * feeRate ||
        signed.fee < original.fee + signed.virtualSize ||
        signed.fee * original.virtualSize <=
            original.fee * signed.virtualSize) {
      throw StateError('置換取引の手数料が不足しています');
    }
    return signed;
  }

  Set<String> _compressedP2pkh = {};

  List<BitcoinUtxo> _selectUtxos({
    required List<BitcoinUtxo> utxos,
    required int amountSats,
    required int feeRateSatPerVbyte,
    required List<TxOutput> outputsForEstimate,
  }) {
    final sorted = List<BitcoinUtxo>.from(utxos)
      ..sort((a, b) => b.value.compareTo(a.value));
    final selected = <BitcoinUtxo>[];
    var total = 0;

    for (final utxo in sorted) {
      if (utxo.value <= 0) continue;
      selected.add(utxo);
      total += utxo.value;
      final fee =
          _estimateVbytes(selected, outputsForEstimate) * feeRateSatPerVbyte;
      if (total >= amountSats + fee) return selected;

      final feeWithoutChange =
          _estimateVbytes(selected, [outputsForEstimate.first]) *
          feeRateSatPerVbyte;
      if (total >= amountSats + feeWithoutChange) return selected;
    }
    throw StateError('手数料を含む残高が不足しています');
  }

  int _estimateVbytes(List<BitcoinUtxo> inputs, List<TxOutput> outputs) {
    var baseSize = 4 + compactSize(inputs.length).length;
    var witnessSize = 0;
    var hasWitness = false;

    for (final input in inputs) {
      switch (scriptType(input.scriptPubkey)) {
        case BitcoinAddressType.p2pkh:
          baseSize += _compressedP2pkh.contains('${input.txid}:${input.vout}')
              ? 149
              : 181;
          witnessSize += 1; // SegWit取引での空のwitness
        case BitcoinAddressType.p2wpkh:
          baseSize += 41;
          witnessSize += 109; // 最大73バイト署名と33バイト公開鍵
          hasWitness = true;
        default:
          throw UnsupportedError('未対応のUTXOスクリプトです');
      }
    }

    baseSize += compactSize(outputs.length).length + 4;
    for (final output in outputs) {
      baseSize += serializeOutput(output).length;
    }

    final weight = baseSize * 4 + (hasWitness ? witnessSize + 2 : 0);
    return (weight + 3) ~/ 4;
  }
}
