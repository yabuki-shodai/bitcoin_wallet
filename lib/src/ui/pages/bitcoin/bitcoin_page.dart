import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/wallet/wallet.dart';
import '../../../crypto/bitcoin/models/bitcoin_address.dart';
import '../../../crypto/bitcoin/models/bitcoin_address_type.dart';
import '../../widgets/address/address_list_tile.dart';
import '../../widgets/address/address_qr_dialog.dart';
import '../../widgets/address/address_list.dart';
import '../../router/app_router.dart';

class BitcoinPage extends StatefulWidget {
  const BitcoinPage({super.key, required this.wallet});

  final Wallet<BitcoinAddress> wallet;

  @override
  State<BitcoinPage> createState() => _BitcoinPageState();
}

class _BitcoinPageState extends State<BitcoinPage> {
  List<BitcoinAddress> _addresses = [];
  bool _loading = true;
  bool _creating = false;
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

  String _formatLabel(BitcoinAddressType type) => switch (type) {
    BitcoinAddressType.p2pkh => 'P2PKH',
    BitcoinAddressType.p2shP2wpkh => 'P2SH-P2WPKH',
    BitcoinAddressType.p2wpkh => 'P2WPKH',
    BitcoinAddressType.p2tr => 'P2TR',
  };

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

  Future<void> _showDetails(BitcoinAddress address) {
    return showDialog<void>(
      context: context,
      builder: (_) =>
          AddressQrDialog(name: address.displayName, address: address.address),
    );
  }

  Future<void> _showCreate() async {
    if (_creating) return;
    setState(() => _creating = true);
    final created = await Navigator.of(
      context,
    ).pushNamed<BitcoinAddress>(AppRouter.bitcoinCreate);
    if (!mounted) return;
    setState(() {
      _creating = false;
      if (created != null) {
        _addresses = [
          created,
          ..._addresses.where((item) => item.address != created.address),
        ];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bitcoin')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _buildAddresses(),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _error != null || _creating ? null : _showCreate,
        backgroundColor: const Color(0xFFFFDABC),
        foregroundColor: const Color(0xFF221A15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        icon: const Icon(Icons.add, size: 26),
        label: const Text('新しいアドレス'),
      ),
    );
  }

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
          onTap: () => _showDetails(address),
          onCopy: () => _copyAddress(address.address),
        );
      },
    );
  }
}
