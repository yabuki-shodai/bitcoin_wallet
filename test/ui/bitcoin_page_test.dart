import 'dart:async';

import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/core/wallet/wallet.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address_type.dart';
import 'package:bitcoin_wallet/src/ui/pages/bitcoin/address_create_page.dart';
import 'package:bitcoin_wallet/src/ui/pages/bitcoin/bitcoin_page.dart';
import 'package:bitcoin_wallet/src/ui/router/app_router.dart';
import 'package:bitcoin_wallet/src/ui/theme/app_theme.dart';
import 'package:bitcoin_wallet/src/ui/widgets/address/address_qr_dialog.dart';
import 'package:bitcoin_wallet/src/ui/widgets/address/address_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

class TestWallet implements Wallet<BitcoinAddress> {
  final addresses = <BitcoinAddress>[];
  int generationCount = 0;
  bool failLoad = false;
  bool failSave = false;
  Completer<void>? saveGate;

  @override
  Future<List<BitcoinAddress>> getAddresses() async {
    if (failLoad) throw StateError('load failed');
    return List.of(addresses);
  }

  @override
  Future<BitcoinAddress> generateAddress(String name) =>
      generateAddressOfType(name, BitcoinAddressType.p2wpkh);

  Future<BitcoinAddress> generateAddressOfType(
    String name,
    BitcoinAddressType type,
  ) async {
    generationCount++;
    return BitcoinAddress(
      displayName: name,
      address: type == BitcoinAddressType.p2pkh
          ? 'mexample000000000000000000000000000$generationCount'
          : 'tb1qexample000000000000000000000000000$generationCount',
      network: Network.testnet,
      publicKey: Uint8List.fromList([2, 3]),
      type: type,
    );
  }

  @override
  Future<void> saveAddress(BitcoinAddress address) async {
    if (saveGate != null) await saveGate!.future;
    if (failSave) throw StateError('save failed');
    addresses.add(address);
  }
}

Future<void> openPage(WidgetTester tester, TestWallet wallet) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      routes: {'/': (_) => BitcoinPage(wallet: wallet)},
      onGenerateRoute: (settings) => settings.name == AppRouter.bitcoinCreate
          ? MaterialPageRoute<BitcoinAddress>(
              settings: settings,
              builder: (_) => AddressCreatePage(
                network: Network.testnet,
                onGenerate: wallet.generateAddressOfType,
                onSave: wallet.saveAddress,
              ),
            )
          : null,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openCreate(WidgetTester tester) async {
  await tester.tap(find.text('新しいアドレス'));
  await tester.pumpAndSettle();
  expect(find.byType(AddressCreatePage), findsOneWidget);
}

