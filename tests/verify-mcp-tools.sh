#!/usr/bin/env bash
# verify-mcp-tools.sh — Atteignabilité des outils MCP (lot 4c-2).
#
# Propriété vérifiée : chaque outil MCP nommé dans un SKILL.md est réellement
# APPELABLE. C'est ce qui sépare « installé » de « opérationnel ».
#
# DEUX SURFACES, PAS UNE. Un outil peut exister côté serveur et rester
# inappelable : la liste d'outils d'un client MCP est figée à la connexion, et
# un client connecté avant l'ajout d'un outil ne le voit pas. La surface qui
# décide de l'exécutabilité est donc celle du CLIENT, pas celle du serveur.
#   --tools         liste exposée par le SERVEUR (méthode `tools/list`)
#   --client-tools  liste réellement offerte au CLIENT qui exécutera les skills
# Les deux sont acceptées, ensemble ou séparément. Quand les deux sont
# fournies, les diagnostics sont distincts :
#   INEXISTANT                   nommé, absent du serveur -> l'outil n'existe pas
#   ABSENT DE LA SURFACE CLIENT  exposé par le serveur, hors liste du client
#                                -> inappelable ici et maintenant, sans que rien
#                                   ne soit cassé côté serveur
# Fournir la seule liste serveur reste permis, mais ne prouve PAS
# l'exécutabilité : le script le dit alors explicitement, il ne le tait pas.
#
# Aucune liste n'est gravée ici, aucun cardinal n'est attendu : le nombre
# d'outils change au fil des versions. La comparaison porte sur des ensembles
# de NOMS.
#
# Obtenir la liste SERVEUR : appeler la méthode MCP `tools/list` et extraire
# `.result.tools[].name` — ou utiliser tests/smoke/mcp-tools-live.sh, qui fait
# exactement cela puis enchaîne sur ce vérificateur.
#
# Obtenir la liste CLIENT : elle dépend du client, pas du serveur. Toute source
# qui énumère les outils que le client offre effectivement convient — inventaire
# d'outils de la session d'agent, sortie de la commande d'inspection MCP du
# client, ou liste tenue à la main. Un nom par ligne.
#
# Format des listes : un nom par ligne. Lignes vides et commentaires `#`
# ignorés. Les deux écritures sont acceptées et normalisées : `vault_search` et
# `mcp__<serveur>__vault_search` (le préfixe porte l'alias du serveur, propre à
# la configuration du consommateur).
#
# Usage :
#   bash tests/verify-mcp-tools.sh --tools serveur.txt
#   bash tests/verify-mcp-tools.sh --client-tools client.txt
#   bash tests/verify-mcp-tools.sh --tools serveur.txt --client-tools client.txt
#   <producteur-de-liste> | bash tests/verify-mcp-tools.sh
#   bash tests/verify-mcp-tools.sh --skills-dir autre/skills --tools liste.txt
#
# Exit : 0 = tous les outils nommés sont appelables, 1 = au moins un ne l'est
#        pas, ou contrôle vide (voir gardes anti-vacuité).

set -euo pipefail

SKILLS_DIR=""
TOOLS_FILE=""
CLIENT_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --skills-dir)   SKILLS_DIR="${2:-}"; shift 2 ;;
    --tools)        TOOLS_FILE="${2:-}"; shift 2 ;;
    --client-tools) CLIENT_FILE="${2:-}"; shift 2 ;;
    -h|--help)      sed -n '2,50p' "$0"; exit 0 ;;
    *)              echo "argument inconnu : $1" >&2; exit 2 ;;
  esac
done

if [ -z "$SKILLS_DIR" ]; then
  SKILLS_DIR="$(cd "$(dirname "$0")/.." && pwd)/skills"
fi

normalise() {
  # Retire commentaires, blancs et le préfixe d'alias serveur `mcp__<srv>__`.
  # `|| true` : une entrée sans aucune ligne utile n'est pas une erreur, c'est
  # une liste vide — que les gardes anti-vacuité traitent explicitement.
  sed -e 's/#.*//' -e 's/[[:space:]]//g' \
    | { grep -v '^$' || true; } \
    | sed -e 's/^mcp__[A-Za-z0-9_-]*__//' \
    | sort -u
}

lire_liste() {
  # $1 = chemin de fichier ; chaîne vide -> lecture de stdin
  if [ -n "$1" ]; then
    [ -f "$1" ] || { echo "FAIL — fichier de liste introuvable : $1" >&2; exit 1; }
    normalise < "$1"
  else
    normalise
  fi
}

if [ -n "$CLIENT_FILE" ]; then
  CLIENT=$(lire_liste "$CLIENT_FILE")
else
  CLIENT=""
fi

# Lecture de stdin : règle STRUCTURELLE, jamais une heuristique sur la nature du
# descripteur. Un test du genre `[ ! -t 0 ]` paraît suffire et ne suffit pas —
# stdin peut n'être ni un terminal, ni jamais alimenté (bats, cron, service),
# auquel cas la lecture attend sans fin et sans message. Mesuré : blocage
# indéfini d'un test bats, non déterministe d'un run à l'autre.
#
# Donc : stdin n'est lu QUE si aucune liste n'a été nommée en argument. Un
# appelant qui veut combiner un flux serveur et une surface client écrit le flux
# dans un fichier et le passe par --tools (cf. tests/smoke/mcp-tools-live.sh).
if [ -n "$TOOLS_FILE" ]; then
  EXPOSED=$(lire_liste "$TOOLS_FILE")
