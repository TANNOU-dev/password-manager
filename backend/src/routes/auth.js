const express = require('express');
const hash = require('../crypto/password_hash');
const v = require('../validate');
const present = require('../presenters');
const { rateLimiter } = require('../middleware/rate_limit');

function authRouter({ store, config, openSession, requireAuth }) {
  const router = express.Router();

  // On limite par couple (IP, e-mail) : un attaquant qui change d'e-mail ne
  // remet pas son quota à zéro, et un utilisateur maladroit ne bloque pas les
  // autres comptes derrière la même IP.
  const loginLimiter = rateLimiter({
    windowMs: config.loginRateLimit.windowMs,
    maxAttempts: config.loginRateLimit.maxAttempts,
    keyFn: (req) => `${req.ip}|${String(req.body?.email || '').toLowerCase()}`,
  });

  router.post('/login', loginLimiter, (req, res) => {
    const email = v.email(req.body?.email);
    const masterPasswordHash = req.body?.masterPasswordHash;
    if (!hash.isWellFormedClientHash(masterPasswordHash)) {
      return res.status(400).json({ error: 'masterPasswordHash mal formé' });
    }

    const user = store.findUserByEmail(email);
    if (!user) {
      // Même coût de calcul que pour un compte réel, même message d'erreur.
      hash.burnEquivalentWork(masterPasswordHash);
      return res.status(401).json({ error: 'E-mail ou mot de passe maître incorrect' });
    }

    if (!hash.verifyClientHash(masterPasswordHash, user.auth_salt, user.auth_hash)) {
      return res.status(401).json({ error: 'E-mail ou mot de passe maître incorrect' });
    }

    const session = openSession(user, v.deviceName(req.body?.deviceName));
    res.json({ ...session, profile: present.profile(user) });
  });

  router.post('/logout', requireAuth, (req, res) => {
    store.deleteSession(req.sessionTokenHash);
    res.json({ success: true });
  });

  router.get('/sessions', requireAuth, (req, res) => {
    res.json(store.listSessions(req.user.id));
  });

  // Déconnecter tous les autres appareils, en gardant celui-ci.
  router.delete('/sessions', requireAuth, (req, res) => {
    const revoked = store.deleteOtherSessions(req.user.id, req.sessionTokenHash);
    res.json({ success: true, revoked });
  });

  return router;
}

module.exports = { authRouter };
