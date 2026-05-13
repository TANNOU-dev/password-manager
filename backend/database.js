const Database = require('better-sqlite3');
const CryptoJS = require('crypto-js');
const crypto = require('crypto');
const path = require('path');

class PasswordDB {
  constructor() {
    this.db = new Database(path.join(__dirname, 'passwords.db'));
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS master (
        id INTEGER PRIMARY KEY,
        hash TEXT NOT NULL,
        salt TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS tokens (
        token TEXT PRIMARY KEY,
        masterKey TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS passwords (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        encrypted_data TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );
    `);
  }

  // ==================== MASTER PASSWORD ====================

  setupMaster(password) {
    const salt = crypto.randomBytes(16).toString('hex');
    const hash = CryptoJS.PBKDF2(password, salt, { keySize: 256 / 32, iterations: 10000 }).toString();
    this.db.prepare('DELETE FROM master').run();
    this.db.prepare('INSERT INTO master (id, hash, salt) VALUES (1, ?, ?)').run(hash, salt);
    return hash;
  }

  verifyMaster(password) {
    const row = this.db.prepare('SELECT * FROM master WHERE id = 1').get();
    if (!row) return false;
    const hash = CryptoJS.PBKDF2(password, row.salt, { keySize: 256 / 32, iterations: 10000 }).toString();
    return hash === row.hash;
  }

  // ==================== TOKENS ====================

  saveToken(token) {
    this.db.prepare('DELETE FROM tokens').run();
    const masterRow = this.db.prepare('SELECT hash FROM master WHERE id = 1').get();
    this.db.prepare('INSERT INTO tokens (token, masterKey) VALUES (?, ?)').run(token, masterRow.hash);
  }

  getKey(token) {
    const row = this.db.prepare('SELECT masterKey FROM tokens WHERE token = ?').get(token);
    return row ? row.masterKey : null;
  }

  // ==================== PASSWORDS ====================

  addPassword(masterKey, data) {
    const plain = JSON.stringify(data);
    const encrypted = CryptoJS.AES.encrypt(plain, masterKey).toString();
    const result = this.db.prepare('INSERT INTO passwords (encrypted_data) VALUES (?)').run(encrypted);
    return result.lastInsertRowid;
  }

  getPasswords(masterKey) {
    const rows = this.db.prepare('SELECT * FROM passwords ORDER BY created_at DESC').all();
    return rows.map(row => {
      try {
        const bytes = CryptoJS.AES.decrypt(row.encrypted_data, masterKey);
        const decrypted = bytes.toString(CryptoJS.enc.Utf8);
        const data = JSON.parse(decrypted);
        return { id: row.id, ...data, created_at: row.created_at };
      } catch {
        return { id: row.id, error: 'Impossible de déchiffrer' };
      }
    });
  }

  deletePassword(id) {
    this.db.prepare('DELETE FROM passwords WHERE id = ?').run(id);
  }

  updatePassword(masterKey, id, data) {
    const plain = JSON.stringify(data);
    const encrypted = CryptoJS.AES.encrypt(plain, masterKey).toString();
    const result = this.db.prepare('UPDATE passwords SET encrypted_data = ? WHERE id = ?').run(encrypted, id);
    return result.changes > 0;
  }

  // ==================== EXPORT / IMPORT ====================

  getAllDecrypted(masterKey) {
    const rows = this.db.prepare('SELECT * FROM passwords ORDER BY created_at DESC').all();
    const result = [];
    for (const row of rows) {
      try {
        const bytes = CryptoJS.AES.decrypt(row.encrypted_data, masterKey);
        const decrypted = bytes.toString(CryptoJS.enc.Utf8);
        const data = JSON.parse(decrypted);
        result.push({ id: row.id, ...data, created_at: row.created_at });
      } catch {
        // skip corrupted entries
      }
    }
    return result;
  }

  importPasswords(masterKey, entries) {
    let count = 0;
    const insert = this.db.prepare('INSERT INTO passwords (encrypted_data) VALUES (?)');
    const insertMany = this.db.transaction((items) => {
      for (const item of items) {
        const { site, email, password, note } = item;
        const plain = JSON.stringify({ site, email, password, note: note || '' });
        const encrypted = CryptoJS.AES.encrypt(plain, masterKey).toString();
        insert.run(encrypted);
        count++;
      }
    });
    insertMany(entries);
    return count;
  }
}

module.exports = PasswordDB;
