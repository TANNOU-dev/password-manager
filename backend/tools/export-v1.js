#!/usr/bin/env node
// Extrait un coffre PassVault v1 en JSON clair, pour le réimporter ensuite dans
// le coffre v2 chiffré côté client.
//
//   node tools/export-v1.js /chemin/vers/passwords.db > coffre-v1.json
//
// À noter : ce script n'a pas besoin du mot de passe maître. En v1 la clé AES
// était le hash stocké dans la table `master`, donc la base contenait à la fois
// le chiffré et sa clé. C'est précisément ce que la v2 corrige.
//
// Le fichier produit est en clair. À traiter comme le coffre lui-même :
// le supprimer dès l'import terminé.

const Database = require('better-sqlite3');
const CryptoJS = require('crypto-js');

const dbPath = process.argv[2];
if (!dbPath) {
  console.error('usage: node tools/export-v1.js <chemin/passwords.db>');
  process.exit(1);
}

const db = new Database(dbPath, { readonly: true, fileMustExist: true });

const master = db.prepare('SELECT hash FROM master WHERE id = 1').get();
if (!master) {
  console.error('Aucun mot de passe maître dans cette base : rien à extraire.');
  process.exit(1);
}

const rows = db.prepare('SELECT id, encrypted_data, created_at FROM passwords').all();
const entries = [];
const failures = [];

for (const row of rows) {
  try {
    const plain = CryptoJS.AES.decrypt(row.encrypted_data, master.hash).toString(
      CryptoJS.enc.Utf8
    );
    if (!plain) throw new Error('déchiffrement vide');
    const data = JSON.parse(plain);
    entries.push({
      site: data.site ?? '',
      email: data.email ?? '',
      password: data.password ?? '',
      note: data.note ?? '',
      createdAt: row.created_at,
    });
  } catch (e) {
    failures.push({ id: row.id, reason: e.message });
  }
}

process.stdout.write(
  JSON.stringify({ version: 1, exportedAt: new Date().toISOString(), entries }, null, 2)
);

console.error(`\n${entries.length} entrée(s) extraite(s).`);
if (failures.length > 0) {
  console.error(`${failures.length} entrée(s) illisible(s) :`);
  for (const f of failures) console.error(`  id=${f.id} — ${f.reason}`);
}
db.close();
