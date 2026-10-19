import 'package:flutter/foundation.dart';
import 'package:bitcoin_wallet/src/ui/pages/bitcoin/bitcoin_qr_scan_page.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_transaction_serializer.dart';
import 'package:bitcoin_wallet/src/ui/formatters/bitcoin_amount.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_transaction.dart';

import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_wallet.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address.dart';

class BitcoinSendPage extends StatefulWidget {
  const BitcoinSendPage({super.key, required this.from, required this.wallet});

  final BitcoinAddress from;
  final BitcoinWallet wallet;

  @override
  State<BitcoinSendPage> createState() => _BitcoinSendPageState();
}

class _BitcoinSendPageState extends State<BitcoinSendPage> {
  final _to = TextEditingController();
  final _amount = TextEditingController();
  final _feeRate = TextEditingController(text: '2');
  BitcoinTransaction? _payment;
  int _amountSats = 0;
  bool _busy = false;
  bool _scanning = false;
  bool _attempted = false;
  String? _txid;
  String? _error;

  @override
  void dispose() {
    _to.dispose();
    _amount.dispose();
    _feeRate.dispose();
    super.dispose();
  }

  Future<void> _scanAddress() async {
    if (_busy || _scanning) return;
    FocusScope.of(context).unfocus();
    setState(() => _scanning = true);
    try {
      final address = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => BitcoinQrScanPage(network: widget.from.network),
        ),
      );
      if (!mounted || address == null) return;
      setState(() {
        _to.value = TextEditingValue(
          text: address,
          selection: TextSelection.collapsed(offset: address.length),
        );
        _error = null;
      });
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _prepare() async {
    if (_busy || _scanning) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.wallet.preparePayment(
        from: widget.from,
        toAddress: _to.text,
        amount: _amount.text,
        feeRate: _feeRate.text,
      );
      if (!mounted) return;
      // walletで検証済みの入力を、浮動小数点を使わず表示用に変換する。
      final parts = _amount.text.trim().split('.');
      final amountSats =
          int.parse(parts.first) * 100000000 +
          int.parse((parts.length == 2 ? parts.last : '').padRight(8, '0'));
      setState(() {
        _payment = result;
        _amountSats = amountSats;
      });
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on ArgumentError catch (error) {
      if (mounted) {
        setState(
          () => _error = error.message?.toString() ?? '送金額やアドレスを確認してください。',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = '送金を準備できませんでした。通信状態を確認して再試行してください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    if (_busy || _payment == null || _txid != null) return;
    setState(() {
      _busy = true;
      _attempted = true;
      _error = null;
    });
    try {
      final txid = await widget.wallet.sendPayment(_payment!);
      if (mounted) setState(() => _txid = txid);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = '送信結果を確認できませんでした。取引IDで状態を確認してください。再試行では同じ取引を送信します。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payment = _payment;
    final sent = _txid != null;
    final canScan =
        kIsWeb ||
        const [
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.macOS,
        ].contains(defaultTargetPlatform);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            sent
                ? '送信完了'
                : payment == null
                ? 'Bitcoinを送る'
                : '送金内容の確認',
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'Bitcoin · ${widget.from.network == Network.testnet ? 'Testnet' : 'Mainnet'}',
                  ),
                  const SizedBox(height: 16),
                  Text('送信元: ${widget.from.displayName}'),
                  SelectableText(widget.from.address),
                  const SizedBox(height: 24),
                  if (payment == null)
                    Form(
                      child: Column(
                        children: [
                          TextFormField(
                            key: const Key('send-address'),
                            controller: _to,
                            enabled: !_busy,
                            onTapOutside: (_) =>
                                FocusScope.of(context).unfocus(),
                            decoration: InputDecoration(
                              labelText: '宛先アドレス',
                              suffixIcon: canScan
                                  ? IconButton(
                                      key: const Key('scan-address'),
                                      tooltip: 'QRコードを読み取る',
                                      onPressed: _busy || _scanning
                                          ? null
                                          : _scanAddress,
                                      icon: const Icon(Icons.qr_code_scanner),
                                    )
                                  : null,
                            ),
                            onChanged: (_) => setState(() => _error = null),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const Key('send-amount'),
                            controller: _amount,
                            enabled: !_busy,
                            onTapOutside: (_) =>
                                FocusScope.of(context).unfocus(),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: '送金額 (BTC)',
                              helperText: '最小0.00000546 BTC・小数点以下8桁まで',
                            ),
                            onChanged: (_) => setState(() => _error = null),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const Key('send-fee-rate'),
                            controller: _feeRate,
                            enabled: !_busy,
                            onTapOutside: (_) =>
                                FocusScope.of(context).unfocus(),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: '手数料率 (sat/vB)',
                              helperText: '手数料が低いと承認まで時間がかかる場合があります',
                            ),
                            onChanged: (_) => setState(() => _error = null),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    const Text('宛先'),
                    SelectableText(_to.text.trim()),
                    const SizedBox(height: 16),
                    Text('送金額: ${formatBitcoinAmount(_amountSats)}'),
                    Text(
                      '手数料: ${formatBitcoinAmount(payment.fee)} (${payment.fee} sat)',
                    ),
                    Text(
                      '合計: ${formatBitcoinAmount(_amountSats + payment.fee)}',
                    ),
                    Text(
                      '実際の手数料率: ${(payment.fee / payment.virtualSize).toStringAsFixed(2)} sat/vB',
                    ),
                    const SizedBox(height: 16),
                    const Text('お釣りは送信元アドレスに戻ります。'),
                    if (_attempted) ...[
                      const SizedBox(height: 20),
                      Text(sent ? '取引を送信しました。承認をお待ちください。' : '取引ID'),
                      SelectableText(_txid ?? payment.txid),
                      SelectableText(
                        widget.wallet
                            .transactionExplorerUrl(payment.txid)
                            .toString(),
                      ),
                    ],
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
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
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : sent
                        ? () => Navigator.of(context).pop(true)
                        : payment == null
                        ? _prepare
                        : _send,
                    child: Text(
                      _busy
                          ? '処理中…'
                          : sent
                          ? 'アドレス詳細へ戻る'
                          : payment == null
                          ? '送金内容を確認'
                          : _attempted
                          ? '同じ取引を再送信'
                          : '確認して送信',
                    ),
                  ),
                  if (payment != null && !_attempted)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _payment = null;
                              _error = null;
                            }),
                      child: const Text('入力を修正'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
