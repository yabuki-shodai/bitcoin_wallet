import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_address_decoder.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/tx_output.dart';

class BitcoinOutputBuilder {
  final Network network;

  BitcoinOutputBuilder({required this.network});

  TxOutput build(String address, int amount) {
    return TxOutput(
      value: amount,
      scriptPubKey: BitcoinAddressDecoder().toScriptPubKey(
        address,
        network: network,
      ),
    );
  }
}
