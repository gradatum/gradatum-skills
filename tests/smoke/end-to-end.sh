#!/usr/bin/env bash
# end-to-end.sh — Smoke test E2E contre gradatum LIVE :19090
#
# Tests : Auth Path 2 (API key → JWT) + vault_search + validation structure réponse
#
# Usage  : bash tests/smoke/end-to-end.sh
# Exit   : 0 = tous les checks OK, 1 = au moins un check KO
#
# Variables d'environnement :
#   GRADATUM_URL         (défaut : http://<gradatum-server>)
#   GRADATUM_API_KEY_FILE (défaut : /etc/gradatum/claude-code.api-key)

set -euo pipefail

GRADATUM_URL="${GRADATUM_URL:-http://<gradatum-server>}"
API_KEY_FILE="${GRADATUM_API_KEY_FILE:-/etc/gradatum/claude-code.api-key}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_SH="$SCRIPT_DIR/../../skills/gradatum-vault-search/scripts/search.sh"

# Compteurs
PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

check_pass() {
  local label="$1"
  echo "  [PASS] $label"
  PASS=$((PASS + 1))
}

check_fail() {
  local label="$1"
  local detail="${2:-}"
  echo "  [FAIL] $label" >&2
  [ -n "$detail" ] && echo "         $detail" >&2
  FAIL=$((FAIL + 1))
}

# ---------------------------------------------------------------------------
# Prérequis
# ---------------------------------------------------------------------------

echo "=== Smoke test gradatum-skills Phase 1 ==="
echo "Cible : $GRADATUM_URL"
echo ""

echo "--- Prérequis ---"

if [ -f "$API_KEY_FILE" ]; then
  check_pass "Fichier API key présent : $API_KEY_FILE"
else
  check_fail "Fichier API key absent : $API_KEY_FILE"
fi

if command -v curl >/dev/null 2>&1; then
  check_pass "curl disponible"
else
  check_fail "curl manquant"
fi

if command -v jq >/dev/null 2>&1; then
  check_pass "jq disponible"
else
  check_fail "jq manquant"
fi

if [ -x "$SEARCH_SH" ]; then
  check_pass "search.sh présent et exécutable"
else
  check_fail "search.sh absent ou non exécutable : $SEARCH_SH"
fi

echo ""

# ---------------------------------------------------------------------------
# Check 1 : Health gradatum
# ---------------------------------------------------------------------------

echo "--- Check 1 : Health gradatum ---"

HEALTH_RESP=$(curl -sS --max-time 5 "$GRADATUM_URL/health" 2>&1) || {
  check_fail "Health check gradatum (connexion refusée ou timeout)"
  echo ""
  echo "=== RÉSULTAT : FAIL ($PASS PASS / $FAIL FAIL) ===" >&2
  exit 1
}

HEALTH_STATUS=$(printf '%s' "$HEALTH_RESP" | jq -r '.status // empty' 2>/dev/null)
if [ "$HEALTH_STATUS" = "ok" ]; then
  HEALTH_VERSION=$(printf '%s' "$HEALTH_RESP" | jq -r '.version // "inconnue"')
  check_pass "gradatum LIVE version $HEALTH_VERSION"
else
  check_fail "gradatum health status inattendu" "Réponse : $HEALTH_RESP"
fi

echo ""

# ---------------------------------------------------------------------------
# Check 2 : Auth Path 2 (API key → JWT)
# ---------------------------------------------------------------------------

echo "--- Check 2 : Auth Path 2 (échange API key → JWT) ---"

API_KEY=$(cat "$API_KEY_FILE" 2>/dev/null) || API_KEY=$(sudo cat "$API_KEY_FILE" 2>/dev/null) || {
  check_fail "Lecture API key échouée"
  FAIL=$((FAIL + 1))
  API_KEY=""
}

if [ -n "$API_KEY" ]; then
  AUTH_RESP=$(curl -sS -X POST "$GRADATUM_URL/auth/exchange" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    --max-time 5 2>&1) || {
    check_fail "auth/exchange : connexion échouée"
    AUTH_RESP=""
  }

  if [ -n "$AUTH_RESP" ]; then
    JWT=$(printf '%s' "$AUTH_RESP" | jq -r '.token // empty' 2>/dev/null)
    TTL=$(printf '%s' "$AUTH_RESP" | jq -r '.ttl_secs // 0' 2>/dev/null)

    if [ -n "$JWT" ] && [ "${#JWT}" -gt 50 ]; then
      check_pass "JWT obtenu (longueur ${#JWT} chars, TTL ${TTL}s)"
    else
      check_fail "JWT invalide ou absent" "Réponse : $AUTH_RESP"
      JWT=""
    fi
  fi
