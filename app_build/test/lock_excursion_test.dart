import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:password_manager/core/crypto/kdf_params.dart';
import 'package:password_manager/core/lock/lock_controller.dart';
import 'package:password_manager/core/settings/app_settings.dart';
import 'package:password_manager/core/settings/lock_settings.dart';
import 'package:password_manager/data/api/api_client.dart';
import 'package:password_manager/data/api/coffort_api.dart';
import 'package:password_manager/data/vault_repository.dart';

/// Excursions volontaires hors de l'app.
///
/// Le sélecteur de fichiers d'Android fait passer l'app en arrière-plan. Avec
/// « verrouiller en quittant » actif, le coffre se verrouillait donc pendant
/// qu'on choisissait le fichier à importer : on revenait sur un écran devenu
/// inerte, et l'import échouait ensuite sur un coffre sans clé — sans rien
/// afficher, puisque le verrou lève un StateError et non une ApiFailure.
///
/// Ce qui est vérifié ici : l'excursion suspend le verrouillage **de fond**,
/// mais jamais celui d'inactivité.

Future<VaultRepository> _unlockedVault() async {
  final repo = VaultRepository(
    api: CoffortApi(ApiClient(baseUrl: 'http://127.0.0.1:1')),
    deviceName: 'test',
  );
  await repo.seedForTest(
    items: const [],
    profile: const VaultProfile(
      id: 'u1',
      email: 'tannou@coffort.test',
      kdf: KdfParams.argon2idDefault,
      kdfSalt: '0123456789abcdef0123456789abcdef',
      protectedKey: '1.AAAA',
    ),
  );
  return repo;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VaultRepository vault;
  late AppSettings settings;
  late LockController lock;
  late DateTime now;

  setUp(() async {
    now = DateTime(2026, 8, 12, 10);
    vault = await _unlockedVault();
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
    lock = LockController(
      vault: vault,
      settings: settings,
      clock: () => now,
    );
  });

  tearDown(() {
    lock.dispose();
    vault.dispose();
  });

  test('sans excursion, passer en arrière-plan verrouille', () async {
    await settings.setLockOnBackground(true);
    expect(vault.isUnlocked, isTrue);

    lock.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(vault.isUnlocked, isFalse,
        reason: 'le réglage « verrouiller en quittant » doit s’appliquer');
  });

  test('pendant une excursion, il ne verrouille pas', () async {
    await settings.setLockOnBackground(true);

    await lock.duringExcursion(() async {
      // Ce que fait le système quand le sélecteur de fichiers s'ouvre.
      lock.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(vault.isUnlocked, isTrue,
          reason: 'le coffre doit rester ouvert le temps de choisir');
      lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
    });

    expect(vault.isUnlocked, isTrue);
  });

  test('après l’excursion, le verrouillage de fond reprend', () async {
    await settings.setLockOnBackground(true);
    await lock.duringExcursion(() async {});

    lock.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(vault.isUnlocked, isFalse,
        reason: 'l’exemption ne vaut que pour la durée de l’excursion');
  });

  test('une excursion qui échoue ne laisse pas l’exemption active', () async {
    await settings.setLockOnBackground(true);

    await expectLater(
      lock.duringExcursion(() async => throw StateError('sélecteur en échec')),
      throwsStateError,
    );

    lock.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(vault.isUnlocked, isFalse);
  });

  test('deux excursions imbriquées : la première à finir ne réarme pas',
      () async {
    await settings.setLockOnBackground(true);

    await lock.duringExcursion(() async {
      await lock.duringExcursion(() async {});
      // L'excursion interne est finie, l'externe non : toujours exempté.
      lock.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(vault.isUnlocked, isTrue);
    });
  });

  test('l’excursion ne dispense pas du verrouillage par inactivité', () async {
    // Le point à ne pas laisser filer : une excursion suspend la réaction au
    // passage en arrière-plan, pas le décompte du temps. Un sélecteur laissé
    // ouvert une heure doit finir sur un coffre verrouillé.
    await settings.setAutoLock(AutoLockDelay.oneMinute);
    await settings.setLockOnBackground(false);

    await lock.duringExcursion(() async {
      lock.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(hours: 1));
      lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
    });

    expect(vault.isUnlocked, isFalse,
        reason: 'le délai d’inactivité court toujours pendant l’excursion');
  });
}
