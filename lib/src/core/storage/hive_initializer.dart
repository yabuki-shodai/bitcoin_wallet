import 'package:hive_flutter/hive_flutter.dart';

class HiveInitializer {
  static Future<void> init() async {
    await Hive.initFlutter();
  }
}
