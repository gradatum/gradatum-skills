#!/usr/bin/env bash
# write.sh — Wrapper atomique vault_write gradatum :19090 (création + MAJ in-place RMW)
#
# Usage :
#   create : write.sh create --section <section> --title "<titre>" [--tags a,b,c]   (corps via stdin)
#   update : write.sh update --note-id <ulid> --sha <sha256> --title "<titre>" [--tags a,b,c]   (corps via stdin)
#
# Le CORPS markdown est lu sur STDIN (heredoc recommandé).
# Output : "✅ <Done|Conflict|Failed> note_id=<ulid>" (stdout) ; exit 0 si Done, >0 sinon.
#
# vault_write est ASYNCHRONE : le script poste (202) puis POLL le job jusqu'à un état terminal
# (Done / Conflict / Failed / DLQ) avant de retourner. Conflict = sha périmé (note non écrasée).
#
# Variables d'environnement :
#   GRADATUM_SERVER_URL    (défaut : http://<gradatum-server>)
#   GRADATUM_API_KEY_FILE  (défaut : /etc/gradatum/claude-code.api-key)
#
# Sécurité : secret passé via en-tête sur FD (`-H @<(...)`), jamais en argv.

set -euo pipefail

MODE="${1:?usage: write.sh create|update ...}"
shift || true
SECTION="" TITLE="" TAGS="" NOTE_ID="" SHA=""
while [ $# -gt 0 ]; do
  case "$1" in
    --section)  SECTION="$2"; shift 2 ;;
    --title)    TITLE="$2";   shift 2 ;;
    --tags)     TAGS="$2";    shift 2 ;;
    --note-id)  NOTE_ID="$2"; shift 2 ;;
    --sha)      SHA="$2";     shift 2 ;;
    *) echo "Erreur : argument inconnu '$1'" >&2; exit 1 ;;
  esac
done

[ -n "$TITLE" ] || { echo "Erreur : --title requis" >&2; exit 1; }
BODY=$(cat)  # corps lu sur stdin
[ -n "$BODY" ] || { echo "Erreur : corps markdown vide (passer le corps sur stdin)" >&2; exit 1; }

GRADATUM_URL="${GRADATUM_SERVER_URL:-http://<gradatum-server>}"
API_KEY_FILE="${GRADATUM_API_KEY_FILE:-/etc/gradatum/claude-code.api-key}"

# Tags "a,b,c" → tableau JSON (vide → [])
if [ -z "$TAGS" ]; then
  TAGS_JSON="[]"
else
  TAGS_JSON=$(printf '%s' "$TAGS" | jq -Rc 'split(",") | map(select(length>0))')
fi

# --- Construire le payload selon le mode ---
case "$MODE" in
  create)
    [ -n "$SECTION" ] || { echo "Erreur : --section requis en mode create" >&2; exit 1; }
    PAYLOAD=$(jq -n --arg s "$SECTION" --arg t "$TITLE" --arg b "$BODY" --argjson tags "$TAGS_JSON" \
      '{section_hint:$s, title:$t, body:$b, tags:$tags, author:"skill", tenant_id:"main"}')
    ;;
  update)
    [ -n "$NOTE_ID" ] || { echo "Erreur : --note-id requis en mode update" >&2; exit 1; }
    [[ "$SHA" =~ ^[0-9a-f]{64}$ ]] || { echo "Erreur : --sha doit être 64 hex lowercase (obtenu via vault-read)" >&2; exit 1; }
    PAYLOAD=$(jq -n --arg n "$NOTE_ID" --arg sha "$SHA" --arg s "$SECTION" --arg t "$TITLE" --arg b "$BODY" --argjson tags "$TAGS_JSON" \
      '{note_id:$n, expected_sha256:$sha, title:$t, body:$b, tags:$tags, tenant_id:"main"}
       + (if $s != "" then {section_hint:$s} else {} end)')
    ;;
  *) echo "Erreur : mode doit être 'create' ou 'update'" >&2; exit 1 ;;
esac

# --- Auth ---
if [ ! -f "$API_KEY_FILE" ]; then echo "Erreur : API key absente : $API_KEY_FILE" >&2; exit 1; fi
API_KEY=$(cat "$API_KEY_FILE" 2>/dev/null) || API_KEY=$(sudo -n cat "$API_KEY_FILE" 2>/dev/null) || {
  echo "Erreur : impossible de lire $API_KEY_FILE (permissions ?)" >&2; exit 1; }
JWT_RESP=$(curl -sS -X POST "$GRADATUM_URL/auth/exchange" \
  -H @<(printf 'Authorization: Bearer %s\n' "$API_KEY") \
  -H "Content-Type: application/json" --max-time 5 --fail-with-body 2>&1) || {
  echo "Erreur : auth exchange KO : $JWT_RESP" >&2; exit 1; }
JWT=$(printf '%s' "$JWT_RESP" | jq -r '.token // empty')
[ "${#JWT}" -ge 50 ] || { echo "Erreur : JWT invalide" >&2; exit 1; }

# --- POST vault_write (202 async) ---
WR_RESP=$(curl -sS -X POST "$GRADATUM_URL/api/v1/vault_write" \
  -H @<(printf 'Authorization: Bearer %s\n' "$JWT") \
  -H "Content-Type: application/json" --max-time 10 --fail-with-body -d "$PAYLOAD" 2>&1) || {
  echo "Erreur : vault_write KO : $WR_RESP" >&2; exit 1; }
JOB_ID=$(printf '%s' "$WR_RESP" | jq -r '.job_id // empty')
NOTE_OUT=$(printf '%s' "$WR_RESP" | jq -r '.note_id // empty')
[ -n "$JOB_ID" ] || { echo "Erreur : pas de job_id retourné : $WR_RESP" >&2; exit 1; }

# --- POLL le job jusqu'à état terminal ---
STATUS=""
for _ in $(seq 1 20); do
  POLL=$(curl -sS "$GRADATUM_URL/api/v1/jobs/$JOB_ID/v2" \
    -H @<(printf 'Authorization: Bearer %s\n' "$JWT") --max-time 5 2>&1) || break
  STATUS=$(printf '%s' "$POLL" | jq -r '.lifecycle.status // .status // empty')
  case "$STATUS" in
    Done|Conflict|Failed|DLQ|Cancelled) break ;;
  esac
  sleep 1
done

case "$STATUS" in
  Done)     echo "✅ Done note_id=${NOTE_OUT:-$NOTE_ID}"; exit 0 ;;
  Conflict) echo "⚠️ Conflict (sha périmé — re-lire via vault-read, ré-appliquer) note_id=${NOTE_OUT:-$NOTE_ID}" >&2; exit 2 ;;
  Failed|DLQ) echo "❌ $STATUS — écriture échouée note_id=${NOTE_OUT:-$NOTE_ID}" >&2; exit 3 ;;
  *) echo "⏳ job non terminal après timeout (status=${STATUS:-?}) job_id=$JOB_ID" >&2; exit 4 ;;
esac
