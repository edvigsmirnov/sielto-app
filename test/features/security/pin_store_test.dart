import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/core/crypto/kdf.dart';
import 'package:sielto/features/security/pin_store.dart';

void main() {
  setUpAll(() => Kdf.cheap = true);
  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  test('three free attempts, then 5 s, 15 s, 30 s, 60 s, doubling to 1 h', () {
    expect(
      <int>[for (int n = 0; n <= 14; n++) lockoutFor(n).inSeconds],
      <int>[0, 0, 0, 5, 15, 30, 60, 120, 240, 480, 960, 1920, 3600, 3600, 3600],
    );
  });

  test('a wrong PIN counts, a lockout refuses, the right PIN resets', () async {
    const PinStore store = PinStore();
    final DateTime t0 = DateTime.utc(2026, 9, 30, 12);
    await store.set('1234');
    expect(await store.isSet(), isTrue);

    expect(await store.check('0000', t0), t0);
    expect(await store.check('0000', t0), t0);
    final DateTime? third = await store.check('0000', t0);
    expect(third, t0.add(const Duration(seconds: 5)));

    // The right PIN during the lockout is not even checked.
    expect(
      await store.check('1234', t0.add(const Duration(seconds: 1))),
      third,
    );

    final DateTime later = t0.add(const Duration(seconds: 6));
    expect(await store.check('1234', later), isNull);
    expect(await store.check('0000', later), later);

    await store.clear();
    expect(await store.isSet(), isFalse);
  });
}
