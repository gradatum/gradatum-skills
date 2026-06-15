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
#   GRADATUM_INCLUDE_CORPUS_COUNT (opt-in : 1 → preuve d'absence ; gradatum >= v0.5.2)

set -euo pipefail

# --- Paramètres ---
QUERY="${1:?usage: search.sh \"<query>\"}"
GRADATUM_URL="${GRADATUM_SERVER_URL:-http://<gradatum-server>}"
API_KEY_FILE="${GRADATUM_API_KEY_FILE:-/etc/gradatum/claude-code.api-key}"
TOP_K="${GRADATUM_REMINDER_TOP_K:-10}"
INCLUDE_CORPUS="${GRADATUM_INCLUDE_CORPUS_COUNT:-0}"

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
# include_corpus_count (opt-in) : gradatum >= v0.5.2 retourne `corpus_match_count` =
# nombre total de notes matchant la query en BM25/FTS5 dans tout le corpus (ignore le
# ranking/seuil) → preuve d'absence. Sur < v0.5.2 le champ est ignoré (absent en réponse).
REQ_BODY=$(jq -n --arg q "$QUERY" --argjson k "$TOP_K" --argjson cc "$([ "$INCLUDE_CORPUS" = "1" ] && echo true || echo false)" \
  '{query: $q, limit: $k} + (if $cc then {include_corpus_count: true} else {} end)')
SEARCH_RESP=$(curl -sS -X POST "$GRADATUM_URL/api/v1/vault_search" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  --max-time 10 \
  --fail-with-body \
  -d "$REQ_BODY" \
  2>&1) || {
  echo "Erreur : vault_search gradatum KO : $SEARCH_RESP" >&2
  exit 1
}

# --- 4. Formater la sortie ---
# L'ULID est la 2e partie du champ "path" (format "<locus>/<ulid>")
COUNT=$(printf '%s' "$SEARCH_RESP" | jq '.items | length')
# corpus_match_count : présent seulement si demandé ET gradatum >= v0.5.2 (sinon vide).
# jq `// empty` : 0 est truthy en jq (seuls null/false falsy) → corpus=0 est bien préservé,
# pas confondu avec "champ absent" (qui donne la chaîne vide).
CORPUS=$(printf '%s' "$SEARCH_RESP" | jq -r '.corpus_match_count // empty')

# Hint preuve-d'absence affiché DANS LES DEUX branches quand corpus=0 (cas le plus piégeux :
# N>0 alors que 0 match lexical → les résultats sont des voisins sémantiques seuls).
CORPUS_HINT=""
if [ "$CORPUS" = "0" ]; then
  CORPUS_HINT=" (corpus_match_count=0 → 0 match lexical : absence prouvée, résultats sémantiques seuls)"
elif [ -n "$CORPUS" ]; then
  CORPUS_HINT=" (corpus_match_count=$CORPUS matchs lexicaux)"
fi

if [ "$COUNT" -eq 0 ]; then
  echo "🧠 0 note pertinente sur ce sujet${CORPUS_HINT}"
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
  echo "🧠 $COUNT notes${CORPUS_HINT} : $FORMATTED"
fi

# --- 5. Log optionnel (opt-in via GRADATUM_REMINDER_LOG=1) ---
if [ "${GRADATUM_REMINDER_LOG:-0}" = "1" ]; then
  TS=$(date -u +%FT%TZ)
  TOP_SCORE=$(printf '%s' "$SEARCH_RESP" | jq -r '[.items[].score] | max // 0')
  printf '%s|search|count=%d|topscore=%s|"%s"\n' \
    "$TS" "$COUNT" "$TOP_SCORE" "${QUERY:0:60}" \
    >> /tmp/gradatum-reminder-stats.log
fi
