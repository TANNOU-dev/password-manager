// Traduction des lignes SQLite (snake_case) vers le JSON de l'API (camelCase).
// Un seul endroit à corriger si le schéma bouge.

function kdfOf(user) {
  return {
    type: user.kdf_type,
    iterations: user.kdf_iterations,
    memory: user.kdf_memory,
    parallelism: user.kdf_parallelism,
  };
}

function profile(user) {
  return {
    id: user.id,
    email: user.email,
    kdf: kdfOf(user),
    kdfSalt: user.kdf_salt,
    // Le client en a besoin pour déballer la clé du coffre. Illisible sans le
    // mot de passe maître.
    protectedKey: user.protected_key,
    createdAt: user.created_at,
  };
}

function cipher(row) {
  return {
    id: row.id,
    type: row.type,
    folderId: row.folder_id,
    favorite: row.favorite === 1,
    reprompt: row.reprompt === 1,
    data: row.data,
    createdAt: row.created_at,
    revisionDate: row.revision_date,
    deletedAt: row.deleted_at,
  };
}

function folder(row) {
  return {
    id: row.id,
    name: row.name,
    revisionDate: row.revision_date,
  };
}

module.exports = { profile, kdfOf, cipher, folder };
