// Limiteur à fenêtre glissante, en mémoire. Suffisant pour un serveur à
// processus unique ; derrière plusieurs instances il faudrait un magasin partagé.
function rateLimiter({ windowMs, maxAttempts, keyFn }) {
  const hits = new Map();

  // Purge opportuniste : on nettoie en écrivant, pas via un timer, pour ne pas
  // garder le processus éveillé.
  function sweep(cutoff) {
    for (const [key, stamps] of hits) {
      const kept = stamps.filter((t) => t > cutoff);
      if (kept.length === 0) hits.delete(key);
      else hits.set(key, kept);
    }
  }

  return (req, res, next) => {
    const nowMs = Date.now();
    const cutoff = nowMs - windowMs;
    if (hits.size > 1000) sweep(cutoff);

    const key = keyFn(req);
    const stamps = (hits.get(key) || []).filter((t) => t > cutoff);

    if (stamps.length >= maxAttempts) {
      const retryAfter = Math.ceil((stamps[0] + windowMs - nowMs) / 1000);
      res.set('Retry-After', String(retryAfter));
      return res.status(429).json({
        error: 'Trop de tentatives, réessayez plus tard',
        retryAfterSeconds: retryAfter,
      });
    }

    stamps.push(nowMs);
    hits.set(key, stamps);
    next();
  };
}

module.exports = { rateLimiter };
