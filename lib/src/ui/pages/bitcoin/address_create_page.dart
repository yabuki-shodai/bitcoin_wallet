import 'package:flutter/material.dart';

import '../../../core/wallet/network.dart';
import '../../../crypto/bitcoin/models/bitcoin_address.dart';
import '../../../crypto/bitcoin/models/bitcoin_address_type.dart';
import '../../widgets/address/address_type_card.dart';

class AddressCreatePage extends StatefulWidget {
  const AddressCreatePage({
    super.key,
    required this.network,
    required this.onGenerate,
    required this.onSave,
  });

  final Network network;
  final Future<BitcoinAddress> Function(String, BitcoinAddressType) onGenerate;
  final Future<void> Function(BitcoinAddress) onSave;

  @override
  State<AddressCreatePage> createState() => _AddressCreatePageState();
}

class _AddressCreatePageState extends State<AddressCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  BitcoinAddressType? _selectedType;
  BitcoinAddress? _pendingAddress;
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_creating ||
        _selectedType == null ||
        !_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _creating = true;
      _error = null;
    });

    try {
      _pendingAddress ??= await widget.onGenerate(
        _nameController.text.trim(),
        _selectedType!,
      );
      final address = _pendingAddress!.copyWith(
        displayName: _nameController.text.trim(),
      );
      await widget.onSave(address);
      if (!mounted) return;
      Navigator.of(context).pop(address);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = 'アドレスを作成できませんでした。もう一度お試しください。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final network = widget.network == Network.testnet ? 'Testnet' : 'Mainnet';

    return PopScope(
      canPop: !_creating,
      child: Scaffold(
        appBar: AppBar(title: const Text('新しいアドレス')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  children: [
                    Text('アドレス名', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameController,
                      enabled: !_creating,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        hintText: '名前を入力',
                        helperText: '1〜30文字',
                      ),
                      validator: (value) {
                        final name = value?.trim() ?? '';
                        if (name.isEmpty) return 'アドレス名を入力してください';
                        if (name.characters.length > 30) {
                          return 'アドレス名は30文字以内で入力してください';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 28),
                    Text('アドレスの種類', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Bitcoin · $network',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    AddressTypeCard(
                      title: 'P2WPKH',
                      description:
                          'Native SegWit · ${widget.network == Network.testnet ? 'tb1' : 'bc1'} から始まる',
                      selected: _selectedType == BitcoinAddressType.p2wpkh,
                      onTap: _creating || _pendingAddress != null
                          ? null
                          : () => setState(
                              () => _selectedType = BitcoinAddressType.p2wpkh,
                            ),
                    ),
                    const SizedBox(height: 12),
                    AddressTypeCard(
                      title: 'P2PKH',
                      description:
                          'Legacy · ${widget.network == Network.testnet ? 'm / n' : '1'} から始まる',
                      selected: _selectedType == BitcoinAddressType.p2pkh,
                      onTap: _creating || _pendingAddress != null
                          ? null
                          : () => setState(
                              () => _selectedType = BitcoinAddressType.p2pkh,
                            ),
                    ),
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
                  ],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _selectedType == null || _creating
                      ? null
                      : _create,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFDABC),
                    foregroundColor: const Color(0xFF221A15),
                    disabledBackgroundColor: const Color(0xFFD9E0E4),
                    disabledForegroundColor: const Color(0xFF69747A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: _creating
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Text('作成中…'),
                          ],
                        )
                      : const Text('作成する'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
