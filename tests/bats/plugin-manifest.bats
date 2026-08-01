#!/usr/bin/env bats
# plugin-manifest.bats — Le manifeste déclare EXACTEMENT les répertoires présents (lot 4a).
#
# Contrat testé : `.claude-plugin/plugin.json` et `skills/` ne peuvent pas diverger.
# La suite échoue dans les deux sens — un répertoire non déclaré, une entrée sans
# répertoire. Aucune liste de skills n'est gravée ici : l'attendu est DÉRIVÉ du
# contenu de `skills/` au moment de l'exécution, donc l'arrivée d'un nouveau skill
# ne périme pas ce fichier (elle exige seulement l'entrée correspondante).
#
# Ce contrat couvre un défaut mesuré le 2026-08-01 : un manifeste dont le champ
# `skills` porte des chemins sans préfixe `./` est rejeté par le chargeur, et le
# plugin n'est alors PAS chargé du tout — pas « chargé partiellement ».
#
# Prérequis : bats-core >= 1.9.0
# Exécution : bats tests/bats/plugin-manifest.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
MANIFEST="$REPO_ROOT/.claude-plugin/plugin.json"

load helpers   # skip_bruyant

# Entrées du champ `skills` du manifeste, une par ligne, sans le préfixe ./skills/
manifest_entries() {
  awk '/"skills"[[:space:]]*:/{f=1} f{print} f && /\]/{exit}' "$MANIFEST" \
    | grep -o '"\./skills/[^"/]*"' | tr -d '"' | sed 's|^\./skills/||' | sort
}

# Répertoires réellement présents sous skills/, une par ligne
skill_dirs() {
  find "$REPO_ROOT/skills" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
}


# ---------------------------------------------------------------------------
# Structure du manifeste
# ---------------------------------------------------------------------------

@test "le manifeste .claude-plugin/plugin.json existe" {
  [ -f "$MANIFEST" ]
}

@test "le manifeste est un JSON valide" {
  if ! command -v jq >/dev/null 2>&1; then
    skip_bruyant "le manifeste est un JSON valide" "jq absent"
  fi
  run jq -e . "$MANIFEST"
  [ "$status" -eq 0 ]
}

@test "le champ author est un objet (une chaîne empêche le chargement du plugin)" {
  if ! command -v jq >/dev/null 2>&1; then
    skip_bruyant "author est un objet (une chaîne empêche TOUT chargement du plugin)" "jq absent"
  fi
  run jq -r '.author | type' "$MANIFEST"
  [ "$output" = "object" ]
}

# ---------------------------------------------------------------------------
# Forme des entrées — un chemin sans ./ est rejeté par le chargeur
# ---------------------------------------------------------------------------

@test "toute entrée du champ skills a la forme ./skills/<nom>" {
  if ! command -v jq >/dev/null 2>&1; then
    skip_bruyant "chaque entrée du champ skills a la forme ./skills/<nom>" "jq absent"
  fi
  run jq -r '.skills[]' "$MANIFEST"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  while IFS= read -r entry; do
    [[ "$entry" =~ ^\./skills/[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
      echo "entrée non conforme : $entry" >&2
      return 1
    }
  done <<< "$output"
}

@test "le manifeste ne contient aucune entrée en double" {
  total=$(manifest_entries | wc -l)
  uniques=$(manifest_entries | sort -u | wc -l)
  [ "$total" -eq "$uniques" ]
}

@test "le manifeste déclare au moins un skill (garde anti-vacuité)" {
  # Un manifeste vide rendrait vertes toutes les comparaisons d'ensembles
  # ci-dessous sans rien avoir prouvé. Aucun cardinal n'est gravé — seule la
  # non-vacuité l'est.
  [ "$(manifest_entries | wc -l)" -ge 1 ]
}

# ---------------------------------------------------------------------------
# Égalité manifeste <-> contenu de skills/ (les deux sens)
# ---------------------------------------------------------------------------

@test "aucun répertoire de skills/ n'est absent du manifeste" {
  manquants=$(comm -23 <(skill_dirs) <(manifest_entries))
  if [ -n "$manquants" ]; then
    echo "répertoires présents sur disque mais non déclarés :" >&2
    echo "$manquants" >&2
    return 1
  fi
}

@test "aucune entrée du manifeste ne pointe vers un répertoire absent" {
  fantomes=$(comm -13 <(skill_dirs) <(manifest_entries))
  if [ -n "$fantomes" ]; then
    echo "entrées déclarées sans répertoire correspondant :" >&2
    echo "$fantomes" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Chargeabilité de chaque skill déclaré
# ---------------------------------------------------------------------------

@test "chaque skill déclaré porte un SKILL.md" {
  while IFS= read -r s; do
    [ -f "$REPO_ROOT/skills/$s/SKILL.md" ] || {
      echo "SKILL.md manquant pour $s" >&2
      return 1
    }
  done < <(manifest_entries)
}

@test "le champ name du frontmatter correspond au nom du répertoire" {
  # Le nom d'invocation vient du frontmatter ; un écart donnerait un skill
  # installé sous un nom que personne n'appelle.
  while IFS= read -r s; do
    declared=$(sed -n 's/^name:[[:space:]]*//p' "$REPO_ROOT/skills/$s/SKILL.md" | head -1)
    [ "$declared" = "$s" ] || {
      echo "répertoire $s vs frontmatter name '$declared'" >&2
      return 1
    }
  done < <(manifest_entries)
}

# ---------------------------------------------------------------------------
# Validation par l'outil du harnais, quand il est disponible
# ---------------------------------------------------------------------------

@test "le manifeste passe claude plugin validate --strict" {
  # Seul contrôle qui interroge le CHARGEUR lui-même plutôt que la forme du
  # fichier : c'est celui qui a levé le défaut `author` du 2026-08-01. Le sauter
  # en silence rendrait vert le seul test qui comptait.
  if ! command -v claude >/dev/null 2>&1; then
    skip_bruyant "le manifeste est accepté par le chargeur (claude plugin validate --strict)" \
      "CLI claude absente de cet environnement"
  fi
  run claude plugin validate "$REPO_ROOT" --strict
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}
