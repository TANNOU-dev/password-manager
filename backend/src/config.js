const path = require('path');

function intEnv(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  const n = Number.parseInt(raw, 10);
  if (!Number.isFinite(n)) throw new Error(`${name} doit être un entier, reçu "${raw}"`);
  return n;
}

// Les origines autorisées sont explicites : une app mobile n'envoie pas d'Origin,
// donc la liste ne sert qu'aux builds web.
function listEnv(name, fallback) {
  const raw = process.env[name];
  if (!raw) return fallback;
  return raw.split(',').map((s) => s.trim()).filter(Boolean);
}

// Taille maximale du corps des requêtes.
//
// Validée ici plutôt que confiée telle quelle à express.json. Une valeur mal
// écrite — « 512k » au lieu de « 512kb » — n'est pas rejetée par la couche de
// dessous : elle **désactive silencieusement** le contrôle de taille, et le
// serveur accepte alors des corps sans limite. C'est le sujet de l'avis
// GHSA-v422-hmwv-36x6 sur body-parser.
//
// Refuser de démarrer est le bon comportement : un serveur qui tourne sans la
// protection qu'on croit avoir configurée est pire qu'un serveur qui ne
// démarre pas.
function byteSizeEnv(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  if (!/^\d+(\.\d+)?\s*(b|kb|mb|gb)$/i.test(raw.trim())) {
    throw new Error(
      `${name} doit être une taille comme "512kb" ou "2mb", reçu "${raw}". ` +
        'Une valeur non reconnue désactiverait la limite sans prévenir.',
    );
  }
  return raw.trim();
}

module.exports = {
  port: intEnv('PORT', 3000),
  host: process.env.HOST || '0.0.0.0',
  dbPath: process.env.PASSVAULT_DB || path.join(__dirname, '..', 'vault.db'),
  corsOrigins: listEnv('PASSVAULT_CORS_ORIGINS', ['http://localhost:8080']),

  // Durée de vie d'une session. Glissante : prolongée à chaque requête authentifiée.
  sessionTtlDays: intEnv('PASSVAULT_SESSION_TTL_DAYS', 30),

  // Paramètres KDF proposés aux nouveaux coffres. Le client peut en imposer
  // d'autres à l'inscription ; le serveur les stocke sans les interpréter.
  defaultKdf: {
    type: 'argon2id',
    iterations: intEnv('PASSVAULT_KDF_ITERATIONS', 3),
    memory: intEnv('PASSVAULT_KDF_MEMORY', 65536), // blocs de 1 kio -> 64 MiB
    parallelism: intEnv('PASSVAULT_KDF_PARALLELISM', 4),
  },

  // Par défaut seul le premier coffre peut être créé : un serveur personnel
  // exposé sur Internet ne doit pas accepter des inscriptions inconnues.
  // 'open' pour ouvrir, 'closed' pour fermer même le premier.
  registration: {
    mode: process.env.PASSVAULT_REGISTRATION || 'first-only',
    token: process.env.PASSVAULT_REGISTRATION_TOKEN || null,
  },

  maxImportItems: intEnv('PASSVAULT_MAX_IMPORT_ITEMS', 5000),

  loginRateLimit: {
    windowMs: intEnv('PASSVAULT_LOGIN_WINDOW_MS', 15 * 60 * 1000),
    maxAttempts: intEnv('PASSVAULT_LOGIN_MAX_ATTEMPTS', 10),
  },

  // Taille maximale d'un corps de requête. Un blob chiffré d'élément reste petit ;
  // cette borne évite qu'un client épuise la mémoire du serveur.
  maxBodyBytes: byteSizeEnv('PASSVAULT_MAX_BODY', '512kb'),
};
