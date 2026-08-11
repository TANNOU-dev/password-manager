// Le serveur ne peut pas vérifier le contenu d'un blob chiffré, mais il peut
// refuser ce qui n'a manifestement pas la bonne forme. Ça évite de stocker des
// données que le client ne saura jamais relire.

const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;

// Format sur le fil : "1." + base64(nonce‖chiffré‖mac), soit 12 + n + 16 octets.
// Le préfixe de version permettra de changer de suite cryptographique sans
// ambiguïté sur les anciens enregistrements.
const ENC_PREFIX = '1.';
const MIN_ENC_PAYLOAD_BYTES = 12 + 16;

class HttpError extends Error {
  constructor(status, message, details) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

const fail = (message, details) => {
  throw new HttpError(400, message, details);
};

function encString(value, field) {
  if (typeof value !== 'string' || !value.startsWith(ENC_PREFIX)) {
    fail(`${field} doit être une chaîne chiffrée préfixée par "${ENC_PREFIX}"`);
  }
  const payload = value.slice(ENC_PREFIX.length);
  if (!BASE64.test(payload)) {
    fail(`${field} n'est pas du base64 valide`);
  }
  // 4 caractères base64 pour 3 octets.
  if ((payload.length * 3) / 4 < MIN_ENC_PAYLOAD_BYTES) {
    fail(`${field} est trop court pour contenir un nonce et un MAC`);
  }
  return value;
}

function email(value) {
  if (typeof value !== 'string') fail('email manquant');
  const trimmed = value.trim().toLowerCase();
  // Volontairement permissif : l'e-mail sert d'identifiant de compte et de sel,
  // pas de canal de contact. On refuse seulement ce qui casserait l'unicité.
  if (trimmed.length < 3 || trimmed.length > 254 || /\s/.test(trimmed)) {
    fail('email invalide');
  }
  return trimmed;
}

function hexOfBytes(value, bytes, field) {
  if (typeof value !== 'string' || value.length !== bytes * 2 || !/^[0-9a-f]+$/i.test(value)) {
    fail(`${field} doit être ${bytes} octets en hexadécimal`);
  }
  return value.toLowerCase();
}

function cipherType(value) {
  const n = Number(value);
  if (!Number.isInteger(n) || n < 1 || n > 4) {
    fail('type doit valoir 1 (identifiant), 2 (note), 3 (carte) ou 4 (identité)');
  }
  return n;
}

function kdfParams(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'object') fail('kdf invalide');
  const type = value.type;
  if (type !== 'argon2id' && type !== 'pbkdf2') {
    fail('kdf.type doit être "argon2id" ou "pbkdf2"');
  }
  const iterations = Number(value.iterations);
  if (!Number.isInteger(iterations) || iterations < 1) fail('kdf.iterations invalide');

  if (type === 'pbkdf2') {
    // En dessous, la dérivation ne coûte plus rien à un attaquant.
    if (iterations < 100000) fail('kdf.iterations doit valoir au moins 100000 pour pbkdf2');
    return { type, iterations, memory: null, parallelism: null };
  }

  const memory = Number(value.memory);
  const parallelism = Number(value.parallelism);
  if (!Number.isInteger(memory) || memory < 8192) {
    fail('kdf.memory doit valoir au moins 8192 blocs de 1 kio');
  }
  if (!Number.isInteger(parallelism) || parallelism < 1 || parallelism > 16) {
    fail('kdf.parallelism doit être entre 1 et 16');
  }
  return { type, iterations, memory, parallelism };
}

function boolFlag(value) {
  return value === true || value === 1 || value === '1' || value === 'true';
}

function optionalUuid(value, field) {
  if (value === undefined || value === null || value === '') return null;
  if (
    typeof value !== 'string' ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)
  ) {
    fail(`${field} n'est pas un identifiant valide`);
  }
  return value.toLowerCase();
}

function deviceName(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') return null;
  return value.trim().slice(0, 64) || null;
}

module.exports = {
  HttpError,
  encString,
  email,
  hexOfBytes,
  cipherType,
  kdfParams,
  boolFlag,
  optionalUuid,
  deviceName,
};
