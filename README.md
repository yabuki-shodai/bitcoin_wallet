# bitcoin wallet

## Run locally

From the project root:

```sh
flutter pub get
dart run build_runner build
flutter run
```

## Change the network

Edit the `network` argument of `BitcoinWallet` in `lib/main.dart`:

```dart
network: Network.testnet, // Bitcoin Testnet4 (default)
```

To use Bitcoin Mainnet, change it to:

```dart
network: Network.mainnet,
```

Stop the app and run `flutter run` again to apply the change.

## Supported address types

| Address type | Create / receive | Send from | Send to |
| --- | --- | --- | --- |
| P2PKH (Legacy) | Supported | Supported | Supported |
| P2WPKH (Native SegWit) | Supported | Supported | Supported |
| P2SH, including P2SH-P2WPKH (Nested SegWit) | Not supported | Not supported | Not supported |
| P2WSH | Not supported | Not supported | Not supported |
| P2TR (Taproot) | Not supported | Not supported | Not supported |

Both Bitcoin Mainnet and Testnet4 are supported. Destination addresses must match the wallet's selected network.

- P2PKH addresses start with `1` on Mainnet and `m` or `n` on Testnet4.
- P2WPKH addresses start with `bc1q` on Mainnet and `tb1q` on Testnet4. These prefixes are also used by P2WSH, which is not supported; validation checks the address type as well as its prefix.
- Some unsupported types are defined in the address type enum for future use. Their presence does not mean address generation or transactions support them.

## Data storage

- Address information (display name, address, network, public key, and address type) is stored locally as JSON in the Hive box named `bitcoin_address`.
- Private keys are stored separately using `flutter_secure_storage`, under the key `bitcoin:privateKey:<address>`.
- Selecting an address on the deletion page opens a confirmation dialog. Confirming deletion removes both its address information and private key. Without a backup, funds sent to that address can become inaccessible.

The storage backend and physical location depend on the target platform.

## License

Licensed under the MIT License. See [LICENSE](LICENSE).
