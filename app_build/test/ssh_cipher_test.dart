import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:password_manager/core/utils/ssh_key.dart';
import 'package:password_manager/data/api/api_client.dart';
import 'package:password_manager/data/export/vault_export.dart';
import 'package:password_manager/data/import/importers.dart';
import 'package:password_manager/data/models/cipher.dart';

/// La clé SSH comme type d'élément : sérialisation, import, export.
///
/// Le point à ne pas rater est la traversée complète — un élément créé ici doit
/// pouvoir sortir par l'export et revenir par l'import sans rien perdre, sinon
/// une sauvegarde donnerait un faux sentiment de sécurité.

void main() {
  const key = SshKeyData(
    name: 'Serveur de déploiement',
    privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n'
        '-----END OPENSSH PRIVATE KEY-----\n',
    publicKey: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExemple tannou@poste',
    keyFingerprint: 'SHA256:abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG',
    notes: 'Déposée sur le VPS le 12 août.',
    fields: [CustomField(name: 'Hôte', value: 'vps.exemple.test')],
  );

  group('modèle', () {
    test('le type porte le numéro 5, comme chez Bitwarden', () {
      expect(CipherType.sshKey.wire, 5);
      expect(CipherType.fromWire(5), CipherType.sshKey);
      expect(key.type, CipherType.sshKey);
    });

    test('aller-retour JSON sans perte', () {
      final parsed = CipherData.fromJson(CipherType.sshKey, key.toJson());
      expect(parsed, isA<SshKeyData>());
      final ssh = parsed as SshKeyData;
      expect(ssh.name, key.name);
      expect(ssh.privateKey, key.privateKey);
      expect(ssh.publicKey, key.publicKey);
      expect(ssh.keyFingerprint, key.keyFingerprint);
      expect(ssh.notes, key.notes);
      expect(ssh.fields.single.name, 'Hôte');
    });

    test('une clé absente donne des chaînes vides, pas une exception', () {
      final parsed = CipherData.fromJson(CipherType.sshKey, {'name': 'Vide'});
      final ssh = parsed as SshKeyData;
      expect(ssh.privateKey, isEmpty);
      expect(ssh.publicKey, isEmpty);
      expect(ssh.keyFingerprint, isEmpty);
    });

    test('la clé privée n’entre pas dans l’index de recherche', () {
      // Sinon chercher « BEGIN » remonterait toutes les clés du coffre, et le
      // secret se promènerait dans une chaîne reconstruite à chaque frappe.
      expect(key.searchHaystack, isNot(contains('begin')));
      expect(key.searchHaystack, contains('serveur de déploiement'));
      expect(key.searchHaystack, contains('ssh-ed25519'));
    });
  });

  group('export puis réimport', () {
    test('le JSON conserve les trois champs', () {
      final item = CipherItem(
        id: '00000000-0000-4000-8000-000000000001',
        data: key,
      );
      final json = VaultExporter.toBitwardenJson([item]);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final exported = (decoded['items'] as List).single as Map<String, dynamic>;

      expect(exported['type'], 5);
      final sshKey = exported['sshKey'] as Map<String, dynamic>;
      expect(sshKey['privateKey'], key.privateKey);
      expect(sshKey['publicKey'], key.publicKey);
      expect(sshKey['keyFingerprint'], key.keyFingerprint);

      // Et l'importateur relit ce que l'exportateur a écrit.
      final parsed = parseImport(json);
      final back = parsed.items.single.data as SshKeyData;
      expect(back.privateKey, key.privateKey);
      expect(back.publicKey, key.publicKey);
      expect(back.notes, key.notes);
    });

    test('le CSV garde la clé publique et refuse la privée', () {
      // Un CSV est un fichier en clair : y déverser une clé privée serait une
      // fuite silencieuse, et un bloc PEM multiligne casserait de toute façon
      // le format.
      final item = CipherItem(
        id: '00000000-0000-4000-8000-000000000001',
        data: key,
      );
      final csv = VaultExporter.toCsv([item]);

      expect(csv, contains('ssh-ed25519'));
      expect(csv, contains('SHA256:'));
      expect(csv, isNot(contains('BEGIN OPENSSH')));
      expect(csv, contains('utiliser l’export chiffré'));
    });
  });

  group('import depuis Bitwarden', () {
    test('un élément de type 5 devient une clé SSH', () {
      const export = '''
{
  "encrypted": false,
  "folders": [],
  "items": [
    {
      "id": "1",
      "type": 5,
      "name": "GitHub deploy",
      "notes": "clé de déploiement",
      "sshKey": {
        "privateKey": "-----BEGIN OPENSSH PRIVATE KEY-----\\nAAAA\\n-----END OPENSSH PRIVATE KEY-----",
        "publicKey": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExemple moi@poste",
        "keyFingerprint": "SHA256:empreinte-du-fichier"
      }
    }
  ]
}''';

      final parsed = parseImport(export);
      expect(parsed.count, 1);
      final ssh = parsed.items.single.data as SshKeyData;
      expect(ssh.name, 'GitHub deploy');
      expect(ssh.publicKey, startsWith('ssh-ed25519 '));
      expect(ssh.privateKey, contains('BEGIN OPENSSH'));
      expect(ssh.notes, 'clé de déploiement');
    });

    test('l’empreinte est recalculée plutôt que crue sur parole', () async {
      // L'empreinte du fichier est une affirmation ; celle qu'on dérive de la
      // clé publique est vérifiable. Une entrée dont l'empreinte ne correspond
      // pas à sa clé serait autrement importée telle quelle, et la comparaison
      // avec le serveur échouerait sans qu'on comprenne pourquoi.
      final real = await SshKeys.generateEd25519(comment: 'moi@poste');
      final export = jsonEncode({
        'encrypted': false,
        'items': [
          {
            'id': '1',
            'type': 5,
            'name': 'Clé',
            'sshKey': {
              'privateKey': real.privateKey,
              'publicKey': real.publicKey,
              'keyFingerprint': 'SHA256:mensonge',
            },
          }
        ],
      });

      final ssh = parseImport(export).items.single.data as SshKeyData;
      expect(ssh.keyFingerprint, real.fingerprint);
      expect(ssh.keyFingerprint, isNot('SHA256:mensonge'));
    });

    test('une clé publique illisible conserve l’empreinte du fichier', () {
      // Perdre l'information serait pire que de garder une valeur douteuse :
      // l'utilisateur peut encore la comparer à la main.
      final export = jsonEncode({
        'encrypted': false,
        'items': [
          {
            'id': '1',
            'type': 5,
            'name': 'Clé',
            'sshKey': {
              'privateKey': '',
              'publicKey': 'pas une clé',
              'keyFingerprint': 'SHA256:valeur-conservée',
            },
          }
        ],
      });

      final ssh = parseImport(export).items.single.data as SshKeyData;
      expect(ssh.keyFingerprint, 'SHA256:valeur-conservée');
    });
  });

  group('avertissement HTTP', () {
    test('une adresse Tailscale n’est pas signalée', () {
      // 100.64.0.0/10 : le transport est du WireGuard, donc chiffré. Avertir
      // ici serait un faux positif — et l'utilisateur apprendrait à ignorer
      // l'avertissement.
      expect(isInsecureServerUrl('http://100.77.208.122:3000'), isFalse);
      expect(isInsecureServerUrl('http://100.64.0.1:3000'), isFalse);
      expect(isInsecureServerUrl('http://100.127.255.254'), isFalse);
    });

    test('la boucle locale non plus', () {
      expect(isInsecureServerUrl('http://localhost:3000'), isFalse);
      expect(isInsecureServerUrl('http://127.0.0.1:3000'), isFalse);
    });

    test('les bords de la plage sont exclus', () {
      // 100.63 et 100.128 sont hors de 100.64.0.0/10 : ce sont des adresses
      // publiques ordinaires.
      expect(isInsecureServerUrl('http://100.63.0.1:3000'), isTrue);
      expect(isInsecureServerUrl('http://100.128.0.1:3000'), isTrue);
      expect(isInsecureServerUrl('http://101.64.0.1:3000'), isTrue);
    });

    test('un réseau local ordinaire reste signalé', () {
      // Là, le HTTP est bel et bien en clair sur le lien.
      expect(isInsecureServerUrl('http://192.168.1.10:3000'), isTrue);
      expect(isInsecureServerUrl('http://10.0.0.5:3000'), isTrue);
      expect(isInsecureServerUrl('http://coffre.exemple.com'), isTrue);
    });

    test('le HTTPS ne l’est jamais', () {
      expect(isInsecureServerUrl('https://coffre.exemple.com'), isFalse);
      expect(isInsecureServerUrl('https://192.168.1.10'), isFalse);
    });
  });
}
