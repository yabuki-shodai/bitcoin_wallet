import 'package:url_launcher/url_launcher.dart';
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
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_history_entry.dart';

class BitcoinSendPage extends StatefulWidget {
  const BitcoinSendPage({
    super.key,
    required this.from,
    required this.wallet,
    this.replaceable = false,
    this.original,
  });

  final BitcoinAddress from;
  final BitcoinWallet wallet;
  final bool replaceable;
  final BitcoinHistoryEntry? original;

  @override
  State<BitcoinSendPage> createState() => _BitcoinSendPageState();
}

class _BitcoinSendPageState extends State<BitcoinSendPage> {
  final _to = TextEditingController();
  final _paymentScroll = ScrollController();
  final _amount = TextEditingController();
  final _feeRate = TextEditingController(text: '2');
  BitcoinHistoryEntry? _originalEntry;
  BitcoinTransaction? _payment;
  BitcoinTransaction? _originalTransaction;
  int _amountSats = 0;
  bool _busy = false;
  bool _scanning = false;
  bool _attempted = false;
  String? _txid;
  String? _error;
  bool _refreshingStatus = false;
  bool _statusCheckFailed = false;
  BitcoinReplacementStatus? _replacementStatus;
  bool? _confirmed;

  @override
  void initState() {
    super.initState();
    _originalEntry = widget.original;
    if (_originalEntry != null) _loadOriginal();
  }

  Future<void> _loadOriginal() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final original = await widget.wallet.getReplaceableTransaction(
        from: widget.from,
        txid: _originalEntry!.txid,
      );
      if (!mounted) return;
      setState(() {
        _originalTransaction = original;
        _to.text = _originalEntry!.toAddress ?? '';
        final sats = original.outputs.first.value;
        _amount.text =
            '${sats ~/ 100000000}.${(sats % 100000000).toString().padLeft(8, '0')}';
        _feeRate.text = '${original.fee ~/ original.virtualSize + 1}';
      });
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '取引を取得できませんでした。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _paymentScroll.dispose();
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
      final original = _originalEntry;
      final result = original != null
          ? await widget.wallet.prepareReplacement(
              from: widget.from,
              txid: original.txid,
              toAddress: _to.text,
              feeRate: _feeRate.text,
            )
          : await widget.wallet.preparePayment(
              from: widget.from,
              toAddress: _to.text,
              amount: _amount.text,
              feeRate: _feeRate.text,
              replaceable: widget.replaceable,
            );
      if (!mounted) return;
      setState(() {
        _payment = result;
        _amountSats = result.outputs.first.value;
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
      final original = _originalEntry;
      final txid = original == null
          ? await widget.wallet.sendPayment(_payment!)
          : await widget.wallet.sendReplacement(
              from: widget.from,
              originalTxid: original.txid,
              payment: _payment!,
            );
      if (!mounted) return;
      setState(() => _txid = txid);
      await _refreshStatus();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = _originalEntry != null && error is StateError
              ? error.message
              : '送信結果を確認できませんでした。取引IDで状態を確認してください。再試行では同じ取引を送信します。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshStatus() async {
    final original = _originalTransaction;
    final payment = _payment;
    if (_refreshingStatus || payment == null || _txid == null) {
      return;
    }
    setState(() {
      _refreshingStatus = true;
      _replacementStatus = null;
      _statusCheckFailed = false;
    });
    if (_paymentScroll.hasClients) _paymentScroll.jumpTo(0);
    try {
      if (original != null) {
        final status = await widget.wallet.getReplacementStatus(
          original: original,
          payment: payment,
        );
        if (mounted) setState(() => _replacementStatus = status);
      } else {
        final confirmed = await widget.wallet.blockchainClient
            .getTransactionConfirmation(_txid!);
        if (mounted) setState(() => _confirmed = confirmed);
      }
    } catch (_) {
      // 送信は完了しているため、確認失敗によって再送信は行わない。
      if (mounted) {
        setState(() => _statusCheckFailed = true);
      }
    } finally {
      if (mounted) setState(() => _refreshingStatus = false);
    }
  }

  Future<void> _replaceFee() async {
    final payment = _payment;
    final txid = _txid;
    if (_busy || _refreshingStatus || payment == null || txid == null) {
      return;
    }
    // 同じルートを使い、呼び出し元が送金画面の終了と誤認しないようにする。
    setState(() {
      _originalEntry = BitcoinHistoryEntry(
        txid: txid,
        balanceChange: -(_amountSats + payment.fee),
        confirmed: false,
        toAddress: _to.text.trim(),
        canReplace: true,
      );
      _originalTransaction = null;
      _payment = null;
      _txid = null;
      _amountSats = 0;
      _attempted = false;
      _error = null;
      _replacementStatus = null;
      _statusCheckFailed = false;
      _confirmed = null;
    });
    await _loadOriginal();
  }

  String _sats(int value) =>
      '${value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',')} sat';

  String get _statusText {
    if (_refreshingStatus) return '状態を確認中…';
    if (_statusCheckFailed) return '状態を更新できませんでした。通信状態を確認して再試行してください。';
    if (_originalTransaction == null) {
      return switch (_confirmed) {
        true => 'ブロック承認済み',
        false => 'ブロック承認待ち',
        null => '取引がネットワーク上で見つかりません。状態を更新してください。',
      };
    }
    return switch (_replacementStatus) {
      BitcoinReplacementStatus.accepted => 'ブロック承認待ち',
      BitcoinReplacementStatus.confirmed => 'ブロック承認済み',
      BitcoinReplacementStatus.notFound => '変更取引がネットワーク上で見つかりません。状態を更新してください。',
      BitcoinReplacementStatus.originalActive => '変更前の取引が有効です。変更の成立をまだ確認できません。',
      BitcoinReplacementStatus.conflicted =>
        '変更前の取引が承認済み、または別の取引と競合しています。変更は成立していません。',
      _ => '取引情報への反映を待っています。状態を更新してください。',
    };
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  Future<void> _copy(String label, String value) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      _notify('$labelをコピーしました');
    } catch (_) {
      _notify('コピーできませんでした。もう一度お試しください。');
    }
  }

