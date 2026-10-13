import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_wallet.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address_type.dart';
import 'package:bitcoin_wallet/src/ui/widgets/address/address_list.dart';
import 'package:bitcoin_wallet/src/ui/widgets/address/address_list_tile.dart';

class AddressDeletePage extends StatefulWidget {
  const AddressDeletePage({super.key, required this.wallet});

  final BitcoinWallet wallet;

  @override
  State<AddressDeletePage> createState() => _AddressDeletePageState();
}

class _AddressDeletePageState extends State<AddressDeletePage> {
  List<BitcoinAddress> _addresses = [];
  bool _loading = true;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final addresses = await widget.wallet.getAddresses();
      if (!mounted) return;
      setState(() {
        _addresses = addresses.reversed.toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'アドレスを読み込めませんでした。';
      });
    }
  }

  Future<void> _deleteAddress(BitcoinAddress address) async {
    if (_deleting) return;
    setState(() => _deleting = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('削除しますか？'),
          content: const Text('このアドレスと秘密鍵を削除します。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: const Text('削除'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      await widget.wallet.deleteAddress(address);
      if (!mounted) return;
      setState(() {
        _addresses.removeWhere((item) => item.address == address.address);
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('アドレスと秘密鍵を削除しました')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('削除できませんでした。もう一度お試しください。')),
        );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _copyAddress(String address) async {
    try {
      await Clipboard.setData(ClipboardData(text: address));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('コピーしました')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('コピーできませんでした。もう一度お試しください。')));
    }
  }

  String _formatLabel(BitcoinAddressType type) => switch (type) {
    BitcoinAddressType.p2pkh => 'P2PKH',
    BitcoinAddressType.p2shP2wpkh => 'P2SH-P2WPKH',
    BitcoinAddressType.p2wpkh => 'P2WPKH',
    BitcoinAddressType.p2tr => 'P2TR',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('アドレスの削除')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _buildAddresses(),
        ),
      ),
    ),
  );

  Widget _buildAddresses() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _loadAddresses,
              child: const Text('再読み込み'),
            ),
          ],
        ),
      );
    }
    return AddressList(
      itemCount: _addresses.length,
      itemBuilder: (_, index) {
        final address = _addresses[index];
        return AddressListTile(
          key: ValueKey(address.address),
          name: address.displayName,
          address: address.address,
          format: _formatLabel(address.type),
          onTap: () => _deleteAddress(address),
          onCopy: () => _copyAddress(address.address),
        );
      },
    );
  }
}
