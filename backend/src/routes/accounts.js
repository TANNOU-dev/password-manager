const express = require('express');
const hash = require('../crypto/password_hash');
const v = require('../validate');
const present = require('../presenters');

function accountsRouter({ store, config, openSession, requireAuth }) {
  const router = express.Router();

  // ── Paramètres de dérivation, servis avant authentification ──
  // Le client en a besoin pour recalculer la clé maître. Le sel étant dérivé de
  // l'e-mail par kdfSaltFor, la réponse pour un compte absent est indiscernable
  // de celle d'un compte présent : pas d'énumération possible. Et le client
  // obtient le bon sel dès l'inscription, sans aller-retour supplémentaire.
  router.post('/prelogin', (req, res) => {
    const email = v.email(req.body?.email);
    const user = store.findUserByEmail(email);

    if (!user) {
      return res.json({
        kdf: { ...config.defaultKdf },
        kdfSalt: hash.kdfSaltFor(store.serverSecret, email),
      });
    }

    res.json({ kdf: present.kdfOf(user), kdfSalt: user.kdf_salt });
  });

  // ── Création d'un coffre ──
  router.post('/register', (req, res) => {
    const mode = config.registration.mode;
    const existing = store.countUsers();

    if (mode === 'closed' || (mode === 'first-only' && existing > 0)) {
      return res.status(403).json({ error: 'Les inscriptions sont fermées sur ce serveur' });
    }
    if (config.registration.token) {
      const provided = req.body?.registrationToken;
      if (
        typeof provided !== 'string' ||
        provided.length !== config.registration.token.length ||
        !hash.constantTimeEquals(provided, config.registration.token)
      ) {
        return res.status(403).json({ error: 'Jeton d’inscription invalide' });
      }
    }

    const email = v.email(req.body?.email);
    const masterPasswordHash = req.body?.masterPasswordHash;
    if (!hash.isWellFormedClientHash(masterPasswordHash)) {
      return res.status(400).json({ error: 'masterPasswordHash mal formé' });
    }
    const protectedKey = v.encString(req.body?.protectedKey, 'protectedKey');
    const kdf = v.kdfParams(req.body?.kdf) ?? { ...config.defaultKdf };
    // Même sel que celui déjà servi par /prelogin pour cet e-mail : le client a
    // donc dérivé sa clé contre la bonne valeur avant même d'appeler /register.
    const kdfSalt = hash.kdfSaltFor(store.serverSecret, email);

    if (store.findUserByEmail(email)) {
      return res.status(409).json({ error: 'Un coffre existe déjà pour cet e-mail' });
    }

    const { authHash, authSalt } = hash.hashClientHash(masterPasswordHash);
    const user = store.createUser({
      email,
      authHash,
      authSalt,
      kdf,
      kdfSalt,
      protectedKey,
    });

    const session = openSession(user, v.deviceName(req.body?.deviceName));
    res.status(201).json({ ...session, profile: present.profile(user) });
  });

  // ── Profil du coffre ouvert ──
  router.get('/profile', requireAuth, (req, res) => {
    res.json(present.profile(req.user));
  });

  // ── Changement de mot de passe maître ──
  // Le client redérive une clé à partir du nouveau mot de passe et réenveloppe
  // la *même* clé symétrique de coffre. Aucun élément n'est rechiffré, donc
  // l'opération est instantanée quelle que soit la taille du coffre.
  router.post('/password', requireAuth, (req, res) => {
    const current = req.body?.masterPasswordHash;
    const next = req.body?.newMasterPasswordHash;
    if (!hash.isWellFormedClientHash(current) || !hash.isWellFormedClientHash(next)) {
      return res.status(400).json({ error: 'masterPasswordHash mal formé' });
    }
    if (!hash.verifyClientHash(current, req.user.auth_salt, req.user.auth_hash)) {
      return res.status(401).json({ error: 'Mot de passe maître actuel incorrect' });
    }

    const newProtectedKey = v.encString(req.body?.newProtectedKey, 'newProtectedKey');
    const { authHash, authSalt } = hash.hashClientHash(next);
    // rotateMasterPassword révoque toutes les sessions, y compris celle-ci :
    // l'ancien mot de passe ne doit plus ouvrir quoi que ce soit.
    store.rotateMasterPassword(req.user.id, {
      authHash,
      authSalt,
      protectedKey: newProtectedKey,
    });

    res.json({ success: true, sessionsRevoked: true });
  });

  // ── Suppression définitive du coffre ──
  router.delete('/', requireAuth, (req, res) => {
    const current = req.body?.masterPasswordHash;
    if (!hash.isWellFormedClientHash(current)) {
      return res.status(400).json({ error: 'masterPasswordHash mal formé' });
    }
    if (!hash.verifyClientHash(current, req.user.auth_salt, req.user.auth_hash)) {
      return res.status(401).json({ error: 'Mot de passe maître incorrect' });
    }
    // ON DELETE CASCADE emporte sessions, dossiers et éléments.
    store.deleteUser(req.user.id);
    res.json({ success: true });
  });

  return router;
}

module.exports = { accountsRouter };
