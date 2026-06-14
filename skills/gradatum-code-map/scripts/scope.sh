#!/usr/bin/env bash
# scope.sh — Wrapper atomique code_scope gradatum :19090 (carte de code dérivée)
#
# Usage   : scope.sh <vault> <kind:query|symbol|path> <value> [body]
#   ex.   : scope.sh code-myproject symbol parse_config
#           scope.sh code-myproject query "auth middleware" body
#           scope.sh code-myproject path src/auth.rs
# Le 4e arg "body" (optionnel) inclut le corps exact des symboles (include_body).
#
# Prérequis : le repo doit avoir été ingéré au préalable via
#   gradatum-admin code ingest --vault code-<projet> <repo_path>
#   gradatum-admin code update --vault code-<projet> <repo_path>   (rafraîchir, O(diff) git)
#
# Output  : signatures (+ corps si body) des symboles pertinents.
# Exit    : 0 si OK, >0 si erreur HTTP / JWT KO / vault invalide.
#
# Variables d'environnement :
#   GRADATUM_SERVER_URL    (défaut : http://<gradatum-server>)
#   GRADATUM_API_KEY_FILE  (défaut : /etc/gradatum/claude-code.api-key)

set -euo pipefail

VAULT="${1:?usage: scope.sh <vault:code-X> <query|symbol|path> <value> [body]}"
KIND="${2:?usage: scope.sh <vault> <query|symbol|path> <value> [body]}"
VALUE="${3:?usage: scope.sh <vault> <query|symbol|path> <value> [body]}"
WANT_BODY="${4:-}"

[[ "$VAULT" =~ ^code-[a-z0-9-]+$ ]] || { echo "Erreur : <vault> doit matcher 'code-[a-z0-9-]+' (ex. code-myproject)" >&2; exit 1; }
case "$KIND" in query|symbol|path) ;; *) echo "Erreur : <kind> doit être query | symbol | path" >&2; exit 1 ;; esac
INCLUDE_BODY=false; [ "$WANT_BODY" = "body" ] && INCLUDE_BODY=true
# Budget adaptatif : plus large en mode body (les corps gonflent). Surchargeable.
if [ "$INCLUDE_BODY" = "true" ]; then BUDGET="${GRADATUM_BUDGET_TOKENS:-2500}"; else BUDGET="${GRADATUM_BUDGET_TOKENS:-1200}"; fi

GRADATUM_URL="${GRADATUM_SERVER_URL:-http://<gradatum-server>}"
API_KEY_FILE="${GRADATUM_API_KEY_FILE:-/etc/gradatum/claude-code.api-key}"

# --- Auth ---
[ -f "$API_KEY_FILE" ] || { echo "Erreur : API key absente : $API_KEY_FILE" >&2; exit 1; }
API_KEY=$(cat "$API_KEY_FILE" 2>/dev/null) || API_KEY=$(sudo -n cat "$API_KEY_FILE" 2>/dev/null) || {
  echo "Erreur : impossible de lire $API_KEY_FILE (permissions ?)" >&2; exit 1; }
JWT_RESP=$(curl -sS -X POST "$GRADATUM_URL/auth/exchange" \
  -H @<(printf 'Authorization: Bearer %s\n' "$API_KEY") \
  -H "Content-Type: application/json" --max-time 5 --fail-with-body 2>&1) || {
  echo "Erreur : auth exchange KO : $JWT_RESP" >&2; exit 1; }
JWT=$(printf '%s' "$JWT_RESP" | jq -r '.token // empty')
[ "${#JWT}" -ge 50 ] || { echo "Erreur : JWT invalide" >&2; exit 1; }

# --- code_scope ---
PAYLOAD=$(jq -n --arg v "$VAULT" --arg k "$KIND" --arg val "$VALUE" --argjson ib "$INCLUDE_BODY" --argjson bud "$BUDGET" \
  '{vault:$v, selector:{kind:$k, value:$val}, include_body:$ib, budget_tokens:$bud}')
RESP=$(curl -sS -X POST "$GRADATUM_URL/api/v1/code_scope" \
  -H @<(printf 'Authorization: Bearer %s\n' "$JWT") \
  -H "Content-Type: application/json" --max-time 10 --fail-with-body -d "$PAYLOAD" 2>&1) || {
  echo "Erreur : code_scope KO (vault '$VAULT' ingéré ? cf gradatum-admin code ingest) : $RESP" >&2; exit 1; }

N=$(printf '%s' "$RESP" | jq -r '(.entries // []) | length' 2>/dev/null || echo 0)
if [ "$N" = "0" ]; then echo "🗺️ 0 symbole [$KIND=$VALUE] dans $VAULT"; exit 0; fi
TRUNC=$(printf '%s' "$RESP" | jq -r '
  (if .truncated then " (entrées tronquées par budget — augmenter GRADATUM_BUDGET_TOKENS)" else "" end) +
  (if .body_truncated then " (⚠️ corps omis par budget : certains body absents)" else "" end)')
echo "🗺️ $N symbole(s) [$KIND=$VALUE] dans $VAULT$TRUNC :"
printf '%s' "$RESP" | jq -r '
  (.entries // [])[] |
  "  \(.source_path):\(.qualified_name)\(.signature)\(if .stale then "  ⚠️STALE" else "" end)" +
  (if .body then "\n----\n\(.body)\n----" else "" end)
' 2>/dev/null || { echo "Erreur : réponse code_scope non parsable" >&2; exit 1; }
