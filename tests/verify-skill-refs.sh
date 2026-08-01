#!/usr/bin/env bash
# verify-skill-refs.sh — Atteignabilité des SKILLS nommés (symétrique de verify-mcp-tools.sh).
#
# verify-mcp-tools.sh vérifie que chaque OUTIL MCP nommé est appelable. Ce
# script vérifie la propriété jumelle, jusqu'ici non couverte : chaque SKILL
# nommé sous la forme `/nom-de-skill` existe réellement.
#
# DEUX DÉFAUTS DISTINCTS sont recherchés, et rendus par des diagnostics
# différents :
#
#   SKILL INEXISTANT      un `/nom` qui ne correspond à aucun skill, ni dans le
#                         produit ni dans l'environnement du consommateur.
#                         Le lecteur est envoyé vers du vide.
#
#   DÉPENDANCE INVERSÉE   un SKILL.md du PRODUIT nomme un skill qui n'appartient
#                         pas au produit. Le produit est distribué seul : ce
#                         `/nom` est mort chez tout consommateur externe, même
#                         s'il résout parfaitement sur la machine d'origine.
#                         Le sens autorisé est local -> produit, jamais
#                         l'inverse.
#
# Le second est indétectable sans savoir quels skills existent HORS produit :
# fournir `--known-skills` fait la différence entre « ce nom existe ailleurs »
# et « ce nom n'existe nulle part ». Sans ce fichier, les deux cas restent
# fautifs et sont signalés, mais sous un diagnostic unique et dégradé — dit
# explicitement, jamais tu.
#
# Aucune liste de skills n'est gravée : l'ensemble du produit est DÉRIVÉ des
# répertoires présents sous `--skills-dir` à l'exécution.
#
# Usage :
#   bash tests/verify-skill-refs.sh
#   bash tests/verify-skill-refs.sh --known-skills environnement.txt
#   bash tests/verify-skill-refs.sh --hooks-dir DIR --known-skills environnement.txt
#   bash tests/verify-skill-refs.sh --skills-dir autre/skills --ignore jeton1,jeton2
#
# Exit : 0 = toute référence résout dans le bon sens, 1 = au moins un écart,
#        ou contrôle vide (voir gardes anti-vacuité).

set -euo pipefail

SKILLS_DIR=""
HOOKS_DIR=""
KNOWN_FILE=""
IGNORE_EXTRA=""

# Jetons qui ont la FORME d'une invocation de skill sans en être une. Chacun
# porte sa raison ; la liste est imprimée à chaque exécution pour qu'elle ne
# puisse pas grossir en silence, et un jeton qui serait AUSSI un skill du
# produit fait échouer le contrôle (interdit d'éteindre une vraie vérification).
#   mcp — chemin de l'endpoint HTTP du serveur (`/mcp`), pas une commande
IGNORE_DEFAUT="mcp"

while [ $# -gt 0 ]; do
  case "$1" in
    --skills-dir)   SKILLS_DIR="${2:-}"; shift 2 ;;
    --hooks-dir)    HOOKS_DIR="${2:-}"; shift 2 ;;
    --known-skills) KNOWN_FILE="${2:-}"; shift 2 ;;
    --ignore)       IGNORE_EXTRA="${2:-}"; shift 2 ;;
    -h|--help)      sed -n '2,44p' "$0"; exit 0 ;;
    *)              echo "argument inconnu : $1" >&2; exit 2 ;;
  esac
done

if [ -z "$SKILLS_DIR" ]; then
  SKILLS_DIR="$(cd "$(dirname "$0")/.." && pwd)/skills"
fi

# Un scan de hooks sans référentiel de skills connus ne pourrait rien conclure :
# un hook a le droit de nommer un skill local. Le refus est explicite plutôt que
# de rendre un contrôle vert et vide.
if [ -n "$HOOKS_DIR" ] && [ -z "$KNOWN_FILE" ]; then
  echo "FAIL — --hooks-dir exige --known-skills : un hook peut légitimement nommer" >&2
  echo "       un skill local ; sans référentiel, le contrôle serait sans pouvoir." >&2
  exit 2
fi

# Caractère admis juste avant le « / » d'une invocation. Liste blanche : tout
# ce qui n'y figure pas écarte le candidat. Écarte ainsi les chemins
# (`/etc/x`), les URL (`https://hote/mcp`), les balises fermantes
# (`</details>`) et les coupes françaises (`décidé/changé`).
PREFIX_OK="[[:space:]([«\"\`*,]"

extraire_refs() {
  # $1 = fichier. Sortie : un nom de skill par ligne, dédoublonné.
  # Le `/?` final capture le séparateur suivant afin d'écarter les chemins :
  # une invocation de skill n'est jamais suivie d'un `/`.
  grep -ohE "(^|$PREFIX_OK)/[a-z][a-z0-9-]*/?" "$1" 2>/dev/null \
    | sed -E 's|^[^/]+||' \
    | grep -v '/$' \
    | sed 's|^/||' \
    | sort -u || true
}

est_dans() { printf '%s\n' "$2" | grep -qxF -- "$1"; }

