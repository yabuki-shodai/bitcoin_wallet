import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_blockchain_client.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_transaction_serializer.dart';

import 'package:bitcoin_wallet/src/core/secure/private_key_store.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_wallet.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/index.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/repository/bitcoin_repository.dart';
import 'package:bitcoin_wallet/src/ui/pages/bitcoin/bitcoin_send_page.dart';
import 'package:bitcoin_wallet/src/ui/widgets/address/address_qr_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bitcoin_wallet/src/ui/theme/app_theme.dart';

class _Repository extends Fake implements BitcoinAddressRepository {}

class _KeyStore extends Fake implements PrivateKeyStore {}

class _StatusClient extends BitcoinBlockchainClient {
  _StatusClient() : super(network: Network.mainnet);
  Future<bool?> Function()? check;
  @override
  Future<bool?> getTransactionConfirmation(String txid) async =>
      check == null ? false : await check!();
}

class _Wallet extends BitcoinWallet {
  _Wallet()
    : super(
        network: Network.mainnet,
        repostory: _Repository(),
        store: _KeyStore(),
        blockchainClient: _StatusClient(),
      );

  final payment = BitcoinTransaction(
    inputs: [
      TxInput(
        utxo: BitcoinUtxo(
          txid: '22' * 32,
          vout: 0,
          value: 10000,
          confirmed: true,
          scriptPubkey: Uint8List.fromList([0x51]),
        ),
        scriptSig: [1],
      ),
    ],
    outputs: [
      TxOutput(value: 9800, scriptPubKey: Uint8List.fromList([0x51])),
    ],
  );
  final sent = <BitcoinTransaction>[];
  bool? lastReplaceable;
  String? replacementAddress;
  String? replacementFeeRate;
  String? loadedReplacementTxid;
  bool includeChange = true;
  Future<BitcoinReplacementStatus> Function()? checkReplacement;

  @override
  Future<BitcoinReplacementStatus> getReplacementStatus({
    required BitcoinTransaction original,
    required BitcoinTransaction payment,
  }) async => checkReplacement == null
      ? BitcoinReplacementStatus.accepted
      : await checkReplacement!();

  BitcoinTransaction get original => payment.copyWith(
    inputs: payment.inputs
        .map((input) => input.copyWith(sequence: 0xfffffffd))
        .toList(),
    outputs: [
      payment.outputs.first.copyWith(value: 5000),
      payment.outputs.first.copyWith(value: 4800),
    ],
  );

  @override
  Future<BitcoinTransaction> getReplaceableTransaction({
    required BitcoinAddress from,
    required String txid,
  }) async {
    loadedReplacementTxid = txid;
    return sent.isNotEmpty && sent.last.txid == txid ? sent.last : original;
  }

  @override
  Future<BitcoinTransaction> prepareReplacement({
    required BitcoinAddress from,
    required String txid,
    required String toAddress,
    required String feeRate,
  }) async {
    replacementAddress = toAddress;
    replacementFeeRate = feeRate;
    return original.copyWith(
      outputs: [
        original.outputs.first,
        original.outputs[1].copyWith(value: 4400),
      ],
    );
  }

  @override
  Future<String> sendReplacement({
    required BitcoinAddress from,
    required String originalTxid,
    required BitcoinTransaction payment,
  }) => sendPayment(payment);

  @override
  Future<BitcoinTransaction> preparePayment({
    required BitcoinAddress from,
    required String toAddress,
    required String amount,
    required String feeRate,
    bool replaceable = false,
  }) async {
    lastReplaceable = replaceable;
    if (!replaceable) return payment;
    return original.copyWith(
      outputs: includeChange ? original.outputs : [original.outputs.first],
    );
  }

  @override
  Future<String> sendPayment(BitcoinTransaction payment) async {
    sent.add(payment);
    if (sent.length == 1) throw StateError('connection lost');
    return payment.txid;
  }
}

