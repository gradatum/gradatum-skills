#!/usr/bin/env bash
# verify-no-leak.sh — Absence de contexte privé sur TOUTE la surface publiée.
#
# Pourquoi ce fichier existe. Le contrôle anti-fuite vivait dans deux fichiers `bats`
# attachés chacun à UN skill : 8 skills sur 10 n'étaient scannés par rien. Un port
# interne a traversé cette lacune jusque dans le champ `description` de quatre skills —
# le champ le plus visible d'un plugin, celui qu'affiche tout listing. La couverture
# partielle donnait l'illusion d'un contrôle : les tests passaient, la fuite était là.
#
# Deux règles de conception, apprises à ses dépens :
#
#   1. UNE surface, UN balayage. Ce script scanne tout ce qui est versionné, sans liste
#      de fichiers à tenir à jour — une liste oubliée reproduit exactement la lacune
#      qu'elle prétend fermer.
#
#   2. Des motifs de CLASSE, jamais de valeur. Un test qui énumère les identifiants
#      qu'il protège les publie : le motif devient la fuite. On cherche donc des
#      FORMES (plage d'adresses privée, port de service, chemin personnel, forme de
#      secret), jamais un nom réel. Les listes nominatives restent côté privé.
#
# Sortie : 0 si la surface est propre, 1 au premier motif trouvé, avec fichier:ligne.

set -u

cd "$(dirname "$0")/.." || exit 1

# Fichiers versionnés uniquement : ce qui n'est pas suivi n'est pas publié — mais on
# n'exclut rien d'autre. Un fichier ajouté demain est couvert sans toucher ce script.
FILES=$(git ls-files 2>/dev/null | grep -vE '^(LICENSE|tests/verify-no-leak\.sh)$')
if [ -z "$FILES" ]; then
  echo "FAIL — aucun fichier versionné trouvé : le contrôle serait sans objet" >&2
  exit 1
fi

fail=0
report() { # $1 = libellé de la classe, $2 = motif
  local hits
  hits=$(printf '%s\n' "$FILES" | xargs -r grep -nPI "$2" 2>/dev/null)
  if [ -n "$hits" ]; then
    echo "[FUITE] $1"
    printf '%s\n' "$hits" | sed 's/^/    /'
    fail=1
  else
    echo "[  OK  ] $1"
  fi
}

echo "=== Absence de contexte privé — surface versionnée ==="
echo "Fichiers scannés : $(printf '%s\n' "$FILES" | wc -l)"
echo

report "adresse IP privée (RFC1918, les trois plages)" \
  '\b10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b|\b172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}\b|\b192\.168\.[0-9]{1,3}\.[0-9]{1,3}\b'

# Un port de service nu suffit à désigner une installation : « (LIVE :19090) » ne nomme
# aucune machine et reste une fuite. Le motif exige 4 ou 5 chiffres précédés d'un espace
# ou d'une parenthèse, ce qui écarte les heures (HH:MM) et les ancres markdown.
report "port de service (hôte nommé ou port nu)" \
  '(localhost|127\.0\.0\.1|0\.0\.0\.0):[0-9]+|[ (]:[0-9]{4,5}\b'

# `~/.claude/` est le chemin STANDARD du harnais, pas un chemin personnel : l'exclure,
# sinon le contrôle crie au loup sur de la documentation légitime et finit ignoré.
report "chemin de répertoire personnel" \
  '/home/[a-z_][a-z0-9_-]*/|/Users/[a-zA-Z]'

# `example.com/.org/.invalid` sont réservés par la RFC 2606 pour la documentation et
# les tests : les exclure, ce ne sont pas des adresses réelles.
report "adresse e-mail" \
  '[a-zA-Z0-9._%+-]+@(?!example\.(com|org|net|invalid))[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'

report "secret de forme connue" \
  'sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{12,}|ak_[0-9a-f]{8,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'

# Un processus de gouvernance que le dépôt ne définit pas est opaque pour un tiers, et
# renseigne sur le fonctionnement privé de qui l'a écrit. Ce n'est pas un secret ; c'est
# du contexte qui n'a rien à faire dans un produit distribué.
report "référence à une gouvernance non définie dans ce dépôt" \
  'NOMENCLATURE|CONSTITUTION|council Art\.|Art\.1[5-9]|gov-[a-z-]+|safety-[a-z-]+'

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — aucune classe de contexte privé trouvée sur la surface versionnée"
  exit 0
fi
echo "FAIL — au moins une classe trouvée ; corriger AVANT tout tag public (surface figée par version)" >&2
exit 1
