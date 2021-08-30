// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as HTML;

class DeviceInfo {
  static String get label {
    return 'Flutter Web';
  }

  static String get userAgent {
    return 'flutter-webrtc/web-plugin 0.0.1 ' +
        ' ( ' +
        HTML.window.navigator.userAgent +
        ' )';
  }
}