elif [ -z "$CLIENT_FILE" ]; then
  EXPOSED=$(lire_liste "")
else
  EXPOSED=""
fi

echo "=== Atteignabilité des outils MCP ==="
echo "Skills : $SKILLS_DIR"
echo ""

# Garde anti-vacuité 1 — sans aucune surface de référence, le contrôle n'a pas
# d'objet. Ni la liste serveur ni la liste client ne sont individuellement
# obligatoires ; leur absence conjointe, si.
if [ -z "$EXPOSED" ] && [ -z "$CLIENT" ]; then
  echo "FAIL — aucune liste d'outils fournie (ni serveur ni client) : le contrôle serait sans objet" >&2
  exit 1
fi

[ -d "$SKILLS_DIR" ] || { echo "FAIL — répertoire de skills absent : $SKILLS_DIR" >&2; exit 1; }

SKILL_FILES=$(find "$SKILLS_DIR" -name 'SKILL.md' -type f | sort)

# Garde anti-vacuité 2 — aucun SKILL.md scanné.
if [ -z "$SKILL_FILES" ]; then
  echo "FAIL — aucun SKILL.md sous $SKILLS_DIR : le contrôle serait vide" >&2
  exit 1
fi

REFERENCED=$(printf '%s\n' "$SKILL_FILES" | xargs grep -ho 'mcp__[A-Za-z0-9_-]*__[A-Za-z0-9_]*' \
  | sed 's/^mcp__[A-Za-z0-9_-]*__//' | sort -u)

# Garde anti-vacuité 3 — des skills, mais aucun outil nommé : un contrôle qui
# passe parce qu'il n'a rien trouvé est un contrôle qui ment.
if [ -z "$REFERENCED" ]; then
  echo "FAIL — aucun outil MCP nommé dans les SKILL.md : le contrôle serait vide" >&2
  exit 1
fi

if [ -n "$EXPOSED" ]; then
  echo "Surface SERVEUR (tools/list)   : $(printf '%s\n' "$EXPOSED" | wc -l) outil(s)"
else
  echo "Surface SERVEUR                : NON MESURÉE"
fi
if [ -n "$CLIENT" ]; then
  echo "Surface CLIENT (exécutabilité) : $(printf '%s\n' "$CLIENT" | wc -l) outil(s)"
else
  echo "Surface CLIENT                 : NON MESURÉE"
fi
echo "Outils nommés par les skills   : $(printf '%s\n' "$REFERENCED" | wc -l)"
echo ""

# Avertissement explicite plutôt que silence : sans surface client, ce contrôle
# établit l'existence côté serveur, pas la capacité d'appeler. Un garde-fou qui
# ne dit pas ce qu'il n'a pas vérifié équivaut à un silence.
if [ -z "$CLIENT" ]; then
  echo "AVERTISSEMENT — surface client non fournie (--client-tools)." >&2
  echo "                Ce contrôle prouve l'EXISTENCE côté serveur, pas l'EXÉCUTABILITÉ :" >&2
  echo "                la liste d'outils d'un client est figée à sa connexion." >&2
  echo "" >&2
fi

est_dans() { printf '%s\n' "$2" | grep -qxF -- "$1"; }

nomme_par() {
  printf '%s\n' "$SKILL_FILES" | while read -r f; do
    if grep -q "mcp__[A-Za-z0-9_-]*__$1\\b" "$f"; then
      echo "         nommé par ${f#"$SKILLS_DIR"/}" >&2
    fi
  done
}

FAIL=0
for t in $REFERENCED; do
  if [ -n "$EXPOSED" ] && ! est_dans "$t" "$EXPOSED"; then
    echo "  [FAIL] $t — INEXISTANT : absent de la surface serveur" >&2
    nomme_par "$t"
    FAIL=$((FAIL + 1))
  elif [ -n "$CLIENT" ] && ! est_dans "$t" "$CLIENT"; then
    if [ -n "$EXPOSED" ]; then
      echo "  [FAIL] $t — ABSENT DE LA SURFACE CLIENT : exposé par le serveur, hors liste du client" >&2
      echo "         => inappelable par ce client ; rien n'est cassé côté serveur" >&2
    else
      echo "  [FAIL] $t — ABSENT DE LA SURFACE CLIENT" >&2
    fi
    nomme_par "$t"
    FAIL=$((FAIL + 1))
  else
    echo "  [PASS] $t"
  fi
done

echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "FAIL — $FAIL outil(s) nommé(s) mais non appelable(s)" >&2
  exit 1
fi

if [ -n "$CLIENT" ]; then
  echo "PASS — tous les outils nommés sont appelables par le client"
else
  echo "PASS — tous les outils nommés existent côté serveur (exécutabilité client NON vérifiée)"
fi
