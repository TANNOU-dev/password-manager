const express = require('express');
const v = require('../validate');
const present = require('../presenters');

// Lit le corps commun à la création et à la mise à jour d'un élément. Le contenu
// réel est dans `data`, que le serveur n'ouvre jamais.
function readCipherBody(body) {
  return {
    type: v.cipherType(body?.type),
    folderId: v.optionalUuid(body?.folderId, 'folderId'),
    favorite: v.boolFlag(body?.favorite),
    reprompt: v.boolFlag(body?.reprompt),
    data: v.encString(body?.data, 'data'),
  };
}

function vaultRouter({ store, requireAuth, maxImportItems }) {
  const router = express.Router();
  router.use(requireAuth);

  // ── Synchronisation complète ──
  // Le serveur ne sait pas chercher dans un coffre chiffré : il renvoie tout et
  // le client filtre après déchiffrement. C'est le prix du zero-knowledge, et
  // c'est tenable — quelques milliers d'éléments font quelques centaines de kio.
  router.get('/sync', (req, res) => {
    res.json({
      profile: present.profile(req.user),
      folders: store.listFolders(req.user.id).map(present.folder),
      ciphers: store.listCiphers(req.user.id).map(present.cipher),
    });
  });

  // ── Éléments ──

  router.post('/ciphers', (req, res) => {
    const row = store.createCipher(req.user.id, readCipherBody(req.body));
    res.status(201).json(present.cipher(row));
  });

  router.put('/ciphers/:id', (req, res) => {
    const id = v.optionalUuid(req.params.id, 'id');
    const row = store.updateCipher(req.user.id, id, readCipherBody(req.body));
    if (!row) {
      return res.status(404).json({ error: 'Élément introuvable ou dans la corbeille' });
    }
    res.json(present.cipher(row));
  });

  // Suppression douce : l'élément part à la corbeille et reste récupérable.
  router.delete('/ciphers/:id', (req, res) => {
    const id = v.optionalUuid(req.params.id, 'id');
    if (!store.trashCipher(req.user.id, id)) {
      return res.status(404).json({ error: 'Élément introuvable' });
    }
    res.json({ success: true });
  });

  router.put('/ciphers/:id/restore', (req, res) => {
    const id = v.optionalUuid(req.params.id, 'id');
    if (!store.restoreCipher(req.user.id, id)) {
      return res.status(404).json({ error: 'Élément absent de la corbeille' });
    }
    res.json({ success: true });
  });

  router.delete('/ciphers/:id/permanent', (req, res) => {
    const id = v.optionalUuid(req.params.id, 'id');
    if (!store.purgeCipher(req.user.id, id)) {
      return res.status(404).json({ error: 'Élément introuvable' });
    }
    res.json({ success: true });
  });

  router.delete('/trash', (req, res) => {
    res.json({ success: true, purged: store.emptyTrash(req.user.id) });
  });

  // ── Import en lot ──
  // Les éléments arrivent déjà chiffrés : c'est le client qui a lu le fichier
  // source et l'a rechiffré. Le serveur ne fait qu'insérer.
  router.post('/ciphers/import', (req, res) => {
    const items = req.body?.items;
    if (!Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ error: 'items doit être un tableau non vide' });
    }
    if (items.length > maxImportItems) {
      return res.status(413).json({
        error: `Import limité à ${maxImportItems} éléments par lot`,
      });
    }
    const ids = store.createCiphersBulk(req.user.id, items.map(readCipherBody));
    res.status(201).json({ success: true, imported: ids.length, ids });
  });

  // ── Dossiers ──

  router.post('/folders', (req, res) => {
    const name = v.encString(req.body?.name, 'name');
    res.status(201).json(present.folder(store.createFolder(req.user.id, name)));
  });

  router.put('/folders/:id', (req, res) => {
    const id = v.optionalUuid(req.params.id, 'id');
    const name = v.encString(req.body?.name, 'name');
    const row = store.updateFolder(req.user.id, id, name);
    if (!row) return res.status(404).json({ error: 'Dossier introuvable' });
    res.json(present.folder(row));
  });

  // Les éléments du dossier survivent et retombent dans « sans dossier ».
  router.delete('/folders/:id', (req, res) => {
    const id = v.optionalUuid(req.params.id, 'id');
    if (!store.deleteFolder(req.user.id, id)) {
      return res.status(404).json({ error: 'Dossier introuvable' });
    }
    res.json({ success: true });
  });

  return router;
}

module.exports = { vaultRouter };
