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
    final addressStyle = theme.textTheme.bodySmall!.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      height: 1.4,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      minLeadingWidth: 24,
      horizontalTitleGap: 12,
      onTap: onTap,
      onLongPress: onCopy,
      leading: Icon(
        Icons.account_balance_wallet_outlined,
        size: 24,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        displayName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 5),
          Semantics(
            label: address,
            child: ExcludeSemantics(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  address.length <= 24
                      ? address
                      : '${address.substring(0, 12)}…${address.substring(address.length - 12)}',
                  maxLines: 1,
                  softWrap: false,
                  style: addressStyle,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFDDF0FF),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              format,
              style: theme.textTheme.labelMedium?.copyWith(
                color: const Color(0xFF2276AD),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      trailing: SizedBox(
        width: 66,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '$displayNameのアドレスをコピー',
              onPressed: onCopy,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              style: IconButton.styleFrom(
                minimumSize: const Size.square(44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              padding: const EdgeInsets.all(12),
              icon: Icon(
                Icons.copy_outlined,
                size: 19,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
