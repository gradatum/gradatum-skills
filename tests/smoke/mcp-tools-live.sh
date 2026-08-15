#!/usr/bin/env bash
# mcp-tools-live.sh — Adaptateur LIVE pour la vérification d'atteignabilité (4c-2).
#
# Rôle unique : obtenir la liste RÉELLE des outils exposés par un serveur
# gradatum joignable (méthode MCP `tools/list`), puis la passer à
# tests/verify-mcp-tools.sh. Aucune liste n'est écrite ici, aucun cardinal
# n'est attendu : le nombre d'outils change au fil des versions du serveur.
#
# PORTÉE — ce que cet adaptateur ne peut PAS établir seul : un serveur n'a
# aucune vue sur la liste d'outils réellement offerte à un client, laquelle est
# figée à la connexion de ce client. La liste `tools/list` prouve donc
# l'existence, pas l'exécutabilité. Passer `--client-tools <fichier>` transmet
# la surface du client au vérificateur, qui rend alors un verdict d'appelabilité
# et distingue « inexistant » de « exposé par le serveur, absent du client ».
#
# Usage : bash tests/smoke/mcp-tools-live.sh [--client-tools FICHIER]
# Exit  : 0 = tous les outils nommés par les skills sont appelables
#         1 = au moins un manquant, ou serveur injoignable
#
# IDENTITÉ — aucune valeur par défaut, par construction. L'emplacement du
# fichier de clé est une valeur d'INSTALLATION, propre à chaque déploiement :
# ce dépôt public ne prescrit pas où poser un credential, et ne nomme pas qui
# le consomme. Fournir l'une des deux, sans quoi le script sort en erreur.
#
# Variables d'environnement :
#   GRADATUM_URL          (REQUIS — adresse du serveur gradatum du consommateur)
#   GRADATUM_API_KEY_FILE (REQUISE sauf si GRADATUM_TOKEN — chemin du fichier de clé)
#   GRADATUM_TOKEN        (jeton déjà obtenu ; court-circuite l'échange)

set -euo pipefail

GRADATUM_URL="${GRADATUM_URL:?GRADATUM_URL requis — ce depot ne connait pas votre adresse de serveur}"
API_KEY_FILE="${GRADATUM_API_KEY_FILE:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"

CLIENT_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --client-tools)
      [ -n "${2:-}" ] || { echo "FAIL — --client-tools attend un fichier" >&2; exit 2; }
      CLIENT_ARGS=(--client-tools "$2"); shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "argument inconnu : $1" >&2; exit 2 ;;
  esac
done

for bin in curl jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "FAIL — $bin manquant" >&2; exit 1; }
done

TOKEN="${GRADATUM_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  if [ -z "$API_KEY_FILE" ]; then
    echo "FAIL — IDENTITÉ INDISPONIBLE : ni GRADATUM_TOKEN ni GRADATUM_API_KEY_FILE." >&2
    echo "       L'emplacement du fichier de clé est une valeur d'installation," >&2
    echo "       propre à votre déploiement — ce dépôt n'en prescrit aucun." >&2
    echo "       Fournir GRADATUM_API_KEY_FILE=<chemin> ou GRADATUM_TOKEN=<jeton>." >&2
    exit 1
  fi
  # Le fichier de clé peut n'être lisible que par le compte de service ; l'élévation
  # non interactive est tentée en second, sans jamais bloquer sur une invite.
  API_KEY=$(cat "$API_KEY_FILE" 2>/dev/null) \
    || API_KEY=$(sudo -n cat "$API_KEY_FILE" 2>/dev/null) \
    || { echo "FAIL — IDENTITÉ INDISPONIBLE : clé API illisible ($API_KEY_FILE)" >&2; exit 1; }
  TOKEN=$(curl -sS -X POST "$GRADATUM_URL/auth/exchange" \
    -H "Authorization: Bearer $API_KEY" \
    -H 'Content-Type: application/json' --max-time 5 | jq -r '.token // empty')
  [ -n "$TOKEN" ] || { echo "FAIL — échange de jeton sans réponse exploitable" >&2; exit 1; }
fi

# La réponse peut être servie en JSON simple ou en flux d'événements (`data: {...}`).
RAW=$(curl -sS -X POST "$GRADATUM_URL/mcp" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  --max-time 10 \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}')

BODY=$(printf '%s' "$RAW" | sed -n 's/^data: //p')
[ -n "$BODY" ] || BODY="$RAW"

TOOLS=$(printf '%s' "$BODY" | jq -r '.result.tools[].name' 2>/dev/null | sort -u)
if [ -z "$TOOLS" ]; then
  echo "FAIL — aucune liste d'outils exploitable dans la réponse du serveur" >&2
  printf '%s\n' "$RAW" | head -c 500 >&2
  exit 1
fi

echo "Liste obtenue du serveur $GRADATUM_URL (méthode tools/list) :"
printf '%s\n' "$TOOLS" | tr '\n' ' '
echo ""
echo ""

if [ "${#CLIENT_ARGS[@]}" -eq 0 ]; then
  echo "Surface client non fournie : le verdict portera sur l'EXISTENCE, pas sur l'appelabilité."
  echo ""
fi

# La liste serveur passe par un fichier, pas par un tube : le vérificateur ne lit
# stdin que si AUCUNE liste ne lui est nommée, et il en reçoit ici au moins une.
SRV_FILE=$(mktemp)
trap 'rm -f "$SRV_FILE"' EXIT
printf '%s\n' "$TOOLS" > "$SRV_FILE"

bash "$HERE/../verify-mcp-tools.sh" --tools "$SRV_FILE" "${CLIENT_ARGS[@]+"${CLIENT_ARGS[@]}"}"
