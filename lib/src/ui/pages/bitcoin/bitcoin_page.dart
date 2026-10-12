import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:bitcoin_wallet/src/crypto/bitcoin/bitcoin_wallet.dart';
import 'package:bitcoin_wallet/src/core/wallet/network.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address_type.dart';
import 'package:bitcoin_wallet/src/ui/widgets/address/address_list_tile.dart';
import 'package:bitcoin_wallet/src/ui/widgets/address/address_qr_dialog.dart';
import 'package:bitcoin_wallet/src/ui/widgets/address/address_list.dart';
import 'package:bitcoin_wallet/src/ui/router/app_router.dart';
import 'package:bitcoin_wallet/src/ui/pages/bitcoin/bitcoin_send_page.dart';
import 'package:bitcoin_wallet/src/ui/pages/bitcoin/bitcoin_menu_page.dart';

class BitcoinPage extends StatefulWidget {
  const BitcoinPage({super.key, required this.wallet});

  final BitcoinWallet wallet;

  @override
  State<BitcoinPage> createState() => _BitcoinPageState();
}

class _BitcoinPageState extends State<BitcoinPage> {
  List<BitcoinAddress> _addresses = [];
  bool _loading = true;
  bool _creating = false;
  String? _error;
  bool _sending = false;
  bool _openingMenu = false;

  Future<void> _showMenu() async {
    if (_openingMenu) return;
    setState(() => _openingMenu = true);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => BitcoinMenuPage(wallet: widget.wallet)),
    );
    if (!mounted) return;
    setState(() => _openingMenu = false);
    await _loadAddresses();
  }

  Future<void> _showSend(BitcoinAddress address) async {
    if (_sending) return;
    _sending = true;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BitcoinSendPage(from: address, wallet: widget.wallet),
      ),
    );
    if (!mounted) return;
    _sending = false;
  }

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
        ..showSnackBar(
          const SnackBar(
            content: Text('コピーしました'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            elevation: 0,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('コピーできませんでした。もう一度お試しください。')));
    }
  }

  Future<void> _showDetails(BitcoinAddress address) async {
    var currentAddress = address;
    final send = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AddressQrDialog(
        name: address.displayName,
        address: address.address,
        onCopy: () => _copyAddress(address.address),
        onOpenExplorer: () => _openExplorer(address),
        onRename: (name) async {
          final renamed = currentAddress.copyWith(displayName: name);
          await widget.wallet.saveAddress(renamed);
          currentAddress = renamed;
          if (!mounted) return;
          setState(() {
            _addresses = _addresses
                .map((item) => item.address == renamed.address ? renamed : item)
                .toList();
          });
        },
        loadBalance: () => widget.wallet.getBalance(address),
        onSend: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (mounted && send == true) {
      await _showSend(currentAddress);
      if (mounted) await _showDetails(currentAddress);
    }
  }

  Future<void> _openExplorer(BitcoinAddress address) async {
    final url = widget.wallet.addressExplorerUrl(address);
    try {
      if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // ブラウザを開けなかった場合は以下で通知する。
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Explorerを開けませんでした。')));
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
    final theme = Theme.of(context);
    final network = widget.wallet.network;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        actions: [
          IconButton(
            tooltip: 'メニュー',
            onPressed: _openingMenu || _creating ? null : _showMenu,
            icon: const Icon(Icons.more_vert),
          ),
        ],
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Bitcoin'),
            ...[
              const SizedBox(height: 2),
              Text(
                network == Network.mainnet ? 'Mainnet' : 'Testnet4',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _buildAddresses(),
          ),
        ),
      ),
      floatingActionButton: SizedBox(
        height: 48,
        child: FloatingActionButton.extended(
          onPressed: _loading || _error != null || _creating
              ? null
              : _showCreate,
          backgroundColor: const Color(0xFFFFDABC),
          foregroundColor: const Color(0xFF221A15),
          elevation: 0,
          focusElevation: 0,
          hoverElevation: 0,
          highlightElevation: 0,
          disabledElevation: 0,
          extendedPadding: const EdgeInsets.symmetric(horizontal: 16),
          extendedIconLabelSpacing: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          icon: const Icon(Icons.add, size: 22),
          label: const Text(
            '新しいアドレス',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
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
