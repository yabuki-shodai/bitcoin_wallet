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

## Data storage

- Address information (display name, address, network, public key, and address type) is stored locally as JSON in the Hive box named `bitcoin_address`.
- Private keys are stored separately using `flutter_secure_storage`, under the key `bitcoin:privateKey:<address>`.
- Selecting an address on the deletion page opens a confirmation dialog. Confirming deletion removes both its address information and private key. Without a backup, funds sent to that address can become inaccessible.

The storage backend and physical location depend on the target platform.

## License

Licensed under the MIT License. See [LICENSE](LICENSE).
