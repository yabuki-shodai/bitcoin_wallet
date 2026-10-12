import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../crypto/bitcoin/bitcoin_wallet.dart';
import '../../../crypto/bitcoin/models/bitcoin_address.dart';
import '../../../crypto/bitcoin/models/bitcoin_address_type.dart';
import '../../widgets/address/address_delete_dialog.dart';
import '../../widgets/address/address_list.dart';
import '../../widgets/address/address_list_tile.dart';

class AddressDeletePage extends StatefulWidget {
  const AddressDeletePage({super.key, required this.wallet});

  final BitcoinWallet wallet;

  @override
  State<AddressDeletePage> createState() => _AddressDeletePageState();
}

class _AddressDeletePageState extends State<AddressDeletePage> {
  List<BitcoinAddress> _addresses = [];
  bool _loading = true;
  bool _confirming = false;
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

  Future<void> _confirmDelete(BitcoinAddress address) async {
    if (_confirming) return;
    _confirming = true;
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddressDeleteDialog(
        address: address,
        onDelete: () => widget.wallet.deleteAddress(address),
      ),
    );
    if (!mounted) return;
    _confirming = false;
    if (deleted != true) return;
    setState(() {
      _addresses.removeWhere((item) => item.address == address.address);
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('アドレスを削除しました')));
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
          onTap: () => _confirmDelete(address),
          onCopy: () => _copyAddress(address.address),
        );
      },
    );
  }
}
