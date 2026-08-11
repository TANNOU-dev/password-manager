-- Schéma zero-knowledge. Tout ce qui est nommé « chiffré côté client » est opaque
-- au serveur : il le stocke et le rend tel quel, sans jamais pouvoir le lire.

CREATE TABLE IF NOT EXISTS meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS users (
  id    TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,

  -- Vérificateur d'authentification. Le client envoie masterPasswordHash, dérivé
  -- de la clé maître ; le serveur en stocke un scrypt salé. Il ne peut donc
  -- reconstruire ni la clé maître ni le mot de passe.
  auth_hash TEXT NOT NULL,
  auth_salt TEXT NOT NULL,

  -- Paramètres que le client doit rejouer pour redériver la clé maître.
  -- Servis avant authentification, donc publics par construction.
  kdf_type        TEXT    NOT NULL DEFAULT 'argon2id',
  kdf_iterations  INTEGER NOT NULL,
  kdf_memory      INTEGER,
  kdf_parallelism INTEGER,
  kdf_salt        TEXT    NOT NULL,

  -- Clé symétrique du coffre, chiffrée par la clé dérivée du mot de passe maître.
  -- C'est la pièce qui rend le changement de mot de passe possible sans
  -- re-chiffrer tout le coffre. Chiffré côté client.
  protected_key TEXT NOT NULL,

  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS sessions (
  -- On indexe sur sha256(token), jamais sur le token : une fuite de la base ne
  -- livre aucune session réutilisable.
  token_hash   TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_name  TEXT,
  created_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  last_used_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  expires_at   TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_expiry ON sessions(expires_at);

CREATE TABLE IF NOT EXISTS folders (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name          TEXT NOT NULL, -- chiffré côté client
  revision_date TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
CREATE INDEX IF NOT EXISTS idx_folders_user ON folders(user_id);

CREATE TABLE IF NOT EXISTS ciphers (
  id      TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- Ces colonnes restent en clair pour que le serveur puisse filtrer et
  -- synchroniser. Elles ne révèlent rien du contenu : un type, un rattachement,
  -- deux drapeaux. Tout le reste vit dans `data`.
  type      INTEGER NOT NULL, -- 1 login, 2 note, 3 carte, 4 identité
  folder_id TEXT REFERENCES folders(id) ON DELETE SET NULL,
  favorite  INTEGER NOT NULL DEFAULT 0,
  reprompt  INTEGER NOT NULL DEFAULT 0, -- redemander le mdp maître à l'ouverture

  -- Nom, identifiant, mot de passe, URIs, TOTP, notes, champs personnalisés et
  -- historique : un seul blob chiffré. Un blob unique fuit moins de métadonnées
  -- qu'un chiffrement champ par champ (aucune longueur individuelle observable).
  data TEXT NOT NULL,

  created_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  revision_date TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at    TEXT -- non nul = dans la corbeille
);
CREATE INDEX IF NOT EXISTS idx_ciphers_user ON ciphers(user_id);
CREATE INDEX IF NOT EXISTS idx_ciphers_folder ON ciphers(folder_id);
