const express = require('express');
const cors = require('cors');
const crypto = require('crypto');

const { VaultStore } = require('./db/database');
const hash = require('./crypto/password_hash');
const { HttpError } = require('./validate');
const { requireAuth } = require('./middleware/auth');
const { accountsRouter } = require('./routes/accounts');
const { authRouter } = require('./routes/auth');
const { vaultRouter } = require('./routes/vault');

// Construit l'application sans l'écouter, pour que les tests puissent la piloter
// sur une base temporaire.
function createApp(config, store = new VaultStore(config.dbPath)) {
  const app = express();

  // Derrière Nginx, req.ip doit refléter le client réel et pas le proxy, sinon
  // le limiteur de débit voit une seule adresse pour tout le monde.
  app.set('trust proxy', Number(process.env.PASSVAULT_TRUST_PROXY || 0));
  app.disable('x-powered-by');

  app.use(
    cors({
      origin: config.corsOrigins,
      methods: ['GET', 'POST', 'PUT', 'DELETE'],
      allowedHeaders: ['Content-Type', 'Authorization'],
    })
  );
  app.use(express.json({ limit: config.maxBodyBytes }));

  // Un coffre ne doit jamais être mis en cache par un intermédiaire.
  app.use((req, res, next) => {
    res.set('Cache-Control', 'no-store');
    next();
  });

  // Ouvre une session et renvoie le jeton en clair. C'est la seule fois où le
  // serveur le voit : seul son sha256 est stocké.
  function openSession(user, deviceName) {
    const token = crypto.randomBytes(32).toString('base64url');
    const expiresAt = new Date(
      Date.now() + config.sessionTtlDays * 86400_000
    ).toISOString();
    store.createSession({
      tokenHash: hash.sha256Hex(token),
      userId: user.id,
      deviceName,
      expiresAt,
    });
    return { token, expiresAt };
  }

  const auth = requireAuth(store, config.sessionTtlDays);

  app.get('/api/status', (req, res) => {
    res.json({
      service: 'passvault',
      apiVersion: 2,
      zeroKnowledge: true,
      // Permet à l'app de savoir si elle doit proposer « créer un coffre ».
      acceptsRegistration:
        config.registration.mode === 'open' ||
        (config.registration.mode === 'first-only' && store.countUsers() === 0),
      defaultKdf: config.defaultKdf,
    });
  });

  app.use(
    '/api/accounts',
    accountsRouter({ store, config, openSession, requireAuth: auth })
  );
  app.use('/api/auth', authRouter({ store, config, openSession, requireAuth: auth }));
  app.use(
    '/api',
    vaultRouter({ store, requireAuth: auth, maxImportItems: config.maxImportItems })
  );

  app.use((req, res) => {
    res.status(404).json({ error: 'Route inconnue' });
  });

  // Les HttpError de validation portent un message utilisable ; tout le reste
  // devient un 500 muet, pour ne pas transformer une trace en fuite.
  app.use((err, req, res, _next) => {
    if (err instanceof HttpError) {
      return res.status(err.status).json({ error: err.message, details: err.details });
    }
    if (err?.type === 'entity.too.large') {
      return res.status(413).json({ error: 'Corps de requête trop volumineux' });
    }
    if (err instanceof SyntaxError && 'body' in err) {
      return res.status(400).json({ error: 'JSON invalide' });
    }
    console.error('[erreur non gérée]', err);
    res.status(500).json({ error: 'Erreur interne' });
  });

  return { app, store };
}

module.exports = { createApp };
