import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:password_manager/core/lock/clipboard_guard.dart';
import 'package:password_manager/core/lock/lock_controller.dart';
import 'package:password_manager/core/settings/app_settings.dart';
import 'package:password_manager/core/settings/lock_settings.dart';
import 'package:password_manager/data/api/api_client.dart';
import 'package:password_manager/data/api/passvault_api.dart';
import 'package:password_manager/data/models/cipher.dart';
import 'package:password_manager/data/vault_repository.dart';

/// L'horloge est injectée : sans ça, tester un verrouillage à 15 minutes
/// demanderait d'attendre 15 minutes.

VaultRepository _repo() => VaultRepository(
      api: PassvaultApi(ApiClient(baseUrl: 'http://127.0.0.1:1')),
      deviceName: 'test',
    );

Future<VaultRepository> _unlockedRepo() async {
  final repo = _repo();
  await repo.seedForTest(items: const [
    CipherItem(
      id: '00000000-0000-4000-8000-000000000001',
      data: LoginData(name: 'Test', password: 'x'),
    ),
  ]);
  return repo;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('verrouillage par inactivité', () {
    test('ne verrouille pas avant le délai', () async {
      final settings = await AppSettings.load();
      await settings.setAutoLock(AutoLockDelay.fiveMinutes);
      final repo = await _unlockedRepo();
      addTearDown(repo.dispose);

      var now = DateTime(2026, 8, 11, 12, 0);
      final lock = LockController(
        vault: repo,
        settings: settings,
        tick: const Duration(milliseconds: 10),
        clock: () => now,
      );
      addTearDown(lock.dispose);

      now = now.add(const Duration(minutes: 4, seconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(repo.isUnlocked, isTrue);
    });

    test('verrouille une fois le délai dépassé', () async {
      final settings = await AppSettings.load();
      await settings.setAutoLock(AutoLockDelay.fiveMinutes);
      final repo = await _unlockedRepo();
      addTearDown(repo.dispose);

      var now = DateTime(2026, 8, 11, 12, 0);
      final lock = LockController(
        vault: repo,
        settings: settings,
        tick: const Duration(milliseconds: 10),
        clock: () => now,
      );
      addTearDown(lock.dispose);

      now = now.add(const Duration(minutes: 5, seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(repo.isUnlocked, isFalse);
      // Le verrouillage vide bien le coffre en mémoire.
      expect(repo.items, isEmpty);
    });

    test('une interaction repousse l’échéance', () async {
      final settings = await AppSettings.load();
      await settings.setAutoLock(AutoLockDelay.fiveMinutes);
      final repo = await _unlockedRepo();
      addTearDown(repo.dispose);

      var now = DateTime(2026, 8, 11, 12, 0);
      final lock = LockController(
        vault: repo,
        settings: settings,
        tick: const Duration(milliseconds: 10),
        clock: () => now,
      );
      addTearDown(lock.dispose);

      now = now.add(const Duration(minutes: 4));
      lock.registerActivity();
      now = now.add(const Duration(minutes: 4));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // 8 minutes écoulées au total, mais seulement 4 depuis l'interaction.
      expect(repo.isUnlocked, isTrue);
    });

    test('« jamais » ne verrouille pas, même après des heures', () async {
      final settings = await AppSettings.load();
      await settings.setAutoLock(AutoLockDelay.never);
      final repo = await _unlockedRepo();
      addTearDown(repo.dispose);

      var now = DateTime(2026, 8, 11, 12, 0);
      final lock = LockController(
        vault: repo,
        settings: settings,
        tick: const Duration(milliseconds: 10),
        clock: () => now,
      );
      addTearDown(lock.dispose);

      now = now.add(const Duration(hours: 12));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(repo.isUnlocked, isTrue);
    });

    test('le temps restant décroît puis s’annule', () async {
      final settings = await AppSettings.load();
      await settings.setAutoLock(AutoLockDelay.fiveMinutes);
      final repo = await _unlockedRepo();
      addTearDown(repo.dispose);

      var now = DateTime(2026, 8, 11, 12, 0);
      final lock = LockController(
        vault: repo,
        settings: settings,
        tick: const Duration(seconds: 30),
        clock: () => now,
      );
      addTearDown(lock.dispose);

      expect(lock.remaining, const Duration(minutes: 5));
      now = now.add(const Duration(minutes: 2));
      expect(lock.remaining, const Duration(minutes: 3));
      now = now.add(const Duration(minutes: 10));
      expect(lock.remaining, Duration.zero);
    });

    test('un coffre verrouillé n’a pas de temps restant', () async {
      final settings = await AppSettings.load();
      await settings.setAutoLock(AutoLockDelay.fiveMinutes);
      final repo = _repo();
      addTearDown(repo.dispose);

      final lock = LockController(vault: repo, settings: settings);
      addTearDown(lock.dispose);

      expect(repo.isUnlocked, isFalse);
      expect(lock.remaining, isNull);
    });

    test('le déverrouillage remet le compteur à zéro', () async {
      final settings = await AppSettings.load();
      await settings.setAutoLock(AutoLockDelay.oneMinute);
      final repo = _repo();
      addTearDown(repo.dispose);

      var now = DateTime(2026, 8, 11, 12, 0);
      final lock = LockController(
        vault: repo,
        settings: settings,
        tick: const Duration(milliseconds: 10),
        clock: () => now,
      );
      addTearDown(lock.dispose);

      // Le contrôleur existe depuis longtemps quand le coffre s'ouvre enfin.
      now = now.add(const Duration(hours: 3));
      await repo.seedForTest(items: const []);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // Sans remise à zéro, le coffre se refermerait immédiatement.
      expect(repo.isUnlocked, isTrue);
    });
  });

  group('passage en arrière-plan', () {
    test('verrouille quand le réglage est actif', () async {
      final settings = await AppSettings.load();
      await settings.setLockOnBackground(true);
      await settings.setAutoLock(AutoLockDelay.never);
      final repo = await _unlockedRepo();
      addTearDown(repo.dispose);

      final lock = LockController(vault: repo, settings: settings);
      addTearDown(lock.dispose);

      lock.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(repo.isUnlocked, isFalse);
    });

    test('ne verrouille pas quand le réglage est désactivé', () async {
      final settings = await AppSettings.load();
      await settings.setLockOnBackground(false);
      await settings.setAutoLock(AutoLockDelay.never);
      final repo = await _unlockedRepo();
      addTearDown(repo.dispose);

      final lock = LockController(vault: repo, settings: settings);
      addTearDown(lock.dispose);

      lock.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(repo.isUnlocked, isTrue);
    });

    test('« inactive » seul ne verrouille pas', () async {
      // Cet état arrive pour un simple panneau système ou un appel entrant :
      // verrouiller dessus rendrait l'app inutilisable.
      final settings = await AppSettings.load();
      await settings.setLockOnBackground(true);
      final repo = await _unlockedRepo();
      addTearDown(repo.dispose);

      final lock = LockController(vault: repo, settings: settings);
      addTearDown(lock.dispose);

      lock.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(repo.isUnlocked, isTrue);
    });

    test('le temps passé en arrière-plan compte au retour', () async {
      // Le point clé : un Timer ne progresse pas pendant que le processus est
      // suspendu. Sans rattrapage, une nuit en arrière-plan ne verrouillerait
      // rien.
      final settings = await AppSettings.load();
      await settings.setLockOnBackground(false);
      await settings.setAutoLock(AutoLockDelay.fiveMinutes);
      final repo = await _unlockedRepo();
      addTearDown(repo.dispose);

      var now = DateTime(2026, 8, 11, 12, 0);
      final lock = LockController(
        vault: repo,
        settings: settings,
        tick: const Duration(hours: 1),
        clock: () => now,
      );
      addTearDown(lock.dispose);

      lock.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(repo.isUnlocked, isTrue, reason: 'lockOnBackground est désactivé');

      // Huit heures plus tard, sans qu'aucun tick n'ait pu se produire.
      now = now.add(const Duration(hours: 8));
      lock.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(repo.isUnlocked, isFalse);
    });

    test('un aller-retour rapide ne verrouille pas', () async {
      final settings = await AppSettings.load();
      await settings.setLockOnBackground(false);
      await settings.setAutoLock(AutoLockDelay.fifteenMinutes);
      final repo = await _unlockedRepo();
      addTearDown(repo.dispose);

      var now = DateTime(2026, 8, 11, 12, 0);
      final lock = LockController(
        vault: repo,
        settings: settings,
        tick: const Duration(hours: 1),
        clock: () => now,
      );
      addTearDown(lock.dispose);

      lock.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 20));
      lock.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(repo.isUnlocked, isTrue);
    });

    test('« immédiatement » verrouille même sans lockOnBackground', () async {
      final settings = await AppSettings.load();
      await settings.setLockOnBackground(false);
      await settings.setAutoLock(AutoLockDelay.immediate);
      final repo = await _unlockedRepo();
      addTearDown(repo.dispose);

      final lock = LockController(vault: repo, settings: settings);
      addTearDown(lock.dispose);

      lock.didChangeAppLifecycleState(AppLifecycleState.hidden);
      expect(repo.isUnlocked, isFalse);
    });
  });

  group('presse-papiers', () {
    /// Simule le presse-papiers de la plateforme, qui n'existe pas en test.
    late Map<String, String?> board;

    setUp(() {
      board = {'text': null};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          board['text'] = (call.arguments as Map)['text'] as String?;
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          return {'text': board['text']};
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('copie la valeur demandée', () async {
      final settings = await AppSettings.load();
      final guard = ClipboardGuard(settings);
      addTearDown(guard.dispose);

      await guard.copy('hunter2');
      expect(board['text'], 'hunter2');
    });

    test('efface au verrouillage sans attendre le délai', () async {
      final settings = await AppSettings.load();
      await settings.setClipboardClear(ClipboardClearDelay.twoMinutes);
      final guard = ClipboardGuard(settings);
      addTearDown(guard.dispose);

      await guard.copy('hunter2');
      await guard.onLock();
      expect(board['text'], ' ');
    });

    test('n’écrase pas ce que l’utilisateur a copié entre-temps', () async {
      final settings = await AppSettings.load();
      final guard = ClipboardGuard(settings);
      addTearDown(guard.dispose);

      await guard.copy('hunter2');
      // L'utilisateur copie autre chose depuis une autre app.
      board['text'] = 'une adresse que je viens de copier';

      await guard.clearIfOurs();
      expect(board['text'], 'une adresse que je viens de copier');
    });

    test('« jamais » n’efface pas après le délai', () async {
      final settings = await AppSettings.load();
      await settings.setClipboardClear(ClipboardClearDelay.never);
      final guard = ClipboardGuard(settings);
      addTearDown(guard.dispose);

      await guard.copy('hunter2');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(board['text'], 'hunter2');
    });

    test('n’efface rien si on n’a jamais copié', () async {
      final settings = await AppSettings.load();
      final guard = ClipboardGuard(settings);
      addTearDown(guard.dispose);

      board['text'] = 'contenu de quelqu’un d’autre';
      await guard.clearIfOurs();
      expect(board['text'], 'contenu de quelqu’un d’autre');
    });

    test('décrit le réglage courant', () async {
      final settings = await AppSettings.load();
      final guard = ClipboardGuard(settings);
      addTearDown(guard.dispose);

      await settings.setClipboardClear(ClipboardClearDelay.never);
      expect(guard.describeDelay, contains('n’est pas effacé'));

      await settings.setClipboardClear(ClipboardClearDelay.tenSeconds);
      expect(guard.describeDelay, 'après 10 secondes');
    });
  });

  group('persistance des réglages', () {
    test('les réglages de verrouillage survivent à un redémarrage', () async {
      final first = await AppSettings.load();
      await first.setAutoLock(AutoLockDelay.thirtyMinutes);
      await first.setLockOnBackground(false);
      await first.setClipboardClear(ClipboardClearDelay.twoMinutes);

      // Une nouvelle instance relit le même stockage.
      final second = await AppSettings.load();
      expect(second.autoLock, AutoLockDelay.thirtyMinutes);
      expect(second.lockOnBackground, isFalse);
      expect(second.clipboardClear, ClipboardClearDelay.twoMinutes);
    });

    test('les valeurs par défaut sont prudentes', () async {
      final settings = await AppSettings.load();
      // Verrouillage en arrière-plan actif, et un délai d'inactivité fini.
      expect(settings.lockOnBackground, isTrue);
      expect(settings.autoLock.isNever, isFalse);
      expect(settings.clipboardClear.isNever, isFalse);
      expect(settings.biometricUnlock, isFalse);
    });
  });
}
