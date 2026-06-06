#!/usr/bin/env bats
# skill-reminder.bats — Tests unitaires pour skills/gradatum-skill-reminder/
#
# Prérequis : bats-core >= 1.9.0
# Exécution : bats tests/bats/skill-reminder.bats
#             cd tests/bats && bats skill-reminder.bats

SKILL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/skills/gradatum-skill-reminder"
SKILL_MD="$SKILL_DIR/SKILL.md"

# ---------------------------------------------------------------------------
# Structure SKILL.md
# ---------------------------------------------------------------------------

@test "SKILL.md existe dans gradatum-skill-reminder" {
  [ -f "$SKILL_MD" ]
}

@test "SKILL.md contient le frontmatter YAML (---)" {
  run grep -c "^---" "$SKILL_MD"
  [ "$status" -eq 0 ]
  [ "$output" -ge 2 ]
}

@test "SKILL.md contient le champ 'name'" {
  grep -q "^name:" "$SKILL_MD"
}

@test "SKILL.md contient le champ 'description'" {
  grep -q "^description:" "$SKILL_MD"
}

@test "SKILL.md contient la valeur 'gradatum-skill-reminder' pour 'name'" {
  grep -q "^name: gradatum-skill-reminder" "$SKILL_MD"
}

@test "SKILL.md contient la section de décision CHERCHE" {
  grep -q "CHERCHE" "$SKILL_MD"
}

@test "SKILL.md contient la section de décision SKIP" {
  grep -q "SKIP" "$SKILL_MD"
}

@test "SKILL.md mentionne la délégation à /gradatum-vault-search" {
  grep -q "gradatum-vault-search" "$SKILL_MD"
}

@test "SKILL.md contient la liste des 11 sections canoniques" {
  # Vérifier la présence de quelques sections canoniques clés
  grep -q "decisions" "$SKILL_MD"
  grep -q "council" "$SKILL_MD"
  grep -q "lessons-learned" "$SKILL_MD"
  grep -q "architecture" "$SKILL_MD"
  grep -q "retrospectives" "$SKILL_MD"
}

@test "SKILL.md contient la convention de titre vault" {
  grep -q "CATÉGORIE" "$SKILL_MD"
}

@test "SKILL.md mentionne le caractère stateless" {
  grep -qi "stateless" "$SKILL_MD"
}

@test "SKILL.md mentionne les anti-patterns" {
  grep -q "Anti-patterns\|anti-pattern" "$SKILL_MD"
}

# ---------------------------------------------------------------------------
# Cohérence avec L0 (pas de duplication de responsabilité)
# ---------------------------------------------------------------------------

@test "SKILL.md de L1 ne contient pas de code bash ni de curl" {
  # L1 est pure logique de décision — pas de scripts
  run grep -E "^#!/|curl |jq " "$SKILL_MD"
  [ "$status" -ne 0 ]
}

@test "SKILL.md de L1 ne contient pas de référence à /auth/exchange (transport L0)" {
  run grep "/auth/exchange" "$SKILL_MD"
  [ "$status" -ne 0 ]
}

@test "SKILL.md de L1 ne contient pas de référence à /api/v1/vault_search directe" {
  # La recherche est déléguée à L0, pas appelée directement depuis L1
  run grep "/api/v1/vault_search" "$SKILL_MD"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Contenu SKILL.md — anti-leak Apache-2.0
# ---------------------------------------------------------------------------

@test "SKILL.md ne contient pas d'adresse email personnelle" {
  run grep -i "@gmail\|@yahoo\|@hotmail" "$SKILL_MD"
  [ "$status" -ne 0 ]
}

@test "SKILL.md ne contient pas de nom d'hôte interne sensible" {
  run grep -E "<inference-host>|192\.168\." "$SKILL_MD"
  [ "$status" -ne 0 ]
}

@test "SKILL.md ne contient pas d'identité opérateur sensible" {
  run grep -iE "Maintainers|maintainer|<container>|<forge>|the operator|the operator|maintainer" "$SKILL_MD"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Logique de décision SKIP — vérification des cas documentés
# ---------------------------------------------------------------------------

@test "SKILL.md documente le cas SKIP pour validation seule ('oui', 'go')" {
  grep -q '"oui"' "$SKILL_MD" || grep -q '"go"' "$SKILL_MD"
}

@test "SKILL.md documente le cas SKIP pour slash-command" {
  grep -qi "slash" "$SKILL_MD" || grep -q "^/\.\.\." "$SKILL_MD" || grep -q "Slash" "$SKILL_MD"
}

@test "SKILL.md documente le cas SKIP pour prompt trivial" {
  grep -qi "trivial" "$SKILL_MD"
}
