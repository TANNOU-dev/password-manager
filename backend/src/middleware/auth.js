const { sha256Hex } = require('../crypto/password_hash');

function bearerToken(req) {
  const header = req.get('authorization');
  if (!header) return null;
  const match = /^Bearer\s+(\S+)$/i.exec(header.trim());
  return match ? match[1] : null;
}

// Sessions glissantes : chaque requête authentifiée repousse l'expiration. Un
// coffre utilisé quotidiennement ne redemande jamais le mot de passe maître au
// serveur, un coffre abandonné se ferme tout seul.
function requireAuth(store, sessionTtlDays) {
  return (req, res, next) => {
    const token = bearerToken(req);
    if (!token) {
      return res.status(401).json({ error: 'Jeton de session absent' });
    }

    const tokenHash = sha256Hex(token);
    const session = store.findSession(tokenHash);
    if (!session) {
      return res.status(401).json({ error: 'Session inconnue' });
    }

    if (new Date(session.expires_at).getTime() <= Date.now()) {
      store.deleteSession(tokenHash);
      return res.status(401).json({ error: 'Session expirée' });
    }

    const user = store.findUserById(session.user_id);
    if (!user) {
      store.deleteSession(tokenHash);
      return res.status(401).json({ error: 'Compte introuvable' });
    }

    const renewed = new Date(Date.now() + sessionTtlDays * 86400_000).toISOString();
    store.touchSession(tokenHash, renewed);

    req.user = user;
    req.sessionTokenHash = tokenHash;
    next();
  };
}

module.exports = { requireAuth, bearerToken };
