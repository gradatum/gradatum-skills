#!/usr/bin/env bash
# read.sh — Wrapper atomique vault_read gradatum :19090
#
# Usage   : read.sh "<section>/<ulid>"
# Output  : "📄 <path>  [section: <section>]\nsha256: <hash>\n---\n<contenu>" (stdout)
# Exit    : 0 si OK, >0 si erreur HTTP / JWT KO / note absente
#
# Variables d'environnement :
#   GRADATUM_SERVER_URL    (défaut : http://<gradatum-server>)
#   GRADATUM_API_KEY_FILE  (défaut : /etc/gradatum/claude-code.api-key)
#
# Sécurité : le secret (clé API, JWT) est passé à curl via un en-tête sur descripteur
# de fichier (`-H @<(...)`) — jamais en argv (pas d'exposition /proc/<pid>/cmdline).

set -euo pipefail

PATH_ARG="${1:?usage: read.sh \"<section>/<ulid>\"}"
GRADATUM_URL="${GRADATUM_SERVER_URL:-http://<gradatum-server>}"
API_KEY_FILE="${GRADATUM_API_KEY_FILE:-/etc/gradatum/claude-code.api-key}"

# --- 1. Lire la clé API (sudo -n = non-bloquant : échoue au lieu de demander un mot de passe) ---
if [ ! -f "$API_KEY_FILE" ]; then
  echo "Erreur : fichier API key absent : $API_KEY_FILE" >&2
  exit 1
fi
API_KEY=$(cat "$API_KEY_FILE" 2>/dev/null) || API_KEY=$(sudo -n cat "$API_KEY_FILE" 2>/dev/null) || {
  echo "Erreur : impossible de lire $API_KEY_FILE (permissions ? rendez-le lisible par l'utilisateur)" >&2
  exit 1
}

# --- 2. Échange clé API → JWT (secret via FD, pas en argv) ---
JWT_RESP=$(curl -sS -X POST "$GRADATUM_URL/auth/exchange" \
  -H @<(printf 'Authorization: Bearer %s\n' "$API_KEY") \
  -H "Content-Type: application/json" --max-time 5 --fail-with-body 2>&1) || {
  echo "Erreur : auth exchange gradatum KO : $JWT_RESP" >&2
  exit 1
}
JWT=$(printf '%s' "$JWT_RESP" | jq -r '.token // empty')
if [ -z "$JWT" ] || [ "${#JWT}" -lt 50 ]; then
  echo "Erreur : JWT invalide retourné par gradatum" >&2
  exit 1
fi

# --- 3. Appel vault_read ---
READ_RESP=$(curl -sS -X POST "$GRADATUM_URL/api/v1/vault_read" \
  -H @<(printf 'Authorization: Bearer %s\n' "$JWT") \
  -H "Content-Type: application/json" --max-time 10 --fail-with-body \
  -d "$(jq -n --arg p "$PATH_ARG" '{path: $p}')" 2>&1) || {
  echo "📄 note introuvable : $PATH_ARG" >&2
  exit 1
}

# --- 4. Format sortie ---
# Champ `title` : présent à partir de gradatum v0.5.2 (peut être null si la note n'a ni
# titre indexé ni H1 `# ` en tête de corps) ; ABSENT sur gradatum <= v0.4.3. Le filtre jq
# `.title // empty` couvre les deux cas (affiché seulement si non-null et non-absent), donc
# le script reste compatible avec les deux familles de versions sans détection explicite.
printf '%s' "$READ_RESP" | jq -r --arg input "$PATH_ARG" '
  "📄 \($input)" +
  (if .metadata.section then "  [section: \(.metadata.section)]" else "" end) +
  (if (.title // empty) != "" then "\ntitle: \(.title)" else "" end) +
  "\nsha256: \(.sha256 // "n/a")\n---\n\(.content // "(vide)")"
' 2>/dev/null || {
  echo "Erreur : réponse vault_read non parsable" >&2
  exit 1
}
