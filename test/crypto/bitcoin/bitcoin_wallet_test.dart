import 'dart:async';
import 'dart:typed_data';

import 'package:bitcoin_wallet/src/core/secure/private_key_store.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_wallet.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_blockchain_client.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_utxo.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_history_entry.dart';
import 'package:convert/convert.dart' as convert;
import 'package:crypto/crypto.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address_type.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/repository/bitcoin_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class TestKeyStore extends PrivateKeyStore {
  TestKeyStore() : super(asset: 'bitcoin');
  final saved = Completer<void>();
  int reads = 0;
  Uint8List? privateKey;

  @override
  Future<Uint8List?> readPrivateKey(String address) async {
    reads++;
    return privateKey;
  }

  @override
  Future<void> savePrivateKey(String address, Uint8List privateKey) =>
      saved.future;
}

class TestRepository implements BitcoinAddressRepository {
  @override
  Future<List<BitcoinAddress>> getAddresses() async => [];

  @override
  Future<void> saveAddress(BitcoinAddress address) async {}

  @override
  Future<void> deleteAddress(BitcoinAddress address) async {}
}

class TestBlockchainClient extends BitcoinBlockchainClient {
  TestBlockchainClient() : super(network: Network.mainnet);
  int reads = 0;
  int historyReads = 0;
  List<BitcoinHistoryEntry> history = [];
  final sent = <String>[];
  List<BitcoinUtxo> utxos = [
    BitcoinUtxo(
      txid: '22' * 32,
      vout: 0,
      value: 10000,
      confirmed: true,
      scriptPubkey: Uint8List.fromList(
        convert.hex.decode(
          '76a914751e76e8199196d454941c45d1b3a323f1433bd688ac',
        ),
      ),
    ),
  ];

  @override
  Future<List<BitcoinUtxo>> getUtxos(String address) async {
    reads++;
    return utxos;
  }

  @override
  Future<List<BitcoinHistoryEntry>> getTransactionHistory(
    String address,
  ) async {
    historyReads++;
    return history;
  }

  @override
  Future<String> broadcastTransaction(String rawHex) async {
    sent.add(rawHex);
    return convert.hex.encode(
      sha256
          .convert(sha256.convert(convert.hex.decode(rawHex)).bytes)
          .bytes
          .reversed
          .toList(),
    );
  }
}

