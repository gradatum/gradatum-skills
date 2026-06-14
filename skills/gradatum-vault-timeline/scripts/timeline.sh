#!/usr/bin/env bash
# timeline.sh — Wrapper atomique vault_timeline gradatum :19090
#
# Usage   : timeline.sh [from_epoch_ms] [to_epoch_ms] [doc_kind:Static|Event]
# Output  : "🕰️ N entrée(s) :\n  <anchor_ms> | <doc_kind> | <ulid> — <titre>" (stdout)
# Exit    : 0 si OK (même si 0 entrée), >0 si erreur HTTP / JWT KO / arg invalide
#
# Variables d'environnement :
#   GRADATUM_SERVER_URL    (défaut : http://<gradatum-server>)
#   GRADATUM_API_KEY_FILE  (défaut : /etc/gradatum/claude-code.api-key)
#
# Sécurité : secret passé via en-tête sur FD (`-H @<(...)`), jamais en argv.

set -euo pipefail

FROM_MS="${1:-}"
TO_MS="${2:-}"
DOC_KIND="${3:-}"
GRADATUM_URL="${GRADATUM_SERVER_URL:-http://<gradatum-server>}"
API_KEY_FILE="${GRADATUM_API_KEY_FILE:-/etc/gradatum/claude-code.api-key}"

# --- 0. Valider les bornes (epoch ms = entiers) ---
for v in "$FROM_MS" "$TO_MS"; do
  [ -z "$v" ] || [[ "$v" =~ ^[0-9]+$ ]] || {
    echo "Erreur : from_ms/to_ms doivent être des epoch millisecondes (entiers)." >&2
    exit 1
  }
done
if [ -n "$DOC_KIND" ] && [ "$DOC_KIND" != "Static" ] && [ "$DOC_KIND" != "Event" ]; then
  echo "Erreur : doc_kind doit être 'Static' ou 'Event'." >&2
  exit 1
fi

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

# --- 3. Construire le payload (champs optionnels) ---
PAYLOAD=$(jq -n --arg from "$FROM_MS" --arg to "$TO_MS" --arg dk "$DOC_KIND" '
  {}
  + (if $from != "" then {from_ms: ($from|tonumber)} else {} end)
  + (if $to   != "" then {to_ms:   ($to|tonumber)}   else {} end)
  + (if $dk   != "" then {doc_kind: [$dk]}            else {} end)')

# --- 4. Appel vault_timeline ---
TL_RESP=$(curl -sS -X POST "$GRADATUM_URL/api/v1/vault_timeline" \
  -H @<(printf 'Authorization: Bearer %s\n' "$JWT") \
  -H "Content-Type: application/json" --max-time 10 --fail-with-body -d "$PAYLOAD" 2>&1) || {
  echo "Erreur : vault_timeline gradatum KO : $TL_RESP" >&2
  exit 1
}

# --- 5. Format sortie ---
COUNT=$(printf '%s' "$TL_RESP" | jq -r '(.items // []) | length' 2>/dev/null || echo 0)
if [ "$COUNT" = "0" ]; then
  echo "🕰️ 0 entrée sur cette fenêtre"
  exit 0
fi
echo "🕰️ $COUNT entrée(s) :"
printf '%s' "$TL_RESP" | jq -r '
  (.items // [])[] |
  "  \(.anchor_ms // "?") | \(.doc_kind // "?") | \(.note_id // .ulid // "?") — \(.title // "(sans titre)")"
' 2>/dev/null || {
  echo "Erreur : réponse timeline non parsable" >&2
  exit 1
}
