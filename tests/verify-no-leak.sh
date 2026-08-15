#!/usr/bin/env bash
# verify-no-leak.sh — Absence de contexte privé sur TOUTE la surface publiée.
#
# Pourquoi ce fichier existe. Le contrôle anti-fuite vivait dans deux fichiers `bats`
# attachés chacun à UN skill : 8 skills sur 10 n'étaient scannés par rien. Un port
# interne a traversé cette lacune jusque dans le champ `description` de quatre skills —
# le champ le plus visible d'un plugin. La couverture partielle donnait l'illusion d'un
# contrôle : les tests passaient, la fuite était là.
#
# Pourquoi il a été réécrit. Sa première version ajoutait bien l'historique, mais avec
# une expression PROPRE, plus faible que celle de l'arbre : trois classes sur six y
# manquaient. Le balayage historique était donc aveugle exactement aux classes qui y
# survivaient, et rendait `PASS` sur 25 révisions polluées. Deux définitions séparées
# de la même chose divergent toujours — la seule question est quand.
#
# TROIS RÈGLES DE CONCEPTION, chacune payée par un défaut réel :
#
#   1. UNE SEULE DÉFINITION DES CLASSES, appliquée à toutes les surfaces. C'est
#      l'invariant central de ce fichier : une classe ajoutée ci-dessous couvre
#      immédiatement l'arbre, l'historique et les messages. Il n'existe aucun endroit
#      où en redéclarer une.
#
#   2. UNE SURFACE, UN BALAYAGE. La liste des fichiers se dérive de l'inventaire
#      versionné, jamais d'une liste tenue à la main — une liste oubliée reproduit
#      exactement la lacune qu'elle prétend fermer.
#
#   3. DES MOTIFS DE CLASSE, JAMAIS DE VALEUR. Un test qui énumère les identifiants
#      qu'il protège les publie : le motif devient la fuite. On cherche des FORMES
#      (plage d'adresses privée, port de service, chemin personnel, forme de secret),
#      jamais un nom réel. Les listes nominatives restent hors de ce dépôt.
#
# LIMITE ASSUMÉE, à ne pas prétendre couvrir : un **nom propre nu** n'a pas de forme.
# Aucune expression régulière ne le distingue d'un mot ordinaire, et l'énumérer ici
# violerait la règle 3. Cette classe relève d'un contrôle privé, hors du dépôt qu'il
# protège — un test qui vit dans le dépôt qu'il défend est condamné soit à être
# aveugle, soit à se trahir.
#
# Sortie : 0 si toutes les surfaces sont propres, 1 sinon, avec l'emplacement des hits.

set -u

cd "$(dirname "$0")/.." || exit 1

# ═══════════════════════════════════════════════════════════════════════════════
# LES CLASSES — source unique. Format : libellé | motif (PCRE).
# Toute classe ajoutée ici est appliquée aux trois surfaces sans autre geste.
# ═══════════════════════════════════════════════════════════════════════════════
classes() {
  cat <<'CLASSES'
adresse IP privée (RFC1918, les trois plages)|\b10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b|\b172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}\b|\b192\.168\.[0-9]{1,3}\.[0-9]{1,3}\b
port de service (hôte nommé ou port nu)|(localhost|127\.0\.0\.1|0\.0\.0\.0):[0-9]+|[ (]:[0-9]{4,5}\b
chemin de répertoire personnel|/home/[a-z_][a-z0-9_-]*/|/Users/[a-zA-Z]
adresse e-mail|\b(?!noreply@)(?!no-reply@)[a-zA-Z0-9._%+-]+@(?!example\.(com|org|net|invalid))(?!users\.noreply\.)[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}
secret de forme connue|sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{12,}|ak_[0-9a-f]{8,}|-----BEGIN [A-Z ]*PRIVATE KEY-----
référence à une gouvernance non définie dans ce dépôt|NOMENCLATURE|CONSTITUTION|council Art\.|Art\.1[5-9]|gov-[a-z-]+|safety-[a-z-]+
CLASSES
}
# Notes sur deux exclusions délibérées, pour qu'un lecteur ne les prenne pas pour des trous :
#   - `~/.claude/` est le chemin STANDARD du harnais, pas un chemin personnel : l'inclure
#     ferait crier le contrôle sur de la documentation légitime, et un contrôle qui crie
#     au loup finit ignoré.
#   - `example.com/.org/.net/.invalid` sont réservés par la RFC 2606 pour la documentation
#     et les tests : ce ne sont pas des adresses réelles.
#   - `noreply@` / `no-reply@` sont une convention réservée (co-auteur, bots de forge).
#     L'exclusion est ancrée par `\b` : sans elle, l'expression démarrerait au milieu du
#     mot (« oreply@… ») et la négation, n'ayant plus rien devant elle, passerait à vide.

