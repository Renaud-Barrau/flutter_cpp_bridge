import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_cpp_bridge_platform_interface.dart';

/// An implementation of [FlutterCppBridgePlatform] that uses method channels.
class MethodChannelFlutterCppBridge extends FlutterCppBridgePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_cpp_bridge');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
