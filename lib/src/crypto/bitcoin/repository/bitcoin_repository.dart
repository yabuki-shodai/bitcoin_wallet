import 'dart:convert';

import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_address.dart';
import 'package:hive/hive.dart';

abstract class BitcoinAddressRepository {
  /// ビットコインエンティティを取得
  Future<List<BitcoinAddress>> getAddresses();

  /// ビットコインエンティティを保存
  Future<void> saveAddress(BitcoinAddress address);

  /// ビットコインエンティティを削除
  Future<void> deleteAddress(BitcoinAddress address);
}

class BitcoinAddressRepositoryImpl implements BitcoinAddressRepository {
  static const String boxName = 'bitcoin_address';
  final Box<String> _box;

  BitcoinAddressRepositoryImpl(this._box);

  @override
  Future<void> deleteAddress(BitcoinAddress address) {
    return _box.delete(address.address);
  }

  @override
  Future<List<BitcoinAddress>> getAddresses() async {
    return _box.values
        .map(
          (value) => BitcoinAddress.fromJson(
            jsonDecode(value) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  @override
  Future<void> saveAddress(BitcoinAddress address) async {
    final json = jsonEncode(address.toJson());
    await _box.put(address.address, json);
  }
}
