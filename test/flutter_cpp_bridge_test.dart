import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cpp_bridge/flutter_cpp_bridge.dart';

void main() {
  group('ServicePool', () {
    test('can be instantiated', () {
      final pool = ServicePool();
      expect(pool, isNotNull);
    });

    test('dispose on empty pool does not throw', () {
      final pool = ServicePool();
      expect(() => pool.dispose(), returnsNormally);
    });
  });
}