fi

echo ""

# ---------------------------------------------------------------------------
# Check 3 : vault_search — structure réponse
# ---------------------------------------------------------------------------

echo "--- Check 3 : vault_search structure réponse ---"

if [ -n "${JWT:-}" ]; then
  SEARCH_RESP=$(curl -sS -X POST "$GRADATUM_URL/api/v1/vault_search" \
    -H "Authorization: Bearer $JWT" \
    -H "Content-Type: application/json" \
    --max-time 10 \
    -d '{"query": "gradatum council decisions 2026", "limit": 3}' \
    2>&1) || {
    check_fail "vault_search : connexion échouée"
    SEARCH_RESP=""
  }

  if [ -n "$SEARCH_RESP" ]; then
    # Vérifier que "items" est présent
    ITEMS_PRESENT=$(printf '%s' "$SEARCH_RESP" | jq 'has("items")' 2>/dev/null)
    if [ "$ITEMS_PRESENT" = "true" ]; then
      check_pass "Réponse vault_search contient le champ 'items'"
    else
      check_fail "Champ 'items' absent de la réponse" "Réponse : $SEARCH_RESP"
    fi

    # Vérifier que items est un tableau
    ITEMS_IS_ARRAY=$(printf '%s' "$SEARCH_RESP" | jq '.items | type == "array"' 2>/dev/null)
    if [ "$ITEMS_IS_ARRAY" = "true" ]; then
      ITEM_COUNT=$(printf '%s' "$SEARCH_RESP" | jq '.items | length')
      check_pass "items est un tableau ($ITEM_COUNT résultats)"
    else
      check_fail "items n'est pas un tableau"
    fi

    # Vérifier la structure d'un item (si non vide)
    ITEM_COUNT_VAL=$(printf '%s' "$SEARCH_RESP" | jq '.items | length')
    if [ "$ITEM_COUNT_VAL" -gt 0 ]; then
      HAS_PATH=$(printf '%s' "$SEARCH_RESP" | jq '.items[0] | has("path")' 2>/dev/null)
      HAS_SCORE=$(printf '%s' "$SEARCH_RESP" | jq '.items[0] | has("score")' 2>/dev/null)

      if [ "$HAS_PATH" = "true" ]; then
        check_pass "Premier item contient le champ 'path'"
      else
        check_fail "Premier item manque le champ 'path'"
      fi

      if [ "$HAS_SCORE" = "true" ]; then
        check_pass "Premier item contient le champ 'score'"
      else
        check_fail "Premier item manque le champ 'score'"
      fi

      # Vérifier que le path contient un ULID extractible
      FIRST_PATH=$(printf '%s' "$SEARCH_RESP" | jq -r '.items[0].path // ""')
      ULID=$(printf '%s' "$FIRST_PATH" | cut -d'/' -f2)
      if [ "${#ULID}" -eq 26 ]; then
        check_pass "ULID extractible depuis path (longueur 26 : $ULID)"
      else
        check_fail "ULID invalide dans path" "path=$FIRST_PATH ulid=$ULID (len=${#ULID})"
      fi
    else
      echo "  [SKIP] Structure item (0 résultat retourné pour cette query)"
    fi
  fi
else
  echo "  [SKIP] vault_search (pas de JWT disponible)"
fi

echo ""

# ---------------------------------------------------------------------------
# Check 4 : Script search.sh bout-en-bout
# ---------------------------------------------------------------------------

echo "--- Check 4 : search.sh bout-en-bout ---"

SEARCH_OUTPUT=$(bash "$SEARCH_SH" "gradatum council decisions 2026" 2>&1) || {
  check_fail "search.sh retourné un code d'erreur" "Output : $SEARCH_OUTPUT"
  SEARCH_OUTPUT=""
}

if [ -n "$SEARCH_OUTPUT" ]; then
  if [[ "$SEARCH_OUTPUT" == "🧠"* ]]; then
    check_pass "search.sh retourne le format attendu '🧠 ...'"
    echo "         Output : $SEARCH_OUTPUT"
  else
    check_fail "search.sh output inattendu (ne commence pas par '🧠')" "Output : $SEARCH_OUTPUT"
  fi
fi

echo ""

# ---------------------------------------------------------------------------
# Résultat final
# ---------------------------------------------------------------------------

echo "=== RÉSULTAT : $PASS PASS / $FAIL FAIL ==="

if [ "$FAIL" -gt 0 ]; then
  echo "FAIL — $FAIL check(s) en échec" >&2
  exit 1
else
  echo "PASS — tous les checks OK"
  exit 0
fi