void main() {
  testWidgets('変更画面では宛先と手数料を編集し金額を維持して確認・再送する', (tester) async {
    final wallet = _Wallet();
    addTearDown(wallet.blockchainClient.close);
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: BitcoinSendPage(
          from: BitcoinAddress(
            address: 'source',
            network: Network.mainnet,
            publicKey: Uint8List(33),
            type: BitcoinAddressType.p2pkh,
          ),
          wallet: wallet,
          original: const BitcoinHistoryEntry(
            txid: 'original',
            balanceChange: -5200,
            confirmed: false,
            toAddress: 'before',
            canReplace: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('送金内容を変更'), findsOneWidget);
    final amount = tester.widget<TextFormField>(
      find.byKey(const Key('send-amount')),
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('send-amount')),
              matching: find.byType(TextField),
            ),
          )
          .readOnly,
      isTrue,
    );
    expect(amount.controller!.text, '0.00005000');
    await tester.enterText(find.byKey(const Key('send-address')), 'after');
    await tester.enterText(find.byKey(const Key('send-fee-rate')), '5');
    await tester.tap(find.text('変更内容を確認'));
    await tester.pumpAndSettle();
    expect(wallet.replacementAddress, 'after');
    expect(wallet.replacementFeeRate, '5');
    expect(find.text('before'), findsOneWidget);
    expect(find.text('after'), findsOneWidget);
    expect(find.text('0.00005000 BTC'), findsOneWidget);
    expect(find.text('追加手数料'), findsOneWidget);
    expect(find.text('+400 sat'), findsOneWidget);
    await tester.tap(find.text('確認して送信'));
    await tester.pumpAndSettle();
    expect(find.text('入力を修正'), findsNothing);
    await tester.tap(find.text('同じ取引を再送信'));
    await tester.pumpAndSettle();
    expect(find.text('送信完了'), findsOneWidget);
    expect(wallet.sent[0], same(wallet.sent[1]));
    expect(find.text('変更取引を送信しました'), findsOneWidget);
    expect(find.text('ブロック承認待ち'), findsOneWidget);
    expect(find.text('手数料を上書き'), findsNothing);
    await tester.tap(find.text('取引詳細へ戻る'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('手数料を上書き'));
    await tester.tap(find.text('手数料を上書き'));
    await tester.pumpAndSettle();
    expect(wallet.loadedReplacementTxid, wallet.sent.last.txid);
    expect(find.text('送金内容を変更'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('send-address')))
          .controller!
          .text,
      'after',
    );
  });

  for (final scenario in [
    (
      status: BitcoinReplacementStatus.pending,
      communicationError: false,
      message: '取引情報への反映を待っています。状態を更新してください。',
    ),
    (
      status: BitcoinReplacementStatus.pending,
      communicationError: true,
      message: '状態を更新できませんでした。通信状態を確認して再試行してください。',
    ),
    (
      status: BitcoinReplacementStatus.notFound,
      communicationError: false,
      message: '変更取引がネットワーク上で見つかりません。状態を更新してください。',
    ),
    (
      status: BitcoinReplacementStatus.originalActive,
      communicationError: false,
      message: '変更前の取引が有効です。変更の成立をまだ確認できません。',
    ),
    (
      status: BitcoinReplacementStatus.conflicted,
      communicationError: false,
      message: '変更前の取引が承認済み、または別の取引と競合しています。変更は成立していません。',
    ),
  ]) {
    testWidgets(
      '上書き確認の理由と再確認結果を表示し再送しない: ${scenario.status}, ${scenario.communicationError}',
      (tester) async {
        final checking = Completer<BitcoinReplacementStatus>();
        final wallet = _Wallet()..checkReplacement = () => checking.future;
        addTearDown(wallet.blockchainClient.close);
        await tester.binding.setSurfaceSize(const Size(1000, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: BitcoinSendPage(
              from: BitcoinAddress(
                address: 'source',
                network: Network.mainnet,
                publicKey: Uint8List(33),
                type: BitcoinAddressType.p2pkh,
              ),
              wallet: wallet,
              original: const BitcoinHistoryEntry(
                txid: 'original',
                balanceChange: -5200,
                confirmed: false,
                toAddress: 'destination',
                canReplace: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('変更内容を確認'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('確認して送信'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('同じ取引を再送信'));
        await tester.pump();
        expect(find.text('状態を確認中…'), findsOneWidget);
        expect(find.text('上書き成功'), findsNothing);
        expect(find.text('手数料を上書き'), findsNothing);
        if (scenario.communicationError) {
          checking.completeError(StateError('connection lost'));
        } else {
          checking.complete(scenario.status);
        }
        await tester.pumpAndSettle();
        expect(find.text('変更取引を送信しました'), findsOneWidget);
        expect(find.text(scenario.message), findsOneWidget);
        expect(find.text('上書き成功'), findsNothing);
        expect(find.text('同じ取引を再送信'), findsNothing);
        expect(find.text('original'), findsNothing);
        expect(find.text('変更後のTXID'), findsOneWidget);
        wallet.checkReplacement = () async => BitcoinReplacementStatus.accepted;
        await tester.tap(find.text('状態を更新'));
        await tester.pumpAndSettle();
        expect(find.text('変更取引を送信しました'), findsOneWidget);
        expect(find.text('ブロック承認待ち'), findsOneWidget);
        wallet.checkReplacement = () async =>
            BitcoinReplacementStatus.confirmed;
        await tester.tap(find.text('状態を更新'));
        await tester.pumpAndSettle();
        expect(find.text('変更取引を送信しました'), findsOneWidget);
        expect(find.text('ブロック承認済み'), findsOneWidget);
        expect(find.text('状態を更新'), findsOneWidget);
        expect(find.text('手数料を上書き'), findsNothing);
        expect(wallet.sent, hasLength(2));
      },
    );
  }

  testWidgets('専用入口からの新規送金だけに変更可能指定を渡す', (tester) async {
    final wallet = _Wallet();
    addTearDown(wallet.blockchainClient.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BitcoinSendPage(
          from: BitcoinAddress(
            address: 'source',
            network: Network.mainnet,
            publicKey: Uint8List(33),
            type: BitcoinAddressType.p2pkh,
          ),
          wallet: wallet,
          replaceable: true,
        ),
      ),
    );
    expect(find.text('変更可能な送金'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('send-address')),
      'destination',
    );
    await tester.enterText(find.byKey(const Key('send-amount')), '0.00009800');
    await tester.tap(find.text('送金内容を確認'));
    await tester.pumpAndSettle();
    expect(wallet.lastReplaceable, isTrue);
  });

  for (final includeChange in [true, false]) {
    testWidgets('変更可能な送金の取引詳細はお釣りがある場合だけ上書きリンクを表示する: $includeChange', (
      tester,
    ) async {
      final wallet = _Wallet()..includeChange = includeChange;
      addTearDown(wallet.blockchainClient.close);
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: BitcoinSendPage(
            from: BitcoinAddress(
              address: 'source',
              network: Network.mainnet,
              publicKey: Uint8List(33),
              type: BitcoinAddressType.p2pkh,
            ),
            wallet: wallet,
            replaceable: true,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('send-address')),
        'destination',
      );
      await tester.enterText(
        find.byKey(const Key('send-amount')),
        '0.00005000',
      );
      expect(find.text('手数料を上書き'), findsNothing);
      await tester.tap(find.text('送金内容を確認'));
      await tester.pumpAndSettle();
      expect(find.text('手数料を上書き'), findsNothing);
      await tester.tap(find.text('確認して送信'));
      await tester.pumpAndSettle();
      expect(find.text('手数料を上書き'), findsNothing);
      await tester.tap(find.text('同じ取引を再送信'));
      await tester.pumpAndSettle();
      expect(find.text('送信完了'), findsOneWidget);
      expect(find.text('手数料を上書き'), findsNothing);
      await tester.tap(find.text('取引詳細へ戻る'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -1000));
      await tester.pumpAndSettle();
      expect(
        find.text('手数料を上書き'),
        includeChange ? findsOneWidget : findsNothing,
      );
      if (includeChange) {
        await tester.tap(find.text('手数料を上書き'));
        await tester.pumpAndSettle();
        expect(wallet.loadedReplacementTxid, wallet.sent.last.txid);
        expect(find.text('送金内容を変更'), findsOneWidget);
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('send-address')))
              .controller!
              .text,
          'destination',
        );
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('send-amount')))
              .controller!
              .text,
          '0.00005000',
        );
        await tester.enterText(find.byKey(const Key('send-fee-rate')), '5');
        await tester.tap(find.text('変更内容を確認'));
        await tester.pumpAndSettle();
        expect(wallet.replacementAddress, 'destination');
        expect(wallet.replacementFeeRate, '5');
      }
    });
  }

  for (final replacement in [false, true]) {
    testWidgets('小画面・拡大文字で確認と完了を表示し全文をコピーする: $replacement', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final wallet = _Wallet();
      addTearDown(wallet.blockchainClient.close);
      final destination = 'bc1q${'a' * 60}';
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.5),
              padding: const EdgeInsets.only(bottom: 34),
            ),
            child: child!,
          ),
          home: BitcoinSendPage(
            from: BitcoinAddress(
              address: 'source',
              network: Network.mainnet,
              publicKey: Uint8List(33),
              type: BitcoinAddressType.p2pkh,
            ),
            wallet: wallet,
            original: replacement
                ? BitcoinHistoryEntry(
                    txid: 'original',
                    balanceChange: -5200,
                    confirmed: false,
                    toAddress: destination,
                    canReplace: true,
                  )
                : null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (!replacement) {
        await tester.enterText(
          find.byKey(const Key('send-address')),
          destination,
        );
        await tester.enterText(
          find.byKey(const Key('send-amount')),
          '0.00009800',
        );
      }
      final review = find.text(replacement ? '変更内容を確認' : '送金内容を確認');
      await tester.scrollUntilVisible(
        review,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('送金先アドレスが変更されています'), findsNothing);
      final truncatedAddress = find.text(
        '${destination.substring(0, 12)}…${destination.substring(destination.length - 10)}',
      );
      await tester.scrollUntilVisible(
        truncatedAddress,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(truncatedAddress);
      await tester.pumpAndSettle();
      expect(copied, destination);
      expect(find.text('送金先アドレスをコピーしました'), findsOneWidget);
      if (replacement) {
        await tester.scrollUntilVisible(
          find.text('変更前の取引情報'),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('変更前の取引情報'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('original'),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('original'));
        await tester.pumpAndSettle();
        expect(copied, 'original');
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('確認して送信'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('同じ取引を再送信'));
      await tester.pumpAndSettle();
      expect(find.text('ブロック承認待ち'), findsOneWidget);
      expect(find.text('手数料を上書き'), findsNothing);
      expect(tester.takeException(), isNull);
      final txid = wallet.sent.last.txid;
      final truncatedTxid = find.text(
        '${txid.substring(0, 12)}…${txid.substring(txid.length - 10)}',
      );
      await tester.scrollUntilVisible(
        truncatedTxid,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(truncatedTxid);
      await tester.pumpAndSettle();
      expect(copied, txid);
      expect(
        find.text('${replacement ? '変更後のTXID' : 'TXID'}をコピーしました'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('状態を更新'));
      await tester.pumpAndSettle();
      expect(find.text('ブロック承認待ち'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('通常送金の状態更新は待機・失敗・未検出・承認済みを区別し再送しない', (tester) async {
    final wallet = _Wallet();
    addTearDown(wallet.blockchainClient.close);
    final client = wallet.blockchainClient as _StatusClient;
    await tester.pumpWidget(
      MaterialApp(
        home: BitcoinSendPage(
          from: BitcoinAddress(
            address: 'source',
            network: Network.mainnet,
            publicKey: Uint8List(33),
            type: BitcoinAddressType.p2pkh,
          ),
          wallet: wallet,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('send-address')),
      'destination',
    );
    await tester.enterText(find.byKey(const Key('send-amount')), '0.00009800');
    await tester.tap(find.text('送金内容を確認'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確認して送信'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同じ取引を再送信'));
    await tester.pumpAndSettle();
    expect(find.text('ブロック承認待ち'), findsOneWidget);
    final checking = Completer<bool?>();
    client.check = () => checking.future;
    await tester.tap(find.text('状態を更新'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('更新中…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '取引詳細へ戻る'))
          .onPressed,
      isNull,
    );
    checking.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('状態を更新できませんでした。通信状態を確認して再試行してください。'), findsOneWidget);
    client.check = () async => null;
    await tester.tap(find.text('状態を更新'));
    await tester.pumpAndSettle();
    expect(find.text('取引がネットワーク上で見つかりません。状態を更新してください。'), findsOneWidget);
    client.check = () async => true;
    await tester.tap(find.text('状態を更新'));
    await tester.pumpAndSettle();
    expect(find.text('ブロック承認済み'), findsOneWidget);
    expect(wallet.sent, hasLength(2));
  });

  testWidgets('完了から取引詳細を開き戻る操作と呼び出し元への復帰が整合する', (tester) async {
    final wallet = _Wallet();
    addTearDown(wallet.blockchainClient.close);
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => BitcoinSendPage(
                      from: BitcoinAddress(
                        address: 'source',
                        network: Network.mainnet,
                        publicKey: Uint8List(33),
                        type: BitcoinAddressType.p2pkh,
                      ),
                      wallet: wallet,
                    ),
                  ),
                );
              },
              child: const Text('開く'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('send-address')),
      'destination',
    );
    await tester.enterText(find.byKey(const Key('send-amount')), '0.00009800');
    await tester.tap(find.text('送金内容を確認'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確認して送信'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同じ取引を再送信'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取引詳細へ戻る'));
    await tester.pumpAndSettle();
    expect(find.text('取引詳細'), findsOneWidget);
    expect(result, isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('送信完了'), findsOneWidget);
    await tester.tap(find.text('取引詳細へ戻る'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -1000));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('アドレス詳細へ戻る'));
    await tester.tap(find.text('アドレス詳細へ戻る'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.text('開く'), findsOneWidget);
  });

  testWidgets('既存モデルから残高・UTXO・入出金履歴を表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddressQrDialog(
            name: '貯蓄用',
            address: 'address',
            loadUtxos: () async => [
              BitcoinUtxo(
                txid: 'confirmed-txid',
                vout: 0,
                value: 10000,
                confirmed: true,
                scriptPubkey: Uint8List(0),
              ),
              BitcoinUtxo(
                txid: 'unconfirmed-txid',
                vout: 1,
                value: 1,
                confirmed: false,
                scriptPubkey: Uint8List(0),
              ),
            ],
            loadHistory: () async => const [
              BitcoinHistoryEntry(
                txid: 'incoming',
                balanceChange: 100000001,
                confirmed: true,
              ),
              BitcoinHistoryEntry(
                txid: 'outgoing',
                balanceChange: -6000,
                confirmed: false,
                toAddress: 'destination',
                canReplace: true,
              ),
              BitcoinHistoryEntry(
                txid: 'zero',
                balanceChange: 0,
                confirmed: false,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('残高: 0.00010001 BTC'), findsOneWidget);
    expect(find.text('0.00010000 BTC'), findsOneWidget);
    expect(find.text('0.00000001 BTC'), findsOneWidget);
    expect(find.text('承認済み'), findsOneWidget);
    expect(find.text('未承認'), findsOneWidget);
    await tester.ensureVisible(find.text('取引履歴'));
    await tester.tap(find.text('取引履歴'));
    await tester.pumpAndSettle();
    expect(find.text('入金: +1.00000001 BTC'), findsOneWidget);
    expect(find.text('出金: -0.00006000 BTC'), findsOneWidget);
    expect(find.text('残高変化なし: 0.00000000 BTC'), findsOneWidget);
    expect(find.text('送金内容を変更'), findsNothing);
    expect(find.text('手数料を上書き'), findsNothing);
  });

  testWidgets('取得失敗後にUTXOを再取得し空なら残高ゼロを表示する', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddressQrDialog(
            name: '貯蓄用',
            address: 'address',
            loadUtxos: () async {
              calls++;
              if (calls == 1) throw StateError('connection lost');
              return [];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('残高を取得できませんでした。'), findsOneWidget);
    await tester.tap(find.text('残高を再取得'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('残高: 0.00000000 BTC'), findsOneWidget);
    expect(find.text('UTXOはありません'), findsOneWidget);
    expect(find.text('残高を取得できませんでした。'), findsNothing);
  });

  testWidgets('送金確認を整形し通信失敗後も同じ取引を再送する', (tester) async {
    final wallet = _Wallet();
    addTearDown(wallet.blockchainClient.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BitcoinSendPage(
          from: BitcoinAddress(
            address: 'source',
            network: Network.mainnet,
            publicKey: Uint8List(33),
            type: BitcoinAddressType.p2pkh,
          ),
          wallet: wallet,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('send-address')),
      ' destination ',
    );
    await tester.enterText(
      find.byKey(const Key('send-amount')),
      ' 0.00009800 ',
    );
    await tester.tap(find.text('送金内容を確認'));
    await tester.pumpAndSettle();
    expect(find.text('0.00009800 BTC'), findsOneWidget);
    expect(wallet.lastReplaceable, isFalse);
    expect(find.text('200 sat'), findsOneWidget);
    expect(find.text('0.00010000 BTC'), findsOneWidget);
    expect(find.text('destination'), findsOneWidget);
    expect(find.text('3.23 sat/vB'), findsOneWidget);
    await tester.tap(find.text('確認して送信'));
    await tester.pumpAndSettle();
    expect(
      find.text('https://blockstream.info/tx/${wallet.payment.txid}'),
      findsNothing,
    );
    await tester.ensureVisible(find.text('エクスプローラーで確認'));
    expect(find.text('エクスプローラーで確認'), findsOneWidget);
    await tester.ensureVisible(find.text('同じ取引を再送信'));
    await tester.tap(find.text('同じ取引を再送信'));
    await tester.pumpAndSettle();
    expect(find.text('送信完了'), findsOneWidget);
    expect(wallet.sent, [same(wallet.payment), same(wallet.payment)]);
    expect(find.text('手数料を上書き'), findsNothing);
  });
}
