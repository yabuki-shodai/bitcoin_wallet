import 'package:flutter/material.dart';

class AddressListTile extends StatelessWidget {
  const AddressListTile({
    super.key,
    required this.name,
    required this.address,
    required this.format,
    required this.onTap,
    required this.onCopy,
  });

  final String name;
  final String address;
  final String format;
  final VoidCallback onTap;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = name.trim().isEmpty ? '名前なし' : name;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      minLeadingWidth: 32,
      onTap: onTap,
      onLongPress: onCopy,
      leading: const Icon(Icons.account_balance_wallet_outlined, size: 28),
      title: Text(
        displayName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            address,
            softWrap: true,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFDDF0FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              format,
              style: theme.textTheme.labelMedium?.copyWith(
                color: const Color(0xFF178DE1),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      trailing: IconButton(
        tooltip: '$displayNameのアドレス詳細を開く',
        onPressed: onTap,
        icon: const Icon(Icons.chevron_right, size: 25),
      ),
    );
  }
}
