const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');

const { createApp } = require('../src/app');

// Base neuve par exécution : les tests ne doivent jamais toucher un vrai coffre.
const dbPath = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'passvault-test-')),
  'vault.db'
);

const config = {
  dbPath,
  corsOrigins: ['http://localhost:8080'],
  sessionTtlDays: 30,
  defaultKdf: { type: 'argon2id', iterations: 3, memory: 65536, parallelism: 4 },
  registration: { mode: 'first-only', token: null },
  maxImportItems: 5000,
  maxBodyBytes: '512kb',
  loginRateLimit: { windowMs: 60_000, maxAttempts: 5 },
};

const { app } = createApp(config);
let server;
let baseUrl;

test.before(async () => {
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

test.after(() => server?.close());

// Un masterPasswordHash est un condensé de 32 octets en base64. Les tests n'ont
// pas besoin de rejouer Argon2id : le serveur ne vérifie que la forme.
const clientHash = (seed) =>
  crypto.createHash('sha256').update(seed).digest('base64');

// Chaîne au format attendu : "1." + base64(nonce‖chiffré‖mac).
const enc = (label) =>
  '1.' + Buffer.concat([crypto.randomBytes(12), Buffer.from(label), crypto.randomBytes(16)]).toString('base64');

async function call(method, url, { body, token } = {}) {
  const res = await fetch(baseUrl + url, {
    method,
    headers: {
      ...(body ? { 'Content-Type': 'application/json' } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

const EMAIL = 'tannou@example.test';
const GOOD = clientHash('bon-mot-de-passe');
const BAD = clientHash('mauvais-mot-de-passe');
let token;

test('le serveur accepte une inscription tant qu’aucun coffre n’existe', async () => {
  const { status, body } = await call('GET', '/api/status');
  assert.equal(status, 200);
  assert.equal(body.zeroKnowledge, true);
  assert.equal(body.acceptsRegistration, true);
});

test('prelogin ne permet pas de distinguer un compte absent d’un compte présent', async () => {
  const absent = await call('POST', '/api/accounts/prelogin', {
    body: { email: 'inconnu@example.test' },
  });
  assert.equal(absent.status, 200);
  assert.match(absent.body.kdfSalt, /^[0-9a-f]{32}$/);
  assert.equal(absent.body.kdf.type, 'argon2id');

  // Déterministe : deux appels sur le même e-mail absent donnent le même sel,
  // sinon un attaquant repérerait les comptes absents à leur instabilité.
  const again = await call('POST', '/api/accounts/prelogin', {
    body: { email: 'inconnu@example.test' },
  });
  assert.equal(again.body.kdfSalt, absent.body.kdfSalt);
});

// Invariant sur lequel repose le client : il dérive sa clé contre le sel obtenu
// avant l'inscription. Si le serveur en retenait un autre, le coffre serait
// illisible au déverrouillage suivant.
let saltBeforeRegister;
test('le sel servi avant inscription est celui qui sera retenu', async () => {
  const pre = await call('POST', '/api/accounts/prelogin', { body: { email: EMAIL } });
  saltBeforeRegister = pre.body.kdfSalt;
  assert.match(saltBeforeRegister, /^[0-9a-f]{32}$/);
});

test('l’inscription crée le coffre et ouvre une session', async () => {
  const { status, body } = await call('POST', '/api/accounts/register', {
    body: {
      email: EMAIL,
      masterPasswordHash: GOOD,
      protectedKey: enc('cle-du-coffre'),
      deviceName: 'test-suite',
    },
  });
  assert.equal(status, 201);
  assert.ok(body.token);
  assert.equal(body.profile.email, EMAIL);
  assert.equal(
    body.profile.kdfSalt,
    saltBeforeRegister,
    'le sel ne doit pas changer entre prelogin et register'
  );
  token = body.token;
});

test('le sel reste stable après inscription', async () => {
  const pre = await call('POST', '/api/accounts/prelogin', { body: { email: EMAIL } });
  assert.equal(pre.body.kdfSalt, saltBeforeRegister);
});

test('le mode first-only referme les inscriptions après le premier coffre', async () => {
  const status = await call('GET', '/api/status');
  assert.equal(status.body.acceptsRegistration, false);

  const second = await call('POST', '/api/accounts/register', {
    body: {
      email: 'intrus@example.test',
      masterPasswordHash: GOOD,
      protectedKey: enc('x'),
    },
  });
  assert.equal(second.status, 403);
});

test('un protectedKey mal formé est refusé', async () => {
  // Compte neuf impossible en first-only : on vérifie la validation via /password.
  const res = await call('POST', '/api/accounts/password', {
    token,
    body: {
      masterPasswordHash: GOOD,
      newMasterPasswordHash: clientHash('autre'),
      newProtectedKey: 'pas-du-tout-chiffre',
    },
  });
  assert.equal(res.status, 400);
  assert.match(res.body.error, /chiffrée préfixée/);
});

test('une requête sans jeton est refusée', async () => {
  const res = await call('GET', '/api/sync');
  assert.equal(res.status, 401);
});

test('un jeton inventé est refusé', async () => {
  const res = await call('GET', '/api/sync', { token: 'jeton-bidon' });
  assert.equal(res.status, 401);
});

test('la synchronisation part d’un coffre vide', async () => {
  const { status, body } = await call('GET', '/api/sync', { token });
  assert.equal(status, 200);
  assert.equal(body.ciphers.length, 0);
  assert.equal(body.folders.length, 0);
  assert.equal(body.profile.email, EMAIL);
});

test('le serveur stocke et rend un élément sans jamais le lire', async () => {
  const blob = enc('github|tannou|hunter2');
  const created = await call('POST', '/api/ciphers', {
    token,
    body: { type: 1, data: blob, favorite: true },
  });
  assert.equal(created.status, 201);
  assert.equal(created.body.data, blob, 'le blob doit revenir octet pour octet');
  assert.equal(created.body.favorite, true);
  assert.equal(created.body.deletedAt, null);

  const sync = await call('GET', '/api/sync', { token });
  assert.equal(sync.body.ciphers.length, 1);
  assert.equal(sync.body.ciphers[0].data, blob);
});

test('un type d’élément hors bornes est refusé', async () => {
  const res = await call('POST', '/api/ciphers', {
    token,
    body: { type: 9, data: enc('x') },
  });
  assert.equal(res.status, 400);
  assert.match(res.body.error, /type doit valoir/);
});

test('un élément non chiffré est refusé', async () => {
  const res = await call('POST', '/api/ciphers', {
    token,
    body: { type: 1, data: JSON.stringify({ site: 'github', password: 'hunter2' }) },
  });
  assert.equal(res.status, 400);
});

test('corbeille puis restauration', async () => {
  const sync = await call('GET', '/api/sync', { token });
  const id = sync.body.ciphers[0].id;

  assert.equal((await call('DELETE', `/api/ciphers/${id}`, { token })).status, 200);
  let after = await call('GET', '/api/sync', { token });
  assert.ok(after.body.ciphers[0].deletedAt, 'l’élément doit être marqué supprimé');

  // Un élément à la corbeille n'est plus modifiable.
  const edit = await call('PUT', `/api/ciphers/${id}`, {
    token,
    body: { type: 1, data: enc('modifie') },
  });
  assert.equal(edit.status, 404);

  assert.equal((await call('PUT', `/api/ciphers/${id}/restore`, { token })).status, 200);
  after = await call('GET', '/api/sync', { token });
  assert.equal(after.body.ciphers[0].deletedAt, null);
});

test('supprimer un dossier conserve ses éléments', async () => {
  const folder = await call('POST', '/api/folders', {
    token,
    body: { name: enc('Banque') },
  });
  assert.equal(folder.status, 201);
  const folderId = folder.body.id;

  const cipher = await call('POST', '/api/ciphers', {
    token,
    body: { type: 1, data: enc('dans-le-dossier'), folderId },
  });
  assert.equal(cipher.body.folderId, folderId);

  assert.equal((await call('DELETE', `/api/folders/${folderId}`, { token })).status, 200);

  const sync = await call('GET', '/api/sync', { token });
  assert.equal(sync.body.folders.length, 0);
  const orphan = sync.body.ciphers.find((c) => c.id === cipher.body.id);
  assert.ok(orphan, 'l’élément doit survivre à la suppression de son dossier');
  assert.equal(orphan.folderId, null, 'et retomber sans dossier');
});

test('import en lot dans une seule transaction', async () => {
  const items = Array.from({ length: 25 }, (_, i) => ({
    type: 1,
    data: enc(`importe-${i}`),
  }));
  const res = await call('POST', '/api/ciphers/import', { token, body: { items } });
  assert.equal(res.status, 201);
  assert.equal(res.body.imported, 25);
});

test('un lot dont un élément est invalide n’insère rien', async () => {
  const before = (await call('GET', '/api/sync', { token })).body.ciphers.length;
  const res = await call('POST', '/api/ciphers/import', {
    token,
    body: {
      items: [
        { type: 1, data: enc('valide') },
        { type: 1, data: 'en-clair' },
      ],
    },
  });
  assert.equal(res.status, 400);
  const after = (await call('GET', '/api/sync', { token })).body.ciphers.length;
  assert.equal(after, before, 'aucun élément du lot ne doit avoir été inséré');
});

test('un mot de passe maître erroné ne connecte pas', async () => {
  const res = await call('POST', '/api/auth/login', {
    body: { email: EMAIL, masterPasswordHash: BAD },
  });
  assert.equal(res.status, 401);
});

test('le message d’erreur ne révèle pas si le compte existe', async () => {
  const inconnu = await call('POST', '/api/auth/login', {
    body: { email: 'personne@example.test', masterPasswordHash: BAD },
  });
  const connu = await call('POST', '/api/auth/login', {
    body: { email: EMAIL, masterPasswordHash: BAD },
  });
  assert.equal(inconnu.status, connu.status);
  assert.equal(inconnu.body.error, connu.body.error);
});

test('le bon mot de passe maître ouvre une session', async () => {
  const res = await call('POST', '/api/auth/login', {
    body: { email: EMAIL, masterPasswordHash: GOOD, deviceName: 'second-appareil' },
  });
  assert.equal(res.status, 200);
  assert.ok(res.body.token);
  assert.equal(res.body.profile.protectedKey.startsWith('1.'), true);
});

test('les sessions sont listées par appareil', async () => {
  const res = await call('GET', '/api/auth/sessions', { token });
  assert.equal(res.status, 200);
  assert.ok(res.body.length >= 2);
  assert.ok(res.body.some((s) => s.device_name === 'test-suite'));
});

test('le limiteur bloque le bourrage de mots de passe', async () => {
  const email = 'cible@example.test';
  let last;
  for (let i = 0; i < 7; i++) {
    last = await call('POST', '/api/auth/login', {
      body: { email, masterPasswordHash: BAD },
    });
  }
  assert.equal(last.status, 429, 'après 5 tentatives la fenêtre doit se fermer');
  assert.ok(last.body.retryAfterSeconds > 0);
});

test('changer le mot de passe maître révoque toutes les sessions', async () => {
  const NEW = clientHash('nouveau-mot-de-passe');
  const res = await call('POST', '/api/accounts/password', {
    token,
    body: {
      masterPasswordHash: GOOD,
      newMasterPasswordHash: NEW,
      newProtectedKey: enc('cle-reenveloppee'),
    },
  });
  assert.equal(res.status, 200);

  // L'ancien jeton ne doit plus rien ouvrir.
  assert.equal((await call('GET', '/api/sync', { token })).status, 401);

  // L'ancien mot de passe non plus.
  assert.equal(
    (await call('POST', '/api/auth/login', {
      body: { email: EMAIL, masterPasswordHash: GOOD },
    })).status,
    401
  );

  // Le nouveau, si.
  const relog = await call('POST', '/api/auth/login', {
    body: { email: EMAIL, masterPasswordHash: NEW },
  });
  assert.equal(relog.status, 200);
  token = relog.body.token;
});

test('le coffre a survécu au changement de mot de passe', async () => {
  // Le changement réenveloppe la clé, il ne rechiffre pas les éléments.
  const sync = await call('GET', '/api/sync', { token });
  assert.ok(sync.body.ciphers.length > 20);
});

test('la déconnexion invalide le jeton', async () => {
  assert.equal((await call('POST', '/api/auth/logout', { token })).status, 200);
  assert.equal((await call('GET', '/api/sync', { token })).status, 401);
});
