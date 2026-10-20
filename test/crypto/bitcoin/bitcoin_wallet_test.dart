import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_transaction_serializer.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:bitcoin_wallet/src/core/secure/private_key_store.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_wallet.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_blockchain_client.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_utxo.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_history_entry.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_transaction.dart';
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
  final transactions = <String, BitcoinTransaction>{};
  final confirmations = <String, bool>{};
  final spends = <String, List<String?>>{};
  String? broadcastTxid;

  @override
  Future<BitcoinTransaction> getTransaction(String txid) async =>
      transactions[txid]!;

  @override
  Future<bool?> getTransactionConfirmation(String txid) async =>
      confirmations[txid];

  @override
  Future<List<String?>> getSpendingTransactionIds(String txid) async =>
      spends[txid]!;
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
    if (broadcastTxid != null) return broadcastTxid!;
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

  test('宛先変更を検証して送信し、再試行時は受理済みの取引を再送しない', () async {
    final store = TestKeyStore()..privateKey = (Uint8List(32)..[31] = 1);
    final client = TestBlockchainClient();
    addTearDown(client.close);
    final wallet = createWallet(Network.mainnet, store: store, client: client);
    final from = source(Network.mainnet);
    final original = await wallet.preparePayment(
      from: from,
      toAddress: mainnetAddress,
      amount: '0.00005000',
      feeRate: '2',
      replaceable: true,
    );
    client.transactions[original.txid] = original;
    client.confirmations[original.txid] = false;
    client.spends[original.txid] = [null, null];
    client.spends[original.inputs.single.utxo.txid] = [original.txid];
    final replacement = await wallet.prepareReplacement(
      from: from,
      txid: original.txid,
      toAddress: 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
      feeRate: '2',
    );
    final altered = replacement.copyWith(
      outputs: [
        replacement.outputs.first.copyWith(value: 4000),
        replacement.outputs[1],
      ],
    );
    await expectLater(
      wallet.sendReplacement(
        from: from,
        originalTxid: original.txid,
        payment: altered,
      ),
      throwsStateError,
    );
    expect(client.sent, isEmpty);
    client.broadcastTxid = replacement.txid;
    expect(
      await wallet.sendReplacement(
        from: from,
        originalTxid: original.txid,
        payment: replacement,
      ),
      replacement.txid,
    );
    expect(client.sent, [replacement.rawHex]);
    client.confirmations[replacement.txid] = false;
    client.transactions.remove(original.txid);
    expect(
      await wallet.sendReplacement(
        from: from,
        originalTxid: original.txid,
        payment: replacement,
      ),
      replacement.txid,
    );
    expect(client.sent, hasLength(1));
  });

  test('上書き成功は全入力の使用先とAPIの取引存在を確認して判定する', () async {
    final store = TestKeyStore()..privateKey = (Uint8List(32)..[31] = 1);
    final client = TestBlockchainClient();
    addTearDown(client.close);
    client.utxos = [
      client.utxos.first.copyWith(value: 3000),
      client.utxos.first.copyWith(value: 3000, vout: 1),
    ];
    final wallet = createWallet(Network.mainnet, store: store, client: client);
    final from = source(Network.mainnet);
    final original = await wallet.preparePayment(
      from: from,
      toAddress: mainnetAddress,
      amount: '0.00005000',
      feeRate: '1',
      replaceable: true,
    );
    expect(original.inputs, hasLength(2));
    client.transactions[original.txid] = original;
    client.confirmations[original.txid] = false;
    client.spends[original.txid] = [null, null];
    final parentTxid = original.inputs.first.utxo.txid;
    client.spends[parentTxid] = [original.txid, original.txid];
    final replacement = await wallet.prepareReplacement(
      from: from,
      txid: original.txid,
      toAddress: mainnetAddress,
      feeRate: '2',
    );
    Future<BitcoinReplacementStatus> check() =>
        wallet.getReplacementStatus(original: original, payment: replacement);
    expect(await check(), BitcoinReplacementStatus.notFound);
    client.confirmations[replacement.txid] = false;
    expect(await check(), BitcoinReplacementStatus.originalActive);
    client.spends[parentTxid] = [replacement.txid, 'another-transaction'];
    expect(await check(), BitcoinReplacementStatus.conflicted);
    client.spends[parentTxid] = [replacement.txid, original.txid];
    expect(await check(), BitcoinReplacementStatus.pending);
    client.spends[parentTxid] = [replacement.txid, null];
    expect(await check(), BitcoinReplacementStatus.pending);
    client.spends[parentTxid] = [replacement.txid];
    expect(await check(), BitcoinReplacementStatus.pending);
    client.spends[parentTxid] = [replacement.txid, replacement.txid];
    client.confirmations.remove(original.txid);
    expect(await check(), BitcoinReplacementStatus.accepted);
    client.confirmations[replacement.txid] = true;
    expect(await check(), BitcoinReplacementStatus.confirmed);
    client.confirmations[original.txid] = true;
    expect(await check(), BitcoinReplacementStatus.conflicted);
    await expectLater(
      wallet.getReplacementStatus(original: original, payment: original),
      throwsArgumentError,
    );
    final differentInput = replacement.copyWith(
      inputs: [
        replacement.inputs.first.copyWith(
          utxo: replacement.inputs.first.utxo.copyWith(vout: 2),
        ),
        replacement.inputs.last,
      ],
    );
    await expectLater(
      wallet.getReplacementStatus(original: original, payment: differentInput),
      throwsArgumentError,
    );
    expect(client.sent, isEmpty);
  });

  test('承認・子取引・別の置換を送信直前に再確認する', () async {
    final store = TestKeyStore()..privateKey = (Uint8List(32)..[31] = 1);
    final client = TestBlockchainClient();
    addTearDown(client.close);
    final wallet = createWallet(Network.mainnet, store: store, client: client);
    final from = source(Network.mainnet);
    final normal = await wallet.preparePayment(
      from: from,
      toAddress: mainnetAddress,
      amount: '0.00005000',
      feeRate: '2',
    );
    client.transactions[normal.txid] = normal;
    await expectLater(
      wallet.getReplaceableTransaction(from: from, txid: normal.txid),
      throwsStateError,
    );
    final original = await wallet.preparePayment(
      from: from,
      toAddress: mainnetAddress,
      amount: '0.00005000',
      feeRate: '2',
      replaceable: true,
    );
    client.transactions[original.txid] = original;
    client.confirmations[original.txid] = false;
    client.spends[original.txid] = [null, null];
    client.spends[original.inputs.single.utxo.txid] = [original.txid];
    final replacement = await wallet.prepareReplacement(
      from: from,
      txid: original.txid,
      toAddress: mainnetAddress,
      feeRate: '5',
    );
    client.confirmations[original.txid] = true;
    await expectLater(
      wallet.sendReplacement(
        from: from,
        originalTxid: original.txid,
        payment: replacement,
      ),
      throwsStateError,
    );
    client.confirmations[original.txid] = false;
    client.spends[original.txid] = [null, 'child'];
    await expectLater(
      wallet.sendReplacement(
        from: from,
        originalTxid: original.txid,
        payment: replacement,
      ),
      throwsStateError,
    );
    client.spends[original.txid] = [null, null];
    client.spends[original.inputs.single.utxo.txid] = ['another-replacement'];
    await expectLater(
      wallet.sendReplacement(
        from: from,
        originalTxid: original.txid,
        payment: replacement,
      ),
      throwsStateError,
    );
    expect(client.sent, isEmpty);
  });

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

  test('入力文字列から署名済み取引を返し同じ取引を送信する', () async {
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
    expect(payment.outputs.single.value, 9800);
    expect(payment.inputs.single.utxo, client.utxos.single);
    expect(payment.fee, 200);
    expect(payment.virtualSize, greaterThan(0));
    expect(await wallet.sendPayment(payment), payment.txid);
    expect(await wallet.sendPayment(payment), payment.txid);
    expect(client.sent, [payment.rawHex, payment.rawHex]);
  });

  test('署名前の取引は送信しない', () async {
    final client = TestBlockchainClient();
    addTearDown(client.close);
    final store = TestKeyStore()..privateKey = (Uint8List(32)..[31] = 1);
    final wallet = createWallet(Network.mainnet, client: client, store: store);
    final payment = await wallet.preparePayment(
      from: source(Network.mainnet),
      toAddress: mainnetAddress,
      amount: '0.00009800',
      feeRate: '1',
    );
    final unsigned = payment.copyWith(
      inputs: [payment.inputs.single.copyWith(scriptSig: [], witness: null)],
    );
    await expectLater(wallet.sendPayment(unsigned), throwsStateError);
    expect(client.sent, isEmpty);
  });

  test('アドレスのUTXO情報をそのまま返す', () async {
    final client = TestBlockchainClient();
    addTearDown(client.close);
    client.utxos = [
      client.utxos.first,
      client.utxos.first.copyWith(txid: '33' * 32, value: 1, confirmed: false),
    ];
    final wallet = createWallet(Network.mainnet, client: client);
    final utxos = await wallet.getUtxos(source(Network.mainnet));
    expect(utxos, client.utxos);
    expect(utxos.last.value, 1);
    expect(utxos.last.confirmed, isFalse);
    client.utxos = [];
    expect(await wallet.getUtxos(source(Network.mainnet)), isEmpty);
  });

  test('UTXO取得時はネットワーク違いを通信前に拒否する', () async {
    final client = TestBlockchainClient();
    addTearDown(client.close);
    final wallet = createWallet(Network.mainnet, client: client);
    await expectLater(
      wallet.getUtxos(source(Network.testnet)),
      throwsArgumentError,
    );
    expect(client.reads, 0);
  });

  test('履歴の入出金とゼロ残高変化をsatoshiのまま返す', () async {
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
    expect(history, client.history);
    expect(history.map((entry) => entry.balanceChange), [100000001, -6000, 0]);
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