  Future<void> _openExplorer() async {
    try {
      if (await launchUrl(
        widget.wallet.transactionExplorerUrl(_txid ?? _payment!.txid),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // 起動失敗は画面上で通知する。
    }
    _notify('エクスプローラーを開けませんでした。');
  }

  Widget _valueRow(String label, String value, {bool emphasis = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelWidget = Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
          final valueWidget = Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: emphasis ? FontWeight.w600 : FontWeight.w400,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          );
          if (constraints.maxWidth < 340 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [labelWidget, const SizedBox(height: 4), valueWidget],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: labelWidget),
              const SizedBox(width: 16),
              Flexible(flex: 2, child: valueWidget),
            ],
          );
        },
      ),
    );
  }

  Widget _copyRow(String label, String? value) {
    final available = value != null && value.isNotEmpty;
    final display = !available
        ? '取得できませんでした'
        : value.length > 24
        ? '${value.substring(0, 12)}…${value.substring(value.length - 10)}'
        : value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (available)
            Semantics(
              label: '$label: $value。タップして全文をコピー',
              button: true,
              excludeSemantics: true,
              child: InkWell(
                onTap: () => _copy(label, value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          display,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.copy_outlined, size: 18),
                    ],
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(display),
            ),
        ],
      ),
    );
  }

  Widget _divider() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 18),
    child: Divider(),
  );

  List<Widget> _paymentContent(
    BitcoinTransaction payment,
    BitcoinTransaction? original, {
    required bool sent,
    bool details = false,
  }) {
    final theme = Theme.of(context);
    final addressChanged =
        original != null &&
        _originalEntry?.toAddress != null &&
        _originalEntry!.toAddress != _to.text.trim();
    return [
      if (sent && !details) ...[
        const Align(
          alignment: Alignment.centerLeft,
          child: Icon(Icons.check_circle_outline, size: 32),
        ),
        const SizedBox(height: 12),
        Text(
          original != null ? '変更取引を送信しました' : '取引を送信しました',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text(
            _statusText,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _statusCheckFailed
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (_refreshingStatus) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        _divider(),
      ] else ...[
        Text(
          'Bitcoin · ${widget.from.network == Network.testnet ? 'Testnet' : 'Mainnet'}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        if (details) ...[Text(_statusText), const SizedBox(height: 16)],
      ],
      Text(
        original != null ? '変更後の手数料' : '送金額',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 6),
      Text(
        original != null
            ? _sats(payment.fee)
            : formatBitcoinAmount(_amountSats),
        style: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      const SizedBox(height: 14),
      if (original != null) ...[
        _valueRow('変更前の手数料', _sats(original.fee)),
        _valueRow(
          '追加手数料',
          '${payment.fee - original.fee >= 0 ? '+' : ''}${_sats(payment.fee - original.fee)}',
          emphasis: true,
        ),
        _valueRow(
          '変更後の手数料率',
          '${(payment.fee / payment.virtualSize).toStringAsFixed(2)} sat/vB',
        ),
      ] else ...[
        _valueRow('手数料', _sats(payment.fee)),
        _valueRow(
          '手数料率',
          '${(payment.fee / payment.virtualSize).toStringAsFixed(2)} sat/vB',
        ),
        _valueRow(
          '合計',
          formatBitcoinAmount(_amountSats + payment.fee),
          emphasis: true,
        ),
      ],
      _divider(),
      if (original != null) _valueRow('送金額', formatBitcoinAmount(_amountSats)),
      if (addressChanged) ...[
        Text(
          '送金先アドレスが変更されています',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        _copyRow('変更前の送金先アドレス', _originalEntry!.toAddress),
      ],
      _copyRow(addressChanged ? '変更後の送金先アドレス' : '送金先アドレス', _to.text.trim()),
      if (sent || _attempted) ...[
        _copyRow(original != null ? '変更後のTXID' : 'TXID', _txid ?? payment.txid),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _openExplorer,
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('エクスプローラーで確認'),
          ),
        ),
      ],
      _divider(),
      ExpansionTile(
        key: ValueKey(
          'transaction-details-${sent ? 'sent' : 'review'}-$details',
        ),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        initiallyExpanded: details,
        title: Text(
          original != null ? '変更前の取引情報' : '詳細情報',
          style: theme.textTheme.bodyMedium,
        ),
        children: [
          if (original != null) ...[
            _copyRow('変更前のTXID', _originalEntry!.txid),
            _valueRow(
              '変更前の手数料率',
              '${(original.fee / original.virtualSize).toStringAsFixed(2)} sat/vB',
            ),
            _valueRow('変更前の手数料', _sats(original.fee)),
            if (addressChanged) ...[
              _copyRow('変更前の送金先アドレス', _originalEntry!.toAddress),
              _copyRow('変更後の送金先アドレス', _to.text.trim()),
            ],
          ],
          _copyRow('送信元アドレス', widget.from.address),
          _valueRow(
            'ネットワーク',
            widget.from.network == Network.testnet ? 'Testnet' : 'Mainnet',
          ),
          _valueRow(
            '合計（送金額＋手数料）',
            formatBitcoinAmount(_amountSats + payment.fee),
          ),
          if (payment.outputs.length > 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('お釣りは送信元アドレスに戻ります。'),
            ),
        ],
      ),
      if (!sent && !_attempted) ...[
        const SizedBox(height: 16),
        Text(
          '送金先と${original != null ? '追加手数料' : '送金額・手数料'}を確認して送信してください。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(
            _error!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      ],
    ];
  }

  Future<void> _showTransactionDetails() async {
    final payment = _payment!;
    final original = _originalTransaction;
    final canReplace =
        payment.inputs.isNotEmpty &&
        payment.inputs.every((input) => input.sequence == 0xfffffffd) &&
        payment.outputs.length == 2 &&
        !_statusCheckFailed &&
        (original == null
            ? _confirmed == false
            : _replacementStatus == BitcoinReplacementStatus.accepted);
    final action = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (detailContext) => Scaffold(
          appBar: AppBar(title: const Text('取引詳細')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    ..._paymentContent(
                      payment,
                      original,
                      sent: true,
                      details: true,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => Navigator.of(detailContext).pop(false),
                      child: const Text('アドレス詳細へ戻る'),
                    ),
                    if (canReplace)
                      TextButton(
                        onPressed: () => Navigator.of(detailContext).pop(true),
                        child: const Text('手数料を上書き'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (action == true) {
      await _replaceFee();
    } else if (action == false) {
      Navigator.of(context).pop(true);
    }
  }

  Widget _buildPaymentPage(
    BitcoinTransaction payment,
    BitcoinTransaction? original,
    bool sent,
  ) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            sent
                ? '送信完了'
                : original != null
                ? '変更内容の確認'
                : '送金内容の確認',
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                key: ValueKey(sent ? 'payment-sent' : 'payment-review'),
                controller: _paymentScroll,
                padding: const EdgeInsets.all(20),
                children: _paymentContent(payment, original, sent: sent),
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Align(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton(
                      onPressed: _busy || (sent && _refreshingStatus)
                          ? null
                          : sent
                          ? _showTransactionDetails
                          : _send,
                      child: Text(
                        _busy
                            ? '処理中…'
                            : sent
                            ? '取引詳細へ戻る'
                            : _attempted
                            ? '同じ取引を再送信'
                            : '確認して送信',
                      ),
                    ),
                    if (sent)
                      TextButton(
                        onPressed: _refreshingStatus || _busy
                            ? null
                            : _refreshStatus,
                        child: Text(_refreshingStatus ? '更新中…' : '状態を更新'),
                      )
                    else if (!_attempted)
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final payment = _payment;
    final original = _originalTransaction;
    final sent = _txid != null;
    if (payment != null) return _buildPaymentPage(payment, original, sent);
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
            _originalEntry != null
                ? '送金内容を変更'
                : widget.replaceable
                ? '変更可能な送金'
                : 'Bitcoinを送る',
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
                  if (original != null) ...[
                    const Text('変更前の宛先'),
                    SelectableText(_originalEntry!.toAddress ?? ''),
                    const SizedBox(height: 16),
                    Text(
                      '変更前の手数料: ${formatBitcoinAmount(original.fee)} (${original.fee} sat)',
                    ),
                    Text(
                      '変更前の手数料率: ${(original.fee / original.virtualSize).toStringAsFixed(2)} sat/vB',
                    ),
                    const SizedBox(height: 24),
                  ],
                  Form(
                    child: Column(
                      children: [
                        TextFormField(
                          key: const Key('send-address'),
                          controller: _to,
                          enabled: !_busy,
                          onTapOutside: (_) => FocusScope.of(context).unfocus(),
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
                          readOnly: _originalEntry != null,
                          onTapOutside: (_) => FocusScope.of(context).unfocus(),
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
                          onTapOutside: (_) => FocusScope.of(context).unfocus(),
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
                  ),
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
                  if (_originalEntry != null && original == null && !_busy)
                    TextButton(
                      onPressed: _loadOriginal,
                      child: const Text('取引を再取得'),
                    ),
                  FilledButton(
                    onPressed:
                        _busy || (_originalEntry != null && original == null)
                        ? null
                        : _prepare,
                    child: Text(
                      _busy
                          ? '処理中…'
                          : _originalEntry != null
                          ? '変更内容を確認'
                          : '送金内容を確認',
                    ),
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
