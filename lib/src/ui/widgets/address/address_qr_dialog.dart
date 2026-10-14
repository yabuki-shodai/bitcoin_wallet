import 'package:flutter/material.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_history_entry.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_balance_summary.dart';
import 'package:bitcoin_wallet/src/ui/widgets/address/address_rename_dialog.dart';

class AddressQrDialog extends StatefulWidget {
  const AddressQrDialog({
    super.key,
    required this.name,
    required this.address,
    this.onSend,
    this.onRename,
    this.onCopy,
    this.onOpenExplorer,
    this.loadBalance,
    this.loadHistory,
  });

  final String name;
  final String address;
  final VoidCallback? onSend;
  final Future<void> Function(String)? onRename;
  final VoidCallback? onCopy;
  final VoidCallback? onOpenExplorer;
  final Future<BitcoinBalanceSummary> Function()? loadBalance;
  final Future<List<BitcoinHistoryEntry>> Function()? loadHistory;

  @override
  State<AddressQrDialog> createState() => _AddressQrDialogState();
}

class _AddressQrDialogState extends State<AddressQrDialog> {
  Future<BitcoinBalanceSummary>? _balance;
  late String _name;
  List<BitcoinHistoryEntry>? _history;
  bool _historyLoading = false;
  bool _historyError = false;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _name = widget.name;
    _balance = widget.loadBalance?.call();
  }

  Future<void> _rename() async {
    if (widget.onRename == null) return;
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          AddressRenameDialog(name: _name, onSave: widget.onRename!),
    );
    if (mounted && name != null) setState(() => _name = name);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<BitcoinBalanceSummary>(
    future: _balance,
    builder: _buildDialog,
  );

  Widget _buildDialog(
    BuildContext context,
    AsyncSnapshot<BitcoinBalanceSummary> snapshot,
  ) {
    final theme = Theme.of(context);
    final displayName = _name.trim().isEmpty ? '名前なし' : _name;
    final balance = snapshot.data;

    return Dialog(
      backgroundColor: theme.scaffoldBackgroundColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'アドレスをコピー',
                      onPressed: widget.onCopy,
                      icon: const Icon(Icons.copy_outlined),
                      color: const Color(0xFF36A8F5),
                    ),
                    Expanded(
                      child: Text(
                        displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'アドレス名の変更',
                      onPressed: widget.onRename == null ? null : _rename,
                      icon: const Icon(Icons.edit_outlined),
                      color: const Color(0xFF36A8F5),
                    ),
                  ],
                ),
                if (widget.loadBalance != null) ...[
                  const SizedBox(height: 12),
                  if (snapshot.connectionState != ConnectionState.done)
                    const Text('残高を取得中…')
                  else if (snapshot.hasError) ...[
                    const Text('残高を取得できませんでした。'),
                    TextButton(
                      onPressed: () =>
                          setState(() => _balance = widget.loadBalance!()),
                      child: const Text('残高を再取得'),
                    ),
                  ] else if (balance != null)
                    Text('残高: ${balance.totalText}'),
                ],
                const SizedBox(height: 20),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: ColoredBox(
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: QrImageView(
                              data: widget.address,
                              version: QrVersions.auto,
                              backgroundColor: Colors.white,
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: Colors.black,
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: widget.onSend,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  icon: const Icon(Icons.send),
                  label: const Text('送金'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: widget.onOpenExplorer,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFDABC),
                    foregroundColor: const Color(0xFF221A15),
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Explorerを開く'),
                ),
                if (widget.loadBalance != null ||
                    widget.loadHistory != null) ...[
                  const SizedBox(height: 24),
                  if (widget.loadHistory != null)
                    DefaultTabController(
                      length: 2,
                      child: TabBar(
                        tabs: const [
                          Tab(text: 'UTXO'),
                          Tab(text: '取引履歴'),
                        ],
                        onTap: (index) {
                          setState(() => _selectedTab = index);
                          if (index == 1 &&
                              _history == null &&
                              !_historyLoading &&
                              !_historyError) {
                            _loadHistory();
                          }
                        },
                      ),
                    )
                  else
                    Text('UTXO', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  if (_selectedTab == 0)
                    ..._buildUtxos(snapshot, theme)
                  else
                    _buildHistory(theme),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildUtxos(
    AsyncSnapshot<BitcoinBalanceSummary> snapshot,
    ThemeData theme,
  ) {
    final balance = snapshot.data;
    if (snapshot.connectionState != ConnectionState.done) {
      return [const Text('UTXOを取得中…')];
    }
    if (snapshot.hasError) return [const Text('UTXOを取得できませんでした。残高を再取得してください。')];
    if (balance == null) return [const Text('UTXOはありません')];
    return [
      if (balance.utxos.isEmpty) const Text('UTXOはありません'),
      for (final utxo in balance.utxos)
        Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          color: theme.colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        utxo.valueText,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: utxo.confirmed
                            ? const Color(0xFFE4F3E7)
                            : const Color(0xFFFFF1D6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        utxo.confirmed ? '承認済み' : '未承認',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: utxo.confirmed
                              ? const Color(0xFF23643A)
                              : const Color(0xFF845300),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  'txid: ${utxo.txid}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text('vout: ${utxo.vout}', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
    ];
  }

  String _confirmedTime(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}/${two(local.month)}/${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _loadHistory() async {
    setState(() {
      _historyLoading = true;
      _historyError = false;
    });
    try {
      final entries = await widget.loadHistory!();
      if (mounted) setState(() => _history = entries);
    } catch (_) {
      if (mounted) setState(() => _historyError = true);
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  Widget _buildHistory(ThemeData theme) {
    if (_historyLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            LinearProgressIndicator(),
            SizedBox(height: 12),
            Text('取引履歴を取得中…'),
          ],
        ),
      );
    }
    if (_historyError) {
      return Column(
        children: [
          const Text('取引履歴を取得できませんでした。'),
          TextButton(onPressed: _loadHistory, child: const Text('取引履歴を再取得')),
        ],
      );
    }
    if (_history == null || _history!.isEmpty) return const Text('取引履歴はありません');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        for (final entry in _history!)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.direction}: ${entry.amountText}',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(entry.confirmed ? '承認済み' : '未承認'),
                  if (entry.confirmedAt != null)
                    Text('承認日時: ${_confirmedTime(entry.confirmedAt!)}'),
                  const SizedBox(height: 8),
                  SelectableText(
                    'txid: ${entry.txid}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