void main() {
  testWidgets('形式と名前を選んで作成し、一覧へ戻る', (tester) async {
    final wallet = TestWallet()..saveGate = Completer<void>();
    await openPage(tester, wallet);
    expect(find.text('アドレスがありません'), findsOneWidget);
    await openCreate(tester);

    final createButton = find.widgetWithText(FilledButton, '作成する');
    expect(tester.widget<FilledButton>(createButton).onPressed, isNull);
    await tester.tap(find.text('P2PKH'));

    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.tap(createButton);
    await tester.pumpAndSettle();
    expect(find.text('アドレス名を入力してください'), findsOneWidget);
    expect(wallet.generationCount, 0);

    await tester.enterText(find.byType(TextFormField), 'あ' * 31);
    await tester.tap(createButton);
    await tester.pumpAndSettle();
    expect(find.text('アドレス名は30文字以内で入力してください'), findsOneWidget);
    expect(wallet.generationCount, 0);

    await tester.enterText(find.byType(TextFormField), '  貯蓄用  ');
    await tester.tap(createButton);
    await tester.pump();
    expect(find.text('作成中…'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(AddressCreatePage), findsOneWidget);
    expect(wallet.generationCount, 1);

    wallet.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AddressCreatePage), findsNothing);
    expect(wallet.addresses.single.displayName, '貯蓄用');
    expect(wallet.addresses.single.type, BitcoinAddressType.p2pkh);
    expect(find.text(wallet.addresses.single.address), findsOneWidget);
    expect(find.text('貯蓄用'), findsOneWidget);
    expect(find.text('P2PKH'), findsOneWidget);
  });

  testWidgets('キャンセルすると作成しない', (tester) async {
    final wallet = TestWallet();
    await openPage(tester, wallet);
    await openCreate(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(AddressCreatePage), findsNothing);
    expect(wallet.generationCount, 0);
  });

  testWidgets('保存失敗時は同じアドレスで再試行できる', (tester) async {
    final wallet = TestWallet()..failSave = true;
    await openPage(tester, wallet);
    await openCreate(tester);
    await tester.tap(find.text('P2WPKH'));
    await tester.enterText(find.byType(TextFormField), '普段使い');
    await tester.tap(find.text('作成する'));
    await tester.pumpAndSettle();
    expect(find.textContaining('作成できませんでした'), findsOneWidget);
    expect(wallet.addresses, isEmpty);

    wallet.failSave = false;
    await tester.enterText(find.byType(TextFormField), '貯蓄用');
    await tester.tap(find.text('作成する'));
    await tester.pumpAndSettle();
    expect(wallet.generationCount, 1);
    expect(wallet.addresses.single.displayName, '貯蓄用');
    expect(wallet.addresses.single.type, BitcoinAddressType.p2wpkh);
    expect(find.byType(AddressCreatePage), findsNothing);
  });

  testWidgets('読み込み失敗後に再読み込みできる', (tester) async {
    final wallet = TestWallet()..failLoad = true;
    await openPage(tester, wallet);
    expect(find.text('アドレスを読み込めませんでした。'), findsOneWidget);
    wallet.failLoad = false;
    await tester.tap(find.text('再読み込み'));
    await tester.pumpAndSettle();
    expect(find.text('アドレスがありません'), findsOneWidget);
  });

  testWidgets('長押しでコピーでき、タップで名前とアドレスのQRを表示する', (tester) async {
    final wallet = TestWallet();
    wallet.addresses.add(await wallet.generateAddress(''));
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
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    await openPage(tester, wallet);
    await tester.longPress(find.byType(AddressListTile));
    await tester.pumpAndSettle();
    expect(copied, wallet.addresses.single.address);

    await tester.tap(find.byType(AddressListTile));
    await tester.pumpAndSettle();
    expect(find.byType(AddressQrDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AddressQrDialog),
        matching: find.text('名前なし'),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<AddressQrDialog>(find.byType(AddressQrDialog)).address,
      wallet.addresses.single.address,
    );
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    copied = null;
    await tester.tap(find.byTooltip('アドレスをコピー'));
    await tester.pumpAndSettle();
    expect(copied, wallet.addresses.single.address);
    expect(find.byType(AddressQrDialog), findsOneWidget);
  });

  testWidgets('詳細のExplorerボタンからTestnet4のアドレスをブラウザで開く', (tester) async {
    final wallet = TestWallet();
    wallet.addresses.add(await wallet.generateAddress('普段使い'));
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await openPage(tester, wallet);
    await tester.tap(find.byType(AddressListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Explorerを開く'));
    await tester.tap(find.text('Explorerを開く'));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect(calls.single.method, 'launch');
    final arguments = calls.single.arguments as Map;
    expect(
      arguments['url'],
      'https://mempool.space/testnet4/address/${wallet.addresses.single.address}',
    );
    expect(arguments['useWebView'], isFalse);
    expect(arguments['useSafariVC'], isFalse);
    expect(find.byType(AddressQrDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Explorerを開けない場合にエラーを表示する', (tester) async {
    final wallet = TestWallet();
    wallet.addresses.add(await wallet.generateAddress('普段使い'));
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => false,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await openPage(tester, wallet);
    await tester.tap(find.byType(AddressListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Explorerを開く'));
    await tester.tap(find.text('Explorerを開く'));
    await tester.pumpAndSettle();
    expect(find.text('Explorerを開けませんでした。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('小さい画面とキーボード表示中も作成できる', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final wallet = TestWallet();
    await openPage(tester, wallet);
    await openCreate(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.enterText(find.byType(TextFormField), '普段使い');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('P2WPKH'));
    await tester.tap(find.text('P2WPKH'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '作成する'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('作成する'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AddressCreatePage), findsNothing);
    expect(wallet.addresses.single.displayName, '普段使い');
  });
}
