const Database = require('better-sqlite3');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const now = () => new Date().toISOString();

class VaultStore {
  constructor(dbPath) {
    this.db = new Database(dbPath);
    this.db.pragma('journal_mode = WAL');
    this.db.pragma('foreign_keys = ON');
    this.db.exec(fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8'));
    this.serverSecret = this.#ensureServerSecret();
  }

  #ensureServerSecret() {
    const row = this.db.prepare('SELECT value FROM meta WHERE key = ?').get('server_secret');
    if (row) return row.value;
    const secret = crypto.randomBytes(32).toString('hex');
    this.db.prepare('INSERT INTO meta (key, value) VALUES (?, ?)').run('server_secret', secret);
    return secret;
  }

  // ==================== UTILISATEURS ====================

  findUserByEmail(email) {
    return this.db
      .prepare('SELECT * FROM users WHERE email = ?')
      .get(email.toLowerCase());
  }

  findUserById(id) {
    return this.db.prepare('SELECT * FROM users WHERE id = ?').get(id);
  }

  countUsers() {
    return this.db.prepare('SELECT COUNT(*) AS n FROM users').get().n;
  }

  createUser({ email, authHash, authSalt, kdf, kdfSalt, protectedKey }) {
    const id = crypto.randomUUID();
    this.db
      .prepare(
        `INSERT INTO users (
           id, email, auth_hash, auth_salt,
           kdf_type, kdf_iterations, kdf_memory, kdf_parallelism, kdf_salt,
           protected_key
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .run(
        id,
        email.toLowerCase(),
        authHash,
        authSalt,
        kdf.type,
        kdf.iterations,
        kdf.memory ?? null,
        kdf.parallelism ?? null,
        kdfSalt,
        protectedKey
      );
    return this.findUserById(id);
  }

  // Changement de mot de passe maître : nouveau vérificateur et nouvelle clé
  // symétrique réenveloppée. Le coffre lui-même n'est pas retouché, et toutes les
  // sessions tombent puisque l'ancien mot de passe ne doit plus ouvrir quoi que
  // ce soit.
  rotateMasterPassword(userId, { authHash, authSalt, protectedKey }) {
    const tx = this.db.transaction(() => {
      this.db
        .prepare(
          `UPDATE users
              SET auth_hash = ?, auth_salt = ?, protected_key = ?, updated_at = ?
            WHERE id = ?`
        )
        .run(authHash, authSalt, protectedKey, now(), userId);
      this.db.prepare('DELETE FROM sessions WHERE user_id = ?').run(userId);
    });
    tx();
  }

  deleteUser(userId) {
    return this.db.prepare('DELETE FROM users WHERE id = ?').run(userId).changes > 0;
  }

  // ==================== SESSIONS ====================

  createSession({ tokenHash, userId, deviceName, expiresAt }) {
    this.db
      .prepare(
        `INSERT INTO sessions (token_hash, user_id, device_name, expires_at)
         VALUES (?, ?, ?, ?)`
      )
      .run(tokenHash, userId, deviceName || null, expiresAt);
  }

  findSession(tokenHash) {
    return this.db
      .prepare('SELECT * FROM sessions WHERE token_hash = ?')
      .get(tokenHash);
  }

  touchSession(tokenHash, expiresAt) {
    this.db
      .prepare('UPDATE sessions SET last_used_at = ?, expires_at = ? WHERE token_hash = ?')
      .run(now(), expiresAt, tokenHash);
  }

  deleteSession(tokenHash) {
    this.db.prepare('DELETE FROM sessions WHERE token_hash = ?').run(tokenHash);
  }

  deleteOtherSessions(userId, keepTokenHash) {
    return this.db
      .prepare('DELETE FROM sessions WHERE user_id = ? AND token_hash != ?')
      .run(userId, keepTokenHash).changes;
  }

  deleteExpiredSessions() {
    return this.db.prepare('DELETE FROM sessions WHERE expires_at < ?').run(now()).changes;
  }

  listSessions(userId) {
    return this.db
      .prepare(
        `SELECT device_name, created_at, last_used_at, expires_at
           FROM sessions WHERE user_id = ? ORDER BY last_used_at DESC`
      )
      .all(userId);
  }

  // ==================== DOSSIERS ====================

  listFolders(userId) {
    return this.db
      .prepare('SELECT * FROM folders WHERE user_id = ? ORDER BY revision_date DESC')
      .all(userId);
  }

  createFolder(userId, encryptedName) {
    const id = crypto.randomUUID();
    this.db
      .prepare('INSERT INTO folders (id, user_id, name) VALUES (?, ?, ?)')
      .run(id, userId, encryptedName);
    return this.db.prepare('SELECT * FROM folders WHERE id = ?').get(id);
  }

  updateFolder(userId, id, encryptedName) {
    const changed = this.db
      .prepare('UPDATE folders SET name = ?, revision_date = ? WHERE id = ? AND user_id = ?')
      .run(encryptedName, now(), id, userId).changes;
    if (!changed) return null;
    return this.db.prepare('SELECT * FROM folders WHERE id = ?').get(id);
  }

  // Les éléments du dossier ne sont pas supprimés : ON DELETE SET NULL les
  // renvoie vers « sans dossier ».
  deleteFolder(userId, id) {
    return this.db
      .prepare('DELETE FROM folders WHERE id = ? AND user_id = ?')
      .run(id, userId).changes > 0;
  }

  // ==================== ÉLÉMENTS ====================

  listCiphers(userId) {
    return this.db
      .prepare('SELECT * FROM ciphers WHERE user_id = ? ORDER BY revision_date DESC')
      .all(userId);
  }

  findCipher(userId, id) {
    return this.db
      .prepare('SELECT * FROM ciphers WHERE id = ? AND user_id = ?')
      .get(id, userId);
  }

  createCipher(userId, { type, folderId, favorite, reprompt, data }) {
    const id = crypto.randomUUID();
    this.db
      .prepare(
        `INSERT INTO ciphers (id, user_id, type, folder_id, favorite, reprompt, data)
         VALUES (?, ?, ?, ?, ?, ?, ?)`
      )
      .run(id, userId, type, folderId || null, favorite ? 1 : 0, reprompt ? 1 : 0, data);
    return this.findCipher(userId, id);
  }

  updateCipher(userId, id, { type, folderId, favorite, reprompt, data }) {
    const changed = this.db
      .prepare(
        `UPDATE ciphers
            SET type = ?, folder_id = ?, favorite = ?, reprompt = ?, data = ?, revision_date = ?
          WHERE id = ? AND user_id = ? AND deleted_at IS NULL`
      )
      .run(
        type,
        folderId || null,
        favorite ? 1 : 0,
        reprompt ? 1 : 0,
        data,
        now(),
        id,
        userId
      ).changes;
    if (!changed) return null;
    return this.findCipher(userId, id);
  }

  trashCipher(userId, id) {
    const stamp = now();
    return this.db
      .prepare(
        `UPDATE ciphers SET deleted_at = ?, revision_date = ?
          WHERE id = ? AND user_id = ? AND deleted_at IS NULL`
      )
      .run(stamp, stamp, id, userId).changes > 0;
  }

  restoreCipher(userId, id) {
    const stamp = now();
    return this.db
      .prepare(
        `UPDATE ciphers SET deleted_at = NULL, revision_date = ?
          WHERE id = ? AND user_id = ? AND deleted_at IS NOT NULL`
      )
      .run(stamp, id, userId).changes > 0;
  }

  purgeCipher(userId, id) {
    return this.db
      .prepare('DELETE FROM ciphers WHERE id = ? AND user_id = ?')
      .run(id, userId).changes > 0;
  }

  emptyTrash(userId) {
    return this.db
      .prepare('DELETE FROM ciphers WHERE user_id = ? AND deleted_at IS NOT NULL')
      .run(userId).changes;
  }

  // Import : une transaction unique, pour qu'un lot n'atterrisse jamais à moitié.
  createCiphersBulk(userId, items) {
    const insert = this.db.prepare(
      `INSERT INTO ciphers (id, user_id, type, folder_id, favorite, reprompt, data)
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    );
    const ids = [];
    const tx = this.db.transaction((rows) => {
      for (const row of rows) {
        const id = crypto.randomUUID();
        insert.run(
          id,
          userId,
          row.type,
          row.folderId || null,
          row.favorite ? 1 : 0,
          row.reprompt ? 1 : 0,
          row.data
        );
        ids.push(id);
      }
    });
    tx(items);
    return ids;
  }

  close() {
    this.db.close();
  }
}

module.exports = { VaultStore, now };