echo "=== Atteignabilité des skills nommés ==="
echo "Skills produit : $SKILLS_DIR"
[ -n "$HOOKS_DIR" ] && echo "Hooks          : $HOOKS_DIR"
echo ""

[ -d "$SKILLS_DIR" ] || { echo "FAIL — répertoire de skills absent : $SKILLS_DIR" >&2; exit 1; }

PRODUIT=$(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | sed 's|.*/||' | sort -u)

# Garde anti-vacuité 1 — aucun skill produit : rien à opposer aux références.
if [ -z "$PRODUIT" ]; then
  echo "FAIL — aucun répertoire de skill sous $SKILLS_DIR : le contrôle serait vide" >&2
  exit 1
fi

FICHIERS=$(find "$SKILLS_DIR" -name 'SKILL.md' -type f | sort)
if [ -n "$HOOKS_DIR" ]; then
  [ -d "$HOOKS_DIR" ] || { echo "FAIL — répertoire de hooks absent : $HOOKS_DIR" >&2; exit 1; }
  HOOK_FILES=$(find "$HOOKS_DIR" -type f | sort)
  FICHIERS=$(printf '%s\n%s\n' "$FICHIERS" "$HOOK_FILES" | grep -v '^$' | sort -u)
fi

# Garde anti-vacuité 2 — aucun fichier scanné.
if [ -z "$FICHIERS" ]; then
  echo "FAIL — aucun fichier à scanner : le contrôle serait vide" >&2
  exit 1
fi

KNOWN=""
if [ -n "$KNOWN_FILE" ]; then
  [ -f "$KNOWN_FILE" ] || { echo "FAIL — fichier --known-skills introuvable : $KNOWN_FILE" >&2; exit 1; }
  KNOWN=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$KNOWN_FILE" | grep -v '^$' | sort -u || true)
  if [ -z "$KNOWN" ]; then
    echo "FAIL — --known-skills fourni mais vide : le référentiel serait sans objet" >&2
    exit 1
  fi
fi

IGNORE=$(printf '%s\n%s\n' "$IGNORE_DEFAUT" "$(printf '%s' "$IGNORE_EXTRA" | tr ',' '\n')" \
  | grep -v '^$' | sort -u || true)

# Garde d'exemption — un jeton exempté ne doit jamais recouvrir un skill du
# produit, sinon l'exemption éteindrait une vérification réelle.
if [ -n "$IGNORE" ]; then
  echo "Jetons exemptés (forme d'invocation, mais n'en sont pas) :"
  for j in $IGNORE; do
    if est_dans "$j" "$PRODUIT"; then
      echo "" >&2
      echo "FAIL — le jeton exempté « $j » est aussi un skill du produit :" >&2
      echo "       cette exemption éteindrait une vérification réelle." >&2
      exit 1
    fi
    echo "  [IGNORE] /$j"
  done
  echo ""
fi

TOTAL_REFS=0
FAIL=0
PASS=0

for f in $FICHIERS; do
  # Une référence depuis un SKILL.md du produit engage la distribution : le
  # produit part seul. Depuis un hook, seule l'existence est exigée.
  case "$f" in
    "$SKILLS_DIR"/*) ORIGINE="produit" ;;
    *)               ORIGINE="hook" ;;
  esac
  AFFICHE="${f#"$SKILLS_DIR"/}"

  for r in $(extraire_refs "$f"); do
    est_dans "$r" "$IGNORE" && continue
    TOTAL_REFS=$((TOTAL_REFS + 1))

    if est_dans "$r" "$PRODUIT"; then
      PASS=$((PASS + 1))
      continue
    fi

    if [ -n "$KNOWN" ] && est_dans "$r" "$KNOWN"; then
      if [ "$ORIGINE" = "produit" ]; then
        echo "  [FAIL] /$r — DÉPENDANCE INVERSÉE : skill produit -> skill local" >&2
        echo "         nommé par $AFFICHE ; le produit est distribué seul, cette" >&2
        echo "         référence est morte chez un consommateur externe" >&2
        FAIL=$((FAIL + 1))
      else
        PASS=$((PASS + 1))
      fi
      continue
    fi

    if [ -n "$KNOWN" ]; then
      echo "  [FAIL] /$r — SKILL INEXISTANT : ni dans le produit, ni dans l'environnement" >&2
      echo "         nommé par $AFFICHE" >&2
    else
      echo "  [FAIL] /$r — HORS PRODUIT : skill local ou inexistant" >&2
      echo "         nommé par $AFFICHE" >&2
      echo "         (fournir --known-skills pour trancher entre les deux)" >&2
    fi
    FAIL=$((FAIL + 1))
  done
done

# Garde anti-vacuité 3 — des fichiers, mais aucune référence trouvée : un
# contrôle vert faute d'avoir rien vu est un contrôle qui ment.
if [ "$TOTAL_REFS" -eq 0 ]; then
  echo "FAIL — aucune référence /skill trouvée dans les fichiers scannés : le contrôle serait vide" >&2
  exit 1
fi

echo ""
echo "=== RÉSULTAT : $PASS référence(s) conforme(s) / $FAIL écart(s) sur $TOTAL_REFS ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
echo "PASS — toute référence /skill résout, et aucune ne descend du produit vers le local"
