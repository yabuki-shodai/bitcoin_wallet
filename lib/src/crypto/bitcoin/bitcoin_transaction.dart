import 'dart:typed_data';

import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_input_builder.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_output_builder.dart';

class BitcoinTransaction {
  final int version;
  final List<TxInput> inputs;
  final List<TxOutput> outputs;
  final int lockTime;

  BitcoinTransaction({
    required this.inputs,
    required this.outputs,
    this.version = 2,
    this.lockTime = 0,
  });

  bool get hasWitness =>
      inputs.any((input) => input.witness?.isNotEmpty ?? false);

  int get virtualSize {
    final baseSize = serialize(includeWitness: false).length;
    final totalSize = serialize().length;
    return (baseSize * 3 + totalSize + 3) ~/ 4;
  }

  Uint8List serialize({bool includeWitness = true}) {
    if (inputs.isEmpty || outputs.isEmpty) {
      throw StateError('取引にはInputとOutputが必要です');
    }

    final useWitness = includeWitness && hasWitness;
    return Uint8List.fromList([
      ...uintLittleEndian(version, 4),
      if (useWitness) ...[0x00, 0x01],
      ...compactSize(inputs.length),
      for (final input in inputs) ...[
        ...input.txid,
        ...uintLittleEndian(input.vout, 4),
        ...compactSize(input.scriptSig.length),
        ...input.scriptSig,
        ...uintLittleEndian(input.sequence, 4),
      ],
      ...compactSize(outputs.length),
      for (final output in outputs) ...serializeOutput(output),
      if (useWitness)
        for (final input in inputs) ...[
          ...compactSize(input.witness?.length ?? 0),
          for (final item in input.witness ?? <Uint8List>[]) ...[
            ...compactSize(item.length),
            ...item,
          ],
        ],
      ...uintLittleEndian(lockTime, 4),
    ]);
  }
}

List<int> serializeOutput(TxOutput output) => [
  ...uintLittleEndian(output.value, 8),
  ...compactSize(output.scriptPubKey.length),
  ...output.scriptPubKey,
];

List<int> uintLittleEndian(int value, int byteLength) {
  if (value < 0 || (byteLength < 8 && value >= (1 << (byteLength * 8)))) {
    throw RangeError.value(value, 'value', '指定されたバイト数に収まりません');
  }
  return List<int>.generate(
    byteLength,
    (index) => (value >> (index * 8)) & 0xff,
  );
}

List<int> compactSize(int value) {
  if (value < 0) throw RangeError.value(value, 'value');
  if (value < 0xfd) return [value];
  if (value <= 0xffff) return [0xfd, ...uintLittleEndian(value, 2)];
  if (value <= 0xffffffff) return [0xfe, ...uintLittleEndian(value, 4)];
  return [0xff, ...uintLittleEndian(value, 8)];
}
