import 'package:hive_flutter/hive_flutter.dart';

class HiveInitializer {
  static Future<void> init() async {
    await Hive.initFlutter();
    await _openBoxIfNeeded('bitcoin_address');
  }

  static Future<void> _openBoxIfNeeded(String name) async {
    if (!Hive.isBoxOpen(name)) {
      await Hive.openBox<String>(name);
    }
  }
}
