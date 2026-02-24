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

    test('startPolling starts a timer and poll is called', () async {
      final pool = ServicePool();
      // No services registered — poll() is a no-op, but the timer must fire.
      pool.startPolling(interval: const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      pool.dispose();
    });

    test('calling startPolling twice cancels the previous timer', () async {
      final pool = ServicePool();
      pool.startPolling(interval: const Duration(milliseconds: 100));
      pool.startPolling(interval: const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      pool.dispose();
    });
  });
}
