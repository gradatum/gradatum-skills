#!/usr/bin/env bats
# vault-search.bats — Tests unitaires pour skills/gradatum-vault-search/
#
# Prérequis : bats-core >= 1.9.0
# Exécution : bats tests/bats/vault-search.bats
#             cd tests/bats && bats vault-search.bats

SKILL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/skills/gradatum-vault-search"
SCRIPT="$SKILL_DIR/scripts/search.sh"
SKILL_MD="$SKILL_DIR/SKILL.md"

# ---------------------------------------------------------------------------
# Structure SKILL.md
# ---------------------------------------------------------------------------

@test "SKILL.md existe dans gradatum-vault-search" {
  [ -f "$SKILL_MD" ]
}

@test "SKILL.md contient le frontmatter YAML (---)" {
  run grep -c "^---" "$SKILL_MD"
  [ "$status" -eq 0 ]
  # Au moins 2 occurrences (ouverture + fermeture du frontmatter)
  [ "$output" -ge 2 ]
}

@test "SKILL.md contient le champ 'name'" {
  grep -q "^name:" "$SKILL_MD"
}

@test "SKILL.md contient le champ 'description'" {
  grep -q "^description:" "$SKILL_MD"
}

@test "SKILL.md contient la valeur 'gradatum-vault-search' pour 'name'" {
  grep -q "^name: gradatum-vault-search" "$SKILL_MD"
}

@test "SKILL.md contient la section '## Quand invoquer'" {
  grep -q "^## Quand invoquer" "$SKILL_MD"
}

@test "SKILL.md contient la section '## Output format'" {
  grep -q "^## Output format" "$SKILL_MD"
}

@test "SKILL.md contient la section '## Erreurs'" {
  grep -q "^## Erreurs" "$SKILL_MD"
}

@test "SKILL.md ne contient pas de référence à vault-mem (gradatum est primary)" {
  # vault-mem ne doit pas apparaître comme fallback dans ce skill
  # (peut apparaître dans un commentaire historique — on vérifie 'fallback.*vault-mem')
  run grep -i "fallback.*vault-mem" "$SKILL_MD"
  [ "$status" -ne 0 ]
}

@test "SKILL.md contient la mention 'mcp__gradatum__vault_read'" {
  grep -q "mcp__gradatum__vault_read" "$SKILL_MD"
}

# ---------------------------------------------------------------------------
# Structure script search.sh
# ---------------------------------------------------------------------------

@test "scripts/search.sh existe" {
  [ -f "$SCRIPT" ]
}

@test "scripts/search.sh est exécutable" {
  [ -x "$SCRIPT" ]
}

@test "scripts/search.sh commence par un shebang bash" {
  run head -1 "$SCRIPT"
  [[ "$output" == "#!/usr/bin/env bash" ]]
}

@test "scripts/search.sh contient 'set -euo pipefail'" {
  grep -q "set -euo pipefail" "$SCRIPT"
}

@test "scripts/search.sh retourne une erreur sans argument" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "scripts/search.sh contient la gestion de GRADATUM_SERVER_URL" {
  grep -q "GRADATUM_SERVER_URL" "$SCRIPT"
}

@test "scripts/search.sh contient la gestion de GRADATUM_API_KEY_FILE" {
  grep -q "GRADATUM_API_KEY_FILE" "$SCRIPT"
}

@test "scripts/search.sh contient l'échange JWT (/auth/exchange)" {
  grep -q "/auth/exchange" "$SCRIPT"
}

@test "scripts/search.sh contient l'appel vault_search (/api/v1/vault_search)" {
  grep -q "/api/v1/vault_search" "$SCRIPT"
}

@test "scripts/search.sh contient la signature de sortie '🧠'" {
  grep -q "🧠" "$SCRIPT"
}

@test "scripts/search.sh échoue proprement si le fichier API key est absent" {
  run env GRADATUM_API_KEY_FILE="/tmp/inexistant_gradatum_key_$$" bash "$SCRIPT" "test"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Erreur" || "$stderr" =~ "Erreur" ]]
}

# ---------------------------------------------------------------------------
# Contenu SKILL.md — anti-leak Apache-2.0
# ---------------------------------------------------------------------------

@test "SKILL.md ne contient pas d'adresse email personnelle" {
  run grep -i "@gmail\|@yahoo\|@hotmail" "$SKILL_MD"
  [ "$status" -ne 0 ]
}

@test "SKILL.md ne contient pas de nom d'hôte interne sensible (<inference-host>, 192.168)" {
  run grep -E "<inference-host>|192\.168\." "$SKILL_MD"
  [ "$status" -ne 0 ]
}
