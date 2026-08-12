#!/usr/bin/env bash
# Essai de bout en bout du chiffrement zero-knowledge.
#
# 1. démarre le backend sur une base temporaire
# 2. fait tourner le client Dart réel contre lui
# 3. fouille le fichier SQLite pour vérifier qu'aucun secret n'y est lisible
#
# C'est l'étape 3 qui compte : les tests unitaires prouvent que le chiffrement
# fonctionne, celle-ci prouve que le serveur ne voit effectivement rien.

set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$(cd "$APP_DIR/../backend" && pwd)"
WORK="$(mktemp -d)"
DB="$WORK/vault.db"
PORT="${PORT:-3999}"

cleanup() {
  [[ -n "${SRV_PID:-}" ]] && kill "$SRV_PID" 2>/dev/null || true
  wait "${SRV_PID:-}" 2>/dev/null || true
}
trap cleanup EXIT

echo "▸ démarrage du backend sur une base neuve ($DB)"
PASSVAULT_DB="$DB" PORT="$PORT" PASSVAULT_REGISTRATION=first-only \
  node "$BACKEND_DIR/server.js" > "$WORK/server.log" 2>&1 &
SRV_PID=$!

for _ in $(seq 1 50); do
  if curl -fsS "http://127.0.0.1:$PORT/api/status" > /dev/null 2>&1; then break; fi
  sleep 0.2
done
if ! curl -fsS "http://127.0.0.1:$PORT/api/status" > /dev/null 2>&1; then
  echo "✗ le backend n'a pas démarré :" >&2
  cat "$WORK/server.log" >&2
  exit 1
fi

echo "▸ essai du client Dart contre ce serveur"
cd "$APP_DIR"
flutter test test/integration/vault_e2e_test.dart \
  --dart-define=PASSVAULT_API_URL="http://127.0.0.1:$PORT"

echo
echo "▸ inspection de la base : aucun de ces marqueurs ne doit y apparaître"

# Les marqueurs sont ceux écrits par le test. On cherche dans le fichier
# principal et dans le journal WAL, qui peut contenir des pages non fusionnées.
MARQUEURS=(
  "MARQUEUR-SECRET-Zx9Qw7:mot de passe d'un identifiant"
  "MARQUEUR-NOM-Kp3Rt8:nom d'un élément"
  "MARQUEUR-NOTE-Vb2Nm5:contenu d'une note"
  "MARQUEUR-DOSSIER-Hj6Ly4:nom d'un dossier"
  "4111111111111111:numéro de carte bancaire"
  "JBSWY3DPEHPK3PXP:secret TOTP"
  # Entré par le chemin d'import, pas par saveItem : il doit être chiffré aussi.
  "MARQUEUR-IMPORT-Qw8Zx3:mot de passe arrivé par import"
  "Importé GitHub:nom d'un élément importé"
  "phrase-de-passe-de-la-sauvegarde:phrase de passe de la sauvegarde"
  "$([ -n "${1:-}" ] && echo "$1" || echo "mot-de-passe-maitre-de-test-2026"):mot de passe maître"
)

FUITES=0
for entry in "${MARQUEURS[@]}"; do
  marqueur="${entry%%:*}"
  label="${entry#*:}"
  if grep -aqF -- "$marqueur" "$DB" "$DB-wal" 2>/dev/null; then
    echo "  ✗ FUITE — $label ($marqueur) trouvé en clair dans la base"
    FUITES=$((FUITES + 1))
  else
    echo "  ✓ absent : $label"
  fi
done

# Contrôle inverse : l'e-mail, lui, DOIT être présent. Sans ça un grep cassé
# passerait tous les tests précédents pour de mauvaises raisons.
echo
if grep -aqF -- "e2e@coffort.test" "$DB" "$DB-wal" 2>/dev/null; then
  echo "  ✓ contrôle inverse : l'e-mail du compte est bien lisible (le grep fonctionne)"
else
  echo "  ✗ contrôle inverse ÉCHOUÉ : même l'e-mail est introuvable, le grep ne teste rien"
  FUITES=$((FUITES + 1))
fi

echo
if [[ "$FUITES" -eq 0 ]]; then
  echo "✓ zero-knowledge vérifié : le serveur stocke le coffre sans pouvoir le lire."
else
  echo "✗ $FUITES problème(s). Le coffre n'est pas opaque au serveur." >&2
  exit 1
fi