# Le libellé est avant le premier `|`, le motif est tout ce qui suit — les motifs
# contiennent eux-mêmes des alternances, d'où le découpage sur le PREMIER séparateur.
libelle() { printf '%s' "${1%%|*}"; }
motif()   { printf '%s' "${1#*|}"; }

fail=0

# ═══ Surface 1 — arbre courant ═══════════════════════════════════════════════
# Fichiers hors périmètre, sur TOUTES les surfaces : la licence (texte tiers) et ce
# fichier lui-même (il contient ses propres motifs — les compter serait absurde). La
# même exclusion s'applique à l'arbre ET à l'historique : une exclusion valable ici et
# pas là recrée exactement l'incohérence que ce script existe pour empêcher.
EXCLUS='^(LICENSE|tests/verify-no-leak\.sh)$'
EXCLUS_HIST=':(exclude)LICENSE :(exclude)tests/verify-no-leak.sh'
FILES=$(git ls-files 2>/dev/null | grep -vE "$EXCLUS")
if [ -z "$FILES" ]; then
  echo "FAIL — aucun fichier versionné trouvé : le contrôle serait sans objet" >&2
  exit 1
fi

echo "=== Arbre courant — $(printf '%s\n' "$FILES" | wc -l) fichier(s) versionné(s) ==="
while IFS= read -r c; do
  [ -n "$c" ] || continue
  hits=$(printf '%s\n' "$FILES" | xargs -r grep -nPI "$(motif "$c")" 2>/dev/null)
  if [ -n "$hits" ]; then
    echo "[FUITE] $(libelle "$c")"; printf '%s\n' "$hits" | head -20 | sed 's/^/    /'; fail=1
  else
    echo "[  OK  ] $(libelle "$c")"
  fi
done <<< "$(classes)"

# ═══ Surfaces 2 et 3 — l'historique est publié lui aussi ═════════════════════
#
# Un fichier assaini dans l'arbre reste lisible dans le commit qui le portait avant.
# Pousser une branche publie tous ses ancêtres : nettoyer HEAD ne nettoie rien. Et une
# réécriture d'identité d'auteur ne touche NI le contenu des révisions, NI les messages
# — trois surfaces distinctes, trois nettoyages distincts.

echo
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "=== Historique — [ SKIP ] pas un dépôt git ==="
else
  REVS=$(git rev-list HEAD 2>/dev/null)
  NREV=$(printf '%s\n' "$REVS" | grep -c . || echo 0)
  echo "=== Historique — $NREV révision(s) + leurs messages ==="

  while IFS= read -r c; do
    [ -n "$c" ] || continue
    lab=$(libelle "$c"); pat=$(motif "$c")

    # Contenu de chaque révision. `git grep` accepte plusieurs révisions en une passe :
    # une invocation par classe, pas une par (classe × révision).
    rev_hits=$(git grep -nPI "$pat" $REVS -- . $EXCLUS_HIST 2>/dev/null | head -10)
    # Messages de commit — jamais couverts par une réécriture d'identité.
    msg_hits=$(git log --format='%H %s%n%b' 2>/dev/null | grep -nPI "$pat" 2>/dev/null | head -10)

    if [ -n "$rev_hits$msg_hits" ]; then
      echo "[FUITE] $lab"
      [ -n "$rev_hits" ] && printf '%s\n' "$rev_hits" | sed 's/^/    révision: /'
      [ -n "$msg_hits" ] && printf '%s\n' "$msg_hits" | sed 's/^/    message : /'
      fail=1
    else
      echo "[  OK  ] $lab"
    fi
  done <<< "$(classes)"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — aucune classe de contexte privé, ni dans l'arbre, ni dans les révisions, ni dans les messages"
  exit 0
fi
echo "FAIL — au moins une classe trouvée ; corriger AVANT tout tag public (surface figée par version)" >&2
exit 1
