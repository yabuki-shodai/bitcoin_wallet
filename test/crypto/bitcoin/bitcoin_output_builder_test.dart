import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_output_builder.dart';
import 'package:convert/convert.dart' as convert;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const hash = '751e76e8199196d454941c45d1b3a323f1433bd6';
  final builder = BitcoinOutputBuilder(network: Network.mainnet);

  test('P2PKHアドレスから25バイトのscriptPubKeyを作る', () {
    final output = builder.build('1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH', 1000);

    expect(output.value, 1000);
    expect(convert.hex.encode(output.scriptPubKey), '76a914${hash}88ac');
  });

  test('P2WPKHアドレスから22バイトのscriptPubKeyを作る', () {
    final output = builder.build(
      'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
      2000,
    );

    expect(output.value, 2000);
    expect(convert.hex.encode(output.scriptPubKey), '0014$hash');
  });

  test('ウォレットと異なるネットワークのアドレスを拒否する', () {
    expect(
      () => BitcoinOutputBuilder(
        network: Network.testnet,
      ).build('1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH', 1000),
      throwsArgumentError,
    );
  });
}
