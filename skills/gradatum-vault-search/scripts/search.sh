#!/usr/bin/env bash
# search.sh — Wrapper atomique vault_search gradatum :19090
#
# Usage   : search.sh "<query sémantique>"
# Output  : "🧠 N notes : <ulid> [<score>], ..." (stdout)
#           "🧠 0 note pertinente sur ce sujet" si N=0
# Exit    : 0 si OK (même si 0 note), >0 si erreur HTTP ou JWT KO
#
# Variables d'environnement :
#   GRADATUM_SERVER_URL      (défaut : http://<gradatum-server>)
#   GRADATUM_API_KEY_FILE    (défaut : /etc/gradatum/claude-code.api-key)
#   GRADATUM_REMINDER_TOP_K  (défaut : 10)
#   GRADATUM_REMINDER_LOG    (opt-in : 1 pour activer le log dans /tmp/)

set -euo pipefail

# --- Paramètres ---
QUERY="${1:?usage: search.sh \"<query>\"}"
GRADATUM_URL="${GRADATUM_SERVER_URL:-http://<gradatum-server>}"
API_KEY_FILE="${GRADATUM_API_KEY_FILE:-/etc/gradatum/claude-code.api-key}"
TOP_K="${GRADATUM_REMINDER_TOP_K:-10}"

# --- 1. Lire la clé API ---
if [ ! -f "$API_KEY_FILE" ]; then
  echo "Erreur : fichier API key absent : $API_KEY_FILE" >&2
  exit 1
fi
API_KEY=$(cat "$API_KEY_FILE" 2>/dev/null) || {
  # Fallback sudo si permissions root (installation système)
  API_KEY=$(sudo cat "$API_KEY_FILE" 2>/dev/null) || {
    echo "Erreur : impossible de lire $API_KEY_FILE" >&2
    exit 1
  }
}

# --- 2. Échange clé API → JWT (24h) ---
JWT_RESP=$(curl -sS -X POST "$GRADATUM_URL/auth/exchange" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  --max-time 5 \
  --fail-with-body 2>&1) || {
  echo "Erreur : auth exchange gradatum KO : $JWT_RESP" >&2
  exit 1
}

JWT=$(printf '%s' "$JWT_RESP" | jq -r '.token // empty')
if [ -z "$JWT" ] || [ "${#JWT}" -lt 50 ]; then
  echo "Erreur : JWT invalide retourné par gradatum" >&2
  exit 1
fi

# --- 3. Appel vault_search ---
SEARCH_RESP=$(curl -sS -X POST "$GRADATUM_URL/api/v1/vault_search" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  --max-time 10 \
  --fail-with-body \
  -d "$(jq -n --arg q "$QUERY" --argjson k "$TOP_K" '{query: $q, limit: $k}')" \
  2>&1) || {
  echo "Erreur : vault_search gradatum KO : $SEARCH_RESP" >&2
  exit 1
}

# --- 4. Formater la sortie ---
# L'ULID est la 2e partie du champ "path" (format "<locus>/<ulid>")
COUNT=$(printf '%s' "$SEARCH_RESP" | jq '.items | length')

if [ "$COUNT" -eq 0 ]; then
  echo "🧠 0 note pertinente sur ce sujet"
else
  FORMATTED=$(printf '%s' "$SEARCH_RESP" | jq -r '
    .items
    | map(
        (.path | split("/") | last) as $ulid
        | (.score * 10000 | round | . / 10000 | tostring) as $score_str
        | "\($ulid) [\($score_str)]"
      )
    | join(", ")
  ')
  echo "🧠 $COUNT notes : $FORMATTED"
fi

# --- 5. Log optionnel (opt-in via GRADATUM_REMINDER_LOG=1) ---
if [ "${GRADATUM_REMINDER_LOG:-0}" = "1" ]; then
  TS=$(date -u +%FT%TZ)
  TOP_SCORE=$(printf '%s' "$SEARCH_RESP" | jq -r '[.items[].score] | max // 0')
  printf '%s|search|count=%d|topscore=%s|"%s"\n' \
    "$TS" "$COUNT" "$TOP_SCORE" "${QUERY:0:60}" \
    >> /tmp/gradatum-reminder-stats.log
fi
