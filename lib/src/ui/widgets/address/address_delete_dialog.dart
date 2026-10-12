import 'package:flutter/material.dart';

import '../../../crypto/bitcoin/models/bitcoin_address.dart';

class AddressDeleteDialog extends StatefulWidget {
  const AddressDeleteDialog({
    super.key,
    required this.address,
    required this.onDelete,
  });

  final BitcoinAddress address;
  final Future<void> Function() onDelete;

  @override
  State<AddressDeleteDialog> createState() => _AddressDeleteDialogState();
}

class _AddressDeleteDialogState extends State<AddressDeleteDialog> {
  bool _deleting = false;
  String? _error;

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await widget.onDelete();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = 'アドレスを削除できませんでした。もう一度お試しください。';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_deleting,
    child: AlertDialog(
      title: const Text('アドレスを削除しますか？'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.address.displayName.trim().isEmpty
                ? '名前なし'
                : widget.address.displayName,
          ),
          const SizedBox(height: 8),
          SelectableText(widget.address.address),
          const SizedBox(height: 16),
          const Text('このアドレスを一覧から削除します。秘密鍵は保持されます。'),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.of(context).pop(false),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: _deleting ? null : _delete,
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          child: Text(_deleting ? '削除中…' : '削除'),
        ),
      ],
    ),
  );
}