void main() {
  BitcoinWallet createWallet(
    Network network, {
    TestKeyStore? store,
    TestBlockchainClient? client,
  }) => BitcoinWallet(
    network: network,
    repostory: TestRepository(),
    store: store ?? TestKeyStore(),
    blockchainClient: client,
  );

  const mainnetAddress = '1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH';

  BitcoinAddress source(Network network) => BitcoinAddress(
    address: mainnetAddress,
    network: network,
    publicKey: Uint8List(33),
    type: BitcoinAddressType.p2pkh,
  );

  test('不正な入力は例外にし秘密鍵・UTXOを取得しない', () async {
    final store = TestKeyStore();
    final client = TestBlockchainClient();
    addTearDown(client.close);
    final wallet = createWallet(Network.mainnet, store: store, client: client);
    await expectLater(
      wallet.preparePayment(
        from: source(Network.mainnet),
        toAddress: 'invalid',
        amount: '0.00000001',
        feeRate: '0',
      ),
      throwsA(
        isA<ArgumentError>().having((error) => error.name, 'name', 'toAddress'),
      ),
    );
    expect(store.reads, 0);
    expect(client.reads, 0);
  });

  test('送金操作が宛先・金額・手数料率の検証を担当する', () async {
    final store = TestKeyStore();
    final wallet = createWallet(Network.mainnet, store: store);
    for (final address in [
      '1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMJ',
      '3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy',
    ]) {
      await expectLater(
        wallet.preparePayment(
          from: source(Network.mainnet),
          toAddress: address,
          amount: '0.00000546',
          feeRate: '2',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'toAddress',
          ),
        ),
      );
    }
    await expectLater(
      createWallet(Network.testnet).preparePayment(
        from: source(Network.testnet),
        toAddress: mainnetAddress,
        amount: '0.00000546',
        feeRate: '2',
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('ネットワーク'),
        ),
      ),
    );
    for (final amount in [
      '0',
      '-1',
      '0.000000001',
      '21000000.00000001',
      '1e2',
      'abc',
      '0.00000545',
    ]) {
      await expectLater(
        wallet.preparePayment(
          from: source(Network.mainnet),
          toAddress: mainnetAddress,
          amount: amount,
          feeRate: '2',
        ),
        throwsA(
          isA<ArgumentError>().having((error) => error.name, 'name', 'amount'),
        ),
      );
    }
    for (final rate in ['0', '-1', '1.5', '+2', 'abc']) {
      await expectLater(
        wallet.preparePayment(
          from: source(Network.mainnet),
          toAddress: mainnetAddress,
          amount: '0.00000546',
          feeRate: rate,
        ),
        throwsA(
          isA<ArgumentError>().having((error) => error.name, 'name', 'feeRate'),
        ),
      );
    }
    expect(store.reads, 0);
    for (final amount in ['0.00000546', '21000000']) {
      await expectLater(
        wallet.preparePayment(
          from: source(Network.mainnet),
          toAddress: mainnetAddress,
          amount: amount,
          feeRate: '2',
        ),
        throwsStateError,
      );
    }
    expect(store.reads, 2);
  });

  test('入力文字列から署名し確認用の値を返して同じ取引を送信する', () async {
    final store = TestKeyStore()..privateKey = (Uint8List(32)..[31] = 1);
    final client = TestBlockchainClient();
    addTearDown(client.close);
    final wallet = createWallet(Network.mainnet, store: store, client: client);
    final result = await wallet.preparePayment(
      from: source(Network.mainnet),
      toAddress: ' $mainnetAddress ',
      amount: ' 0.00009800 ',
      feeRate: ' 1 ',
    );
    final payment = result;
    expect(payment.toAddress, mainnetAddress);
    expect(payment.amountText, '0.00009800 BTC');
    expect(payment.feeText, '0.00000200 BTC (200 sat)');
    expect(payment.totalText, '0.00010000 BTC');
    expect(payment.feeRateText, matches(RegExp(r'^\d+\.\d{2} sat/vB$')));
    expect(
      payment.explorerUrl.toString(),
      'https://blockstream.info/tx/${payment.txid}',
    );
    expect(await wallet.sendPayment(payment), payment.txid);
    expect(await wallet.sendPayment(payment), payment.txid);
    expect(client.sent, [payment.rawHex, payment.rawHex]);
  });

  test('残高取得がBTC表示とUTXO表示を整形する', () async {
    final client = TestBlockchainClient();
    addTearDown(client.close);
    client.utxos = [
      client.utxos.first,
      client.utxos.first.copyWith(txid: '33' * 32, value: 1, confirmed: false),
    ];
    final wallet = createWallet(Network.mainnet, client: client);
    final balance = await wallet.getBalance(source(Network.mainnet));
    expect(balance.totalText, '0.00010001 BTC');
    expect(balance.confirmedText, '0.00010000 BTC');
    expect(balance.utxos.last.valueText, '0.00000001 BTC');
    expect(balance.utxos.last.confirmed, isFalse);
    client.utxos = [];
    expect(
      (await wallet.getBalance(source(Network.mainnet))).totalText,
      '0.00000000 BTC',
    );
  });

  test('履歴の入出金とゼロ残高変化を表示用に変換する', () async {
    final confirmedAt = DateTime.utc(2026, 10, 14);
    final client = TestBlockchainClient()
      ..history = [
        BitcoinHistoryEntry(
          txid: 'incoming',
          balanceChange: 100000001,
          confirmed: true,
          confirmedAt: confirmedAt,
        ),
        const BitcoinHistoryEntry(
          txid: 'outgoing',
          balanceChange: -6000,
          confirmed: false,
        ),
        const BitcoinHistoryEntry(
          txid: 'zero',
          balanceChange: 0,
          confirmed: false,
        ),
      ];
    addTearDown(client.close);
    final wallet = createWallet(Network.mainnet, client: client);
    final history = await wallet.getTransactionHistory(source(Network.mainnet));
    expect(history.map((entry) => entry.direction), ['入金', '出金', '残高変化なし']);
    expect(history.map((entry) => entry.amountText), [
      '+1.00000001 BTC',
      '-0.00006000 BTC',
      '0.00000000 BTC',
    ]);
    expect(history.map((entry) => entry.txid), [
      'incoming',
      'outgoing',
      'zero',
    ]);
    expect(history.first.confirmed, isTrue);
    expect(history.first.confirmedAt, confirmedAt);
    expect(history[1].confirmed, isFalse);
    expect(history[1].confirmedAt, isNull);

    client.history = [];
    expect(
      await wallet.getTransactionHistory(source(Network.mainnet)),
      isEmpty,
    );
  });

  test('履歴取得時はネットワーク違いを通信前に拒否する', () async {
    final client = TestBlockchainClient();
    addTearDown(client.close);
    final wallet = createWallet(Network.mainnet, client: client);
    await expectLater(
      wallet.getTransactionHistory(source(Network.testnet)),
      throwsArgumentError,
    );
    expect(client.historyReads, 0);
  });

  test('ネットワークに対応したExplorerのURLを生成する', () {
    final mainnet = createWallet(Network.mainnet);
    final testnet = createWallet(Network.testnet);
    final address = BitcoinAddress(
      address: mainnetAddress,
      network: Network.mainnet,
      publicKey: Uint8List(33),
      type: BitcoinAddressType.p2pkh,
    );
    expect(
      mainnet.addressExplorerUrl(address).toString(),
      'https://blockstream.info/address/$mainnetAddress',
    );
    expect(
      testnet
          .addressExplorerUrl(address.copyWith(network: Network.testnet))
          .toString(),
      'https://mempool.space/testnet4/address/$mainnetAddress',
    );
    expect(
      mainnet.transactionExplorerUrl('abc').toString(),
      'https://blockstream.info/tx/abc',
    );
    expect(
      testnet.transactionExplorerUrl('abc').toString(),
      'https://mempool.space/testnet4/tx/abc',
    );
  });

  test('秘密鍵の保存完了を待ち、指定ネットワークと名前で生成する', () async {
    final store = TestKeyStore();
    final wallet = BitcoinWallet(
      network: Network.mainnet,
      repostory: TestRepository(),
      store: store,
    );
    bool completed = false;
    final generation = wallet.generateAddress('貯蓄用').then((address) {
      completed = true;
      return address;
    });
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    store.saved.complete();
    final address = await generation;
    expect(address.network, Network.mainnet);
    expect(address.address, startsWith('bc1'));
    expect(address.displayName, '貯蓄用');
  });

  test('秘密鍵の保存失敗を生成の失敗として返す', () async {
    final store = TestKeyStore();
    final wallet = BitcoinWallet(
      network: Network.testnet,
      repostory: TestRepository(),
      store: store,
    );
    final expectation = expectLater(
      wallet.generateAddress('普段使い'),
      throwsStateError,
    );
    await Future<void>.delayed(Duration.zero);
    store.saved.completeError(StateError('secure storage failed'));
    await expectation;
  });

  test('選んだP2PKH形式でアドレスを生成する', () async {
    final store = TestKeyStore();
    final wallet = BitcoinWallet(
      network: Network.testnet,
      repostory: TestRepository(),
      store: store,
    );
    final generation = wallet.generateAddressOfType(
      '普段使い',
      BitcoinAddressType.p2pkh,
    );
    store.saved.complete();
    final address = await generation;
    expect(address.type, BitcoinAddressType.p2pkh);
    expect(address.address, anyOf(startsWith('m'), startsWith('n')));
    expect(address.displayName, '普段使い');
  });
}
