import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

class KeyValueStore {
  KeyValueStore();
  SharedPreferences _preferences;

  init() async {
    _preferences = await SharedPreferences.getInstance();
  }

  String getString(String key) => _preferences.getString(key);

  Future<bool> setString(String key, String value) =>
      _preferences.setString(key, value);
}
