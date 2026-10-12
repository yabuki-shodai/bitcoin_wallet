import 'dart:typed_data';

import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_address_decoder.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address_type.dart';
import 'models/tx_output.dart';

class BitcoinOutputBuilder {
  final Network network;

  BitcoinOutputBuilder({required this.network});

  TxOutput build(String address, int amount) {
    final decoded = BitcoinAddressDecoder().decode(address);
    if (decoded.network != network) {
      throw ArgumentError.value(address, 'address', 'ウォレットとネットワークが一致しません');
    }

    final hash = decoded.publicKeyHash;
    final scriptPubKey = switch (decoded.type) {
      BitcoinAddressType.p2pkh => Uint8List.fromList([
        0x76, // OP_DUP
        0xa9, // OP_HASH160
        0x14, // 20-byte push
        ...hash,
        0x88, // OP_EQUALVERIFY
        0xac, // OP_CHECKSIG
      ]),
      BitcoinAddressType.p2wpkh => Uint8List.fromList([
        0x00, // OP_0
        0x14, // 20-byte push
        ...hash,
      ]),
      _ => throw UnsupportedError('未対応のアドレスタイプです: ${decoded.type}'),
    };

    return TxOutput(
      value: amount,
      scriptPubKey: scriptPubKey.asUnmodifiableView(),
    );
  }
}
