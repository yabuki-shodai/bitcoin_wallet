import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_address_decoder.dart';

class BitcoinQrScanPage extends StatefulWidget {
  const BitcoinQrScanPage({super.key, required this.network});

  final Network network;

  @override
  State<BitcoinQrScanPage> createState() => _BitcoinQrScanPageState();
}

class _BitcoinQrScanPageState extends State<BitcoinQrScanPage> {
  bool _completed = false;
  String? _error;

  String _readAddress(String rawValue) {
    final text = rawValue.trim();
    final uri = Uri.tryParse(text);
    if (uri == null) throw const FormatException();

    var address = text;
    if (uri.hasScheme) {
      if (uri.scheme != 'bitcoin' || uri.hasAuthority || uri.hasFragment) {
        throw const FormatException();
      }
      if (uri.queryParameters.keys.any((key) => key.startsWith('req-'))) {
        throw UnsupportedError('未対応の必須パラメータです');
      }
      address = uri.path;
    }
    BitcoinAddressDecoder().toScriptPubKey(address, network: widget.network);
    final lowerAddress = address.toLowerCase();
    if (lowerAddress.startsWith('bc1') || lowerAddress.startsWith('tb1')) {
      return lowerAddress;
    }
    return address;
  }

  void _onDetect(BarcodeCapture capture) {
    if (!mounted || _completed || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    String? message;
    for (final barcode in capture.barcodes) {
      if (barcode.format != BarcodeFormat.qrCode || barcode.rawValue == null) {
        continue;
      }
      try {
        final address = _readAddress(barcode.rawValue!);
        _completed = true;
        Navigator.of(context).pop(address);
        return;
      } on ArgumentError {
        message = '送信元と同じネットワークのアドレスを読み取ってください。';
      } on UnsupportedError {
        message = 'このQRコードのアドレス種別または支払い形式には対応していません。';
      } on FormatException {
        message = '有効なBitcoinアドレスのQRコードを読み取ってください。';
      }
    }
    if (message != null && message != _error) {
      setState(() => _error = message);
    }
  }

  Widget _cameraError(BuildContext context, MobileScannerException error) {
    final message = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'カメラの使用が許可されていません。端末やブラウザの設定でカメラを許可してください。',
      MobileScannerErrorCode.unsupported => 'この端末ではカメラで読み取れません。',
      _ => 'カメラを起動できませんでした。読み取り画面を開き直してください。',
    };
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 40),
              const SizedBox(height: 16),
              Semantics(liveRegion: true, child: Text(message)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('送金画面へ戻る'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('QRコードを読み取る')),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: _onDetect,
              errorBuilder: _cameraError,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
