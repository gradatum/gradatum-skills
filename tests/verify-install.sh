#!/usr/bin/env bash
# verify-install.sh — Conformité d'installation (lot 4c-1).
#
# Propriété vérifiée : pour CHAQUE skill déclaré au manifeste de la référence,
# la copie installée est identique à la référence commitée. Un skill manquant,
# un fichier modifié sur place ou un fichier ajouté dans la copie sont des écarts.
#
# La liste des skills vient du manifeste, jamais d'un balayage du répertoire
# d'installation — un skill étranger au produit n'est ni vérifié ni signalé.
#
# Usage : bash tests/verify-install.sh
# Exit  : 0 = toutes les copies conformes, 1 = au moins un écart
#
# Variables d'environnement :
#   GRADATUM_SKILLS_REPO  (défaut : répertoire courant)
#   CLAUDE_SKILLS_DIR     (défaut : $HOME/.claude/skills)
#   GRADATUM_SKILLS_REF   (défaut : HEAD)

set -euo pipefail

REPO="${GRADATUM_SKILLS_REPO:-$PWD}"
DEST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
REF="${GRADATUM_SKILLS_REF:-HEAD}"

PASS=0
FAIL=0

fail() {
  echo "  [FAIL] $1" >&2
  [ -n "${2:-}" ] && echo "         $2" >&2
  FAIL=$((FAIL + 1))
}

echo "=== Conformité d'installation ==="
echo "Référence   : $REF"
echo "Installation: $DEST"
echo ""

if [ ! -d "$REPO/.git" ] && ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  echo "FAIL — $REPO n'est pas un dépôt git" >&2
  exit 1
fi

# Lecture du manifeste de la référence, autorité unique pour la liste des skills.
# Étape séparée de l'extraction : un manifeste absent et un manifeste illisible
# ne se diagnostiquent pas de la même façon.
if ! MANIFEST_JSON=$(git -C "$REPO" show "$REF:.claude-plugin/plugin.json" 2>/dev/null); then
  echo "FAIL — .claude-plugin/plugin.json introuvable à la référence $REF" >&2
  exit 1
fi

# `|| WANTED=""` est LOAD-BEARING : sous `set -euo pipefail`, un `grep` qui ne
# matche rien fait échouer la substitution et abandonne le script AVANT la garde
# anti-vacuité ci-dessous — laquelle serait alors du code mort, et l'échec muet.
# Mesuré : entrées du manifeste sans préfixe `./` -> exit 1, zéro diagnostic.
WANTED=$(printf '%s\n' "$MANIFEST_JSON" \
  | awk '/"skills"[[:space:]]*:/{f=1} f{print} f && /\]/{exit}' \
  | grep -o '"\./skills/[^"/]*"' | tr -d '"' | sed 's|^\./skills/||' | sort -u) || WANTED=""

# Garde anti-vacuité : un manifeste illisible rendrait ce contrôle vert sans
# avoir rien vérifié. Le cardinal n'est pas gravé — seule la non-vacuité l'est.
if [ -z "$WANTED" ]; then
  echo "FAIL — aucun skill lisible au champ \"skills\" du manifeste de $REF" >&2
  echo "       le contrôle serait vide : rien n'aurait été comparé" >&2
  echo "       forme attendue pour chaque entrée : \"./skills/<nom>\"" >&2
  echo "       (une entrée sans le préfixe \`./\` n'est reconnue ni ici ni par le chargeur)" >&2
  exit 1
fi

if [ ! -d "$DEST" ]; then
  echo "FAIL — répertoire d'installation absent : $DEST" >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Extraction de la référence, une seule fois pour tous les skills.
set --
for s in $WANTED; do set -- "$@" "skills/$s"; done
git -C "$REPO" archive "$REF" "$@" | tar -x --strip-components=1 -C "$TMP"

for s in $WANTED; do
  if [ ! -d "$DEST/$s" ]; then
    fail "$s : absent de l'installation"
    continue
  fi
  if [ -L "$DEST/$s" ]; then
    fail "$s : lien symbolique (l'installation doit être une copie figée)"
    continue
  fi
  if DIFF=$(diff -r "$TMP/$s" "$DEST/$s" 2>&1); then
    echo "  [PASS] $s"
    PASS=$((PASS + 1))
  else
    fail "$s : diverge de la référence" "$(printf '%s' "$DIFF" | head -20)"
  fi
done

echo ""
echo "=== RÉSULTAT : $PASS conforme(s) / $FAIL écart(s) ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
echo "PASS — l'installation reflète $REF"
