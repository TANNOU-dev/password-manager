const crypto = require('crypto');

// L'entrée n'est pas un mot de passe humain mais un masterPasswordHash de 256 bits
// déjà passé par Argon2id côté client. Le scrypt du serveur n'est donc pas la
// défense principale : il empêche seulement qu'une fuite de la base livre
// directement le vérificateur. N=16384 (~17 Mio, ~70 ms) suffit et reste sous le
// maxmem par défaut de Node.
const SCRYPT = { N: 16384, r: 8, p: 1, keylen: 64 };

// Longueur attendue du masterPasswordHash : 32 octets en base64.
const CLIENT_HASH_B64_LENGTH = 44;

function randomHex(bytes) {
  return crypto.randomBytes(bytes).toString('hex');
}

function isWellFormedClientHash(value) {
  return (
    typeof value === 'string' &&
    value.length === CLIENT_HASH_B64_LENGTH &&
    /^[A-Za-z0-9+/]+={0,2}$/.test(value)
  );
}

function derive(clientHash, saltHex) {
  return crypto.scryptSync(clientHash, Buffer.from(saltHex, 'hex'), SCRYPT.keylen, {
    N: SCRYPT.N,
    r: SCRYPT.r,
    p: SCRYPT.p,
  });
}

function hashClientHash(clientHash) {
  const salt = randomHex(16);
  return { authHash: derive(clientHash, salt).toString('hex'), authSalt: salt };
}

function verifyClientHash(clientHash, saltHex, expectedHex) {
  const expected = Buffer.from(expectedHex, 'hex');
  const actual = derive(clientHash, saltHex);
  // Longueurs égales par construction, mais on garde le garde-fou : timingSafeEqual
  // lève si elles diffèrent, ce qui produirait un 500 au lieu d'un 401.
  if (actual.length !== expected.length) return false;
  return crypto.timingSafeEqual(actual, expected);
}

// Sel de dérivation d'un compte : HMAC(secret du serveur, e-mail).
//
// Déterministe, donc /prelogin peut le servir avant même que le compte existe —
// le client dérive la bonne clé du premier coup, sans aller-retour. Et comme la
// même fonction sert pour un compte présent et pour un compte absent, les deux
// réponses sont identiques par construction : l'endpoint ne permet pas
// d'énumérer les comptes.
//
// Un sel n'a pas besoin d'être secret, seulement unique par compte. Celui-ci
// l'est, et reste imprévisible sans le secret du serveur.
function kdfSaltFor(serverSecret, email) {
  return crypto
    .createHmac('sha256', Buffer.from(serverSecret, 'hex'))
    .update(email.toLowerCase())
    .digest('hex')
    .slice(0, 32);
}

function sha256Hex(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

// Comparaison de deux chaînes sans fuite par le temps. On passe par sha256 pour
// que des longueurs différentes ne fassent pas sortir tôt de la comparaison.
function constantTimeEquals(a, b) {
  const da = crypto.createHash('sha256').update(String(a)).digest();
  const db = crypto.createHash('sha256').update(String(b)).digest();
  return crypto.timingSafeEqual(da, db);
}

// Vérification factice, exécutée quand le compte demandé n'existe pas, pour que
// le temps de réponse de /login ne révèle pas l'existence d'un coffre.
function burnEquivalentWork(clientHash) {
  derive(typeof clientHash === 'string' ? clientHash : 'x', randomHex(16));
}

module.exports = {
  randomHex,
  isWellFormedClientHash,
  hashClientHash,
  verifyClientHash,
  kdfSaltFor,
  sha256Hex,
  constantTimeEquals,
  burnEquivalentWork,
};
