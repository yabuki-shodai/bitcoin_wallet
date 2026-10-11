import 'package:flutter/material.dart';

class AddressRenameDialog extends StatefulWidget {
  const AddressRenameDialog({
    super.key,
    required this.name,
    required this.onSave,
  });

  final String name;
  final Future<void> Function(String) onSave;

  @override
  State<AddressRenameDialog> createState() => _AddressRenameDialogState();
}

class _AddressRenameDialogState extends State<AddressRenameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final name = _controller.text.trim();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(name);
      if (mounted) Navigator.of(context).pop(name);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '名前を変更できませんでした。もう一度お試しください。';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('アドレス名の変更'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _controller,
              autofocus: true,
              enabled: !_saving,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                labelText: 'アドレス名',
                helperText: '1〜30文字',
              ),
              validator: (value) {
                final name = value?.trim() ?? '';
                if (name.isEmpty) return 'アドレス名を入力してください';
                if (name.characters.length > 30) return 'アドレス名は30文字以内で入力してください';
                return null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    ),
  );
}
