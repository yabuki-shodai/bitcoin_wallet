import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:bitcoin_wallet/src/core/secure/private_key_store.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_wallet.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address_type.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/repository/bitcoin_repository.dart';
import 'package:bitcoin_wallet/src/ui/pages/bitcoin/bitcoin_qr_scan_page.dart';
import 'package:bitcoin_wallet/src/ui/pages/bitcoin/bitcoin_send_page.dart';

class _Repository extends Fake implements BitcoinAddressRepository {}

class _KeyStore extends Fake implements PrivateKeyStore {}

class _Scanner extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast();
  MobileScannerErrorCode? failure;
  int starts = 0;
  int stops = 0;
  int disposals = 0;

  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    starts++;
    if (failure != null) throw MobileScannerException(errorCode: failure!);
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.unavailable,
      size: Size(640, 480),
    );
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }

  void read(String value) => captures.add(
    BarcodeCapture(
      barcodes: [Barcode(format: BarcodeFormat.qrCode, rawValue: value)],
    ),
  );
}

void main() {
  late MobileScannerPlatform previousPlatform;
  late _Scanner scanner;
  setUp(() {
    previousPlatform = MobileScannerPlatform.instance;
    scanner = _Scanner();
    MobileScannerPlatform.instance = scanner;
  });
  tearDown(() async {
    await scanner.captures.close();
    MobileScannerPlatform.instance = previousPlatform;
    MobileScannerController.resetPlatformSessionOwner();
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> showSend(
    WidgetTester tester, {
    Network network = Network.mainnet,
  }) async {
    final wallet = BitcoinWallet(
      network: network,
      repostory: _Repository(),
      store: _KeyStore(),
    );
    addTearDown(wallet.blockchainClient.close);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    });
    await tester.pumpWidget(
      MaterialApp(
        home: BitcoinSendPage(
          from: BitcoinAddress(
            address: 'source',
            network: network,
            publicKey: Uint8List(33),
            type: BitcoinAddressType.p2wpkh,
          ),
          wallet: wallet,
        ),
      ),
    );
  }

  Future<void> openScanner(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('scan-address')));
    await tester.pumpAndSettle();
    expect(find.byType(BitcoinQrScanPage), findsOneWidget);
  }

  String field(WidgetTester tester, String key) =>
      tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

  const mainnet = '1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH';
  const segwit = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
  const testnet = 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx';

  for (final address in [mainnet, segwit, testnet]) {
    testWidgets('アドレスの読み取りと重複検出: $address', (tester) async {
      await showSend(
        tester,
        network: address == testnet ? Network.testnet : Network.mainnet,
      );
      await openScanner(tester);
      scanner.read(' $address ');
      scanner.read(address);
      await tester.pumpAndSettle();
      expect(find.byType(BitcoinQrScanPage), findsNothing);
      expect(find.byType(BitcoinSendPage), findsOneWidget);
      expect(field(tester, 'send-address'), address);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(scanner.stops, 1);
      expect(scanner.disposals, 1);
    });
  }

  testWidgets('bitcoin URIから宛先を取得し入力済みの金額と手数料率を維持する', (tester) async {
    await showSend(tester);
    await tester.enterText(find.byKey(const Key('send-amount')), '0.25');
    await tester.enterText(find.byKey(const Key('send-fee-rate')), '5');
    await openScanner(tester);
    scanner.read('BITCOIN:$mainnet?amount=1&label=Donation');
    await tester.pumpAndSettle();
    expect(field(tester, 'send-address'), mainnet);
    expect(field(tester, 'send-amount'), '0.25');
    expect(field(tester, 'send-fee-rate'), '5');
  });

  testWidgets('不正な内容とネットワーク違いを拒否し続けて有効なQRを読める', (tester) async {
    await showSend(tester);
    await openScanner(tester);
    for (final value in [
      '',
      'hello',
      'https://example.com',
      '1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMJ',
      'bitcoin://$mainnet',
      'bitcoin:$mainnet#fragment',
    ]) {
      scanner.read(value);
      await tester.pumpAndSettle();
      expect(find.text('有効なBitcoinアドレスのQRコードを読み取ってください。'), findsOneWidget);
    }
    scanner.read(testnet);
    await tester.pumpAndSettle();
    expect(find.text('送信元と同じネットワークのアドレスを読み取ってください。'), findsOneWidget);
    scanner.read('bitcoin:$mainnet?req-extra=1');
    await tester.pumpAndSettle();
    expect(find.text('このQRコードのアドレス種別または支払い形式には対応していません。'), findsOneWidget);
    scanner.read(mainnet);
    await tester.pumpAndSettle();
    expect(field(tester, 'send-address'), mainnet);
  });

  testWidgets('QR以外は入力せずキャンセル時も既存の宛先を維持する', (tester) async {
    await showSend(tester);
    await tester.enterText(find.byKey(const Key('send-address')), 'original');
    await openScanner(tester);
    scanner.captures.add(
      const BarcodeCapture(
        barcodes: [
          Barcode(format: BarcodeFormat.code128, rawValue: mainnet),
          Barcode(format: BarcodeFormat.qrCode),
        ],
      ),
    );
    await tester.pump();
    expect(find.byType(BitcoinQrScanPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(field(tester, 'send-address'), 'original');
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(scanner.stops, 1);
    expect(scanner.disposals, 1);
  });

  for (final code in [
    MobileScannerErrorCode.permissionDenied,
    MobileScannerErrorCode.unsupported,
    MobileScannerErrorCode.genericError,
  ]) {
    testWidgets('カメラエラーを表示し送金画面へ戻れる: ${code.name}', (tester) async {
      scanner.failure = code;
      await showSend(tester);
      await openScanner(tester);
      final message = switch (code) {
        MobileScannerErrorCode.permissionDenied =>
          'カメラの使用が許可されていません。端末やブラウザの設定でカメラを許可してください。',
        MobileScannerErrorCode.unsupported => 'この端末ではカメラで読み取れません。',
        _ => 'カメラを起動できませんでした。読み取り画面を開き直してください。',
      };
      expect(find.text(message), findsOneWidget);
      await tester.tap(find.text('送金画面へ戻る'));
      await tester.pumpAndSettle();
      expect(find.byType(BitcoinSendPage), findsOneWidget);
      expect(field(tester, 'send-address'), isEmpty);
    });
  }

  testWidgets('バックグラウンドでカメラを停止し復帰時に再開する', (tester) async {
    await showSend(tester);
    await openScanner(tester);
    expect(scanner.starts, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(scanner.stops, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(scanner.starts, 2);
    scanner.read(mainnet);
    await tester.pumpAndSettle();
    expect(field(tester, 'send-address'), mainnet);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(scanner.stops, 2);
  });

  testWidgets('未対応プラットフォームでは手入力のみ表示する', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await showSend(tester);
    expect(find.byKey(const Key('scan-address')), findsNothing);
    expect(find.byKey(const Key('send-address')), findsOneWidget);
    expect(scanner.starts, 0);
    debugDefaultTargetPlatformOverride = null;
  });
}
