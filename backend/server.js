const express = require('express');
const cors = require('cors');
const PasswordDB = require('./database');
const crypto = require('crypto');

const app = express();
const PORT = 3000;
const db = new PasswordDB();

app.use(cors({
  origin: [
    'http://100.77.208.122:3000',
    'http://localhost:3000',
  ],
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));
app.use(express.json());

// ========================================
// AUTH - Créer un compte maître
// ========================================
app.post('/api/setup', (req, res) => {
  const { masterPassword } = req.body;
  if (!masterPassword || masterPassword.length < 6) {
    return res.status(400).json({ error: 'Mot de passe trop court (min 6)' });
  }
  db.setupMaster(masterPassword);
  res.json({ success: true });
});

app.post('/api/login', (req, res) => {
  const { masterPassword } = req.body;
  if (!masterPassword) return res.status(400).json({ error: 'Mot de passe requis' });
  
  const valid = db.verifyMaster(masterPassword);
  if (!valid) return res.status(401).json({ error: 'Mot de passe incorrect' });
  
  const token = crypto.randomBytes(32).toString('hex');
  db.saveToken(token);
  res.json({ token });
});

// ========================================
// MOTS DE PASSE
// ========================================

// Ajouter un mot de passe
app.post('/api/passwords', (req, res) => {
  const { token, site, email, password, note } = req.body;
  if (!token || !site || !email || !password) {
    return res.status(400).json({ error: 'Champs manquants (token, site, email, password)' });
  }
  
  const masterKey = db.getKey(token);
  if (!masterKey) return res.status(401).json({ error: 'Token invalide' });

  const id = db.addPassword(masterKey, { site, email, password, note });
  res.json({ id, success: true });
});

// Récupérer tous les mots de passe (déchiffrés)
app.get('/api/passwords', (req, res) => {
  const { token } = req.query;
  if (!token) return res.status(400).json({ error: 'Token requis' });

  const masterKey = db.getKey(token);
  if (!masterKey) return res.status(401).json({ error: 'Token invalide' });

  const passwords = db.getPasswords(masterKey);
  res.json(passwords);
});

// Supprimer un mot de passe
app.delete('/api/passwords/:id', (req, res) => {
  const { token } = req.body;
  if (!token) return res.status(400).json({ error: 'Token requis' });

  const masterKey = db.getKey(token);
  if (!masterKey) return res.status(401).json({ error: 'Token invalide' });

  db.deletePassword(req.params.id);
  res.json({ success: true });
});

// Modifier un mot de passe
app.put('/api/passwords/:id', (req, res) => {
  const { token, site, email, password, note } = req.body;
  if (!token || !site || !email || !password) {
    return res.status(400).json({ error: 'Champs manquants (token, site, email, password)' });
  }

  const masterKey = db.getKey(token);
  if (!masterKey) return res.status(401).json({ error: 'Token invalide' });

  const updated = db.updatePassword(masterKey, req.params.id, { site, email, password, note });
  if (!updated) return res.status(404).json({ error: 'Mot de passe introuvable' });

  res.json({ success: true });
});

// ========================================
// EXPORT / IMPORT
// ========================================

// Exporter tous les mots de passe en JSON
app.get('/api/export', (req, res) => {
  const { token } = req.query;
  if (!token) return res.status(400).json({ error: 'Token requis' });

  const masterKey = db.getKey(token);
  if (!masterKey) return res.status(401).json({ error: 'Token invalide' });

  const passwords = db.getAllDecrypted(masterKey);
  res.json(passwords);
});

// Importer des mots de passe depuis JSON
app.post('/api/import', (req, res) => {
  const { token, passwords } = req.body;
  if (!token) return res.status(400).json({ error: 'Token requis' });
  if (!Array.isArray(passwords) || passwords.length === 0) {
    return res.status(400).json({ error: 'Tableau passwords vide ou invalide' });
  }

  const masterKey = db.getKey(token);
  if (!masterKey) return res.status(401).json({ error: 'Token invalide' });

  const count = db.importPasswords(masterKey, passwords);
  res.json({ success: true, imported: count });
});

// ========================================
// EXPORT / IMPORT CSV
// ========================================

// Exporter en CSV
app.get('/api/export/csv', (req, res) => {
  const { token } = req.query;
  if (!token) return res.status(400).json({ error: 'Token requis' });

  const masterKey = db.getKey(token);
  if (!masterKey) return res.status(401).json({ error: 'Token invalide' });

  const passwords = db.getAllDecrypted(masterKey);

  // Construire le CSV
  let csv = 'site,email,password,note\n';
  for (const p of passwords) {
    const site = escapeCSV(p.site || '');
    const email = escapeCSV(p.email || '');
    const password = escapeCSV(p.password || '');
    const note = escapeCSV(p.note || '');
    csv += `${site},${email},${password},${note}\n`;
  }

  res.json({ csv });
});

function escapeCSV(value) {
  const str = String(value);
  if (str.includes(',') || str.includes('"') || str.includes('\n')) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

// ========================================
// IMPORT CSV
// ========================================

app.post('/api/import/csv', (req, res) => {
  const { token, csv } = req.body;
  if (!token) return res.status(400).json({ error: 'Token requis' });
  if (!csv || typeof csv !== 'string' || csv.trim().length === 0) {
    return res.status(400).json({ error: 'CSV vide ou invalide' });
  }

  const masterKey = db.getKey(token);
  if (!masterKey) return res.status(401).json({ error: 'Token invalide' });

  try {
    const lines = csv.trim().split('\n');
    const entries = [];
    let errors = 0;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length === 0) continue;

      // Skip header line if it looks like one
      const firstCol = line.split(',')[0].trim().toLowerCase();
      if (i === 0 && (firstCol === 'site' || firstCol === 'website' || firstCol === 'service')) {
        continue;
      }

      // Parse CSV simple (sans guillemets pour les champs)
      const parts = parseCSVLine(line);
      if (parts.length < 3) {
        errors++;
        continue;
      }

      entries.push({
        site: parts[0].trim(),
        email: parts[1].trim(),
        password: parts[2].trim(),
        note: parts.length > 3 ? parts.slice(3).join(', ').trim() : '',
      });
    }

    if (entries.length === 0) {
      return res.status(400).json({
        error: 'Aucune entrée valide trouvée',
        errors,
      });
    }

    const count = db.importPasswords(masterKey, entries);
    res.json({
      success: true,
      imported: count,
      errors,
      total: entries.length + errors,
    });
  } catch (e) {
    res.status(400).json({ error: 'Erreur de parsing CSV: ' + e.message });
  }
});

// Parse une ligne CSV en gérant les guillemets
function parseCSVLine(line) {
  const result = [];
  let current = '';
  let inQuotes = false;

  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] === '"') {
        current += '"';
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (c === ',' && !inQuotes) {
      result.push(current);
      current = '';
    } else {
      current += c;
    }
  }
  result.push(current);
  return result;
}

// ========================================
// GÉNÉRATEUR DE MOT DE PASSE
// ========================================
app.get('/api/generate', (req, res) => {
  const length = parseInt(req.query.length) || 20;
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+-=[]{}|;:,.<>?';
  let password = '';
  for (let i = 0; i < length; i++) {
    password += chars.charAt(crypto.randomInt(chars.length));
  }
  res.json({ password });
});

// ========================================
// DÉMARRAGE
// ========================================
app.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ Password Manager API lancée sur http://localhost:${PORT}`);
});
