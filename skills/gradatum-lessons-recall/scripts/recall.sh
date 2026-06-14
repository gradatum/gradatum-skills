#!/usr/bin/env bash
# recall.sh — Wrapper atomique lessons recall (F-60) gradatum :19090
#
# Usage   : recall.sh "<classe>" [limit]
# Output  : "🎓 N leçon(s) [classe=X] :\n  <ulid> — <titre> :: <snippet>" (stdout)
# Exit    : 0 si OK (même si 0 leçon), >0 si erreur HTTP / JWT KO / classe invalide
#
# Variables d'environnement :
#   GRADATUM_SERVER_URL    (défaut : http://<gradatum-server>)
#   GRADATUM_API_KEY_FILE  (défaut : /etc/gradatum/claude-code.api-key)
#
# Sécurité : secret passé via en-tête sur FD (`-H @<(...)`), jamais en argv.

set -euo pipefail

CLASS="${1:?usage: recall.sh \"<classe>\" [limit]}"
LIMIT="${2:-5}"
[[ "$LIMIT" =~ ^[0-9]+$ ]] || { echo "Erreur : limit doit être un entier positif." >&2; exit 1; }
GRADATUM_URL="${GRADATUM_SERVER_URL:-http://<gradatum-server>}"
API_KEY_FILE="${GRADATUM_API_KEY_FILE:-/etc/gradatum/claude-code.api-key}"

# --- 1. Lire la clé API ---
if [ ! -f "$API_KEY_FILE" ]; then
  echo "Erreur : fichier API key absent : $API_KEY_FILE" >&2
  exit 1
fi
API_KEY=$(cat "$API_KEY_FILE" 2>/dev/null) || API_KEY=$(sudo -n cat "$API_KEY_FILE" 2>/dev/null) || {
  echo "Erreur : impossible de lire $API_KEY_FILE (permissions ?)" >&2
  exit 1
}

# --- 2. Échange clé API → JWT ---
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

# --- 3. Appel lessons recall (GET query string) ---
RECALL_RESP=$(curl -sS -G "$GRADATUM_URL/api/v1/lessons/recall" \
  -H @<(printf 'Authorization: Bearer %s\n' "$JWT") \
  --max-time 10 --fail-with-body \
  --data-urlencode "class=$CLASS" --data-urlencode "limit=$LIMIT" 2>&1) || {
  echo "Erreur : lessons recall gradatum KO (classe '$CLASS' valide ?) : $RECALL_RESP" >&2
  exit 1
}

# --- 4. Format sortie ---
COUNT=$(printf '%s' "$RECALL_RESP" | jq -r '(.items // []) | length' 2>/dev/null || echo 0)
if [ "$COUNT" = "0" ]; then
  echo "🎓 0 leçon pour la classe $CLASS"
  exit 0
fi
echo "🎓 $COUNT leçon(s) [classe=$CLASS] :"
printf '%s' "$RECALL_RESP" | jq -r '
  (.items // [])[] |
  "  \(.ulid // .note_id) — \(.title // "(sans titre)") :: \((.snippet // "") | gsub("\n";" ") | .[0:120])"
' 2>/dev/null || {
  echo "Erreur : réponse recall non parsable" >&2
  exit 1
}
