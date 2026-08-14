#!/usr/bin/env bats
# vault-search.bats — Tests unitaires pour skills/gradatum-vault-search/
#
# Contrat testé : le skill L0 gradatum-vault-search est passé du wrapper shell
# (scripts/search.sh + Bash allowed-tool) à l'outil MCP natif
# `mcp__gradatum__vault_search`. Ces tests attestent le NOUVEAU contrat MCP :
#   - allowed-tools déclare l'outil MCP, plus un wrapper Bash
#   - le SKILL.md référence l'outil MCP
#   - plus aucune trace du script (Bash(, scripts/, env de transport, signature 🧠)
#   - les sections réellement présentes dans le SKILL.md MCP
# Le bloc anti-leak Apache-2.0 (dépôt public) est CONSERVÉ intégralement.
#
# Prérequis : bats-core >= 1.9.0
# Exécution : bats tests/bats/vault-search.bats
#             cd tests/bats && bats vault-search.bats

SKILL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/skills/gradatum-vault-search"
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

# --- Sections réellement présentes dans le contrat MCP (remplacent
#     '## Output format' et '## Erreurs' du contrat shell, absents ici) ---

@test "SKILL.md contient la section '## Anti-patterns'" {
  grep -q "^## Anti-patterns" "$SKILL_MD"
}

@test "SKILL.md contient la section '## Mode compact' (activation compact MCP)" {
  grep -q "^## Mode compact" "$SKILL_MD"
}

@test "SKILL.md ne contient pas de référence à vault-mem (gradatum est primary)" {
  # vault-mem ne doit pas apparaître comme fallback dans ce skill
  run grep -i "fallback.*vault-mem" "$SKILL_MD"
  [ "$status" -ne 0 ]
}

@test "SKILL.md contient la mention 'mcp__gradatum__vault_read'" {
  grep -q "mcp__gradatum__vault_read" "$SKILL_MD"
}

# ---------------------------------------------------------------------------
# Nouveau contrat MCP — l'outil MCP remplace le wrapper shell
# ---------------------------------------------------------------------------

@test "frontmatter allowed-tools déclare l'outil MCP mcp__gradatum__vault_search" {
  grep -qE "^allowed-tools:.*mcp__gradatum__vault_search" "$SKILL_MD"
}

@test "SKILL.md référence l'outil MCP mcp__gradatum__vault_search" {
  grep -q "mcp__gradatum__vault_search" "$SKILL_MD"
}

@test "le répertoire scripts/ du skill a disparu (plus de wrapper shell)" {
  [ ! -d "$SKILL_DIR/scripts" ]
}

@test "SKILL.md ne déclare plus d'allowed-tool Bash(" {
  # Le contrat MCP ne passe plus par un wrapper shell exécuté via Bash(...)
  run grep -F "Bash(" "$SKILL_MD"
  [ "$status" -ne 0 ]
}

@test "SKILL.md ne référence plus de script sous scripts/" {
  run grep -F "scripts/" "$SKILL_MD"
  [ "$status" -ne 0 ]
}

@test "SKILL.md ne contient plus l'env de transport GRADATUM_SERVER_URL" {
  # Le transport (URL, échange JWT) est interne à l'outil MCP, hors du SKILL.md
  run grep -F "GRADATUM_SERVER_URL" "$SKILL_MD"
  [ "$status" -ne 0 ]
}

@test "SKILL.md ne contient plus l'env de transport GRADATUM_API_KEY_FILE" {
  run grep -F "GRADATUM_API_KEY_FILE" "$SKILL_MD"
  [ "$status" -ne 0 ]
}

@test "SKILL.md ne contient plus la signature de sortie '🧠' du script" {
  # La mise en forme de sortie était propre au wrapper shell ; l'outil MCP
  # rend une structure native.
  run grep -F "🧠" "$SKILL_MD"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Contenu SKILL.md — anti-leak Apache-2.0 (CONSERVÉ intégralement, load-bearing)
# ---------------------------------------------------------------------------

@test "SKILL.md ne contient pas d'adresse email personnelle" {
  run grep -i "@gmail\|@yahoo\|@hotmail" "$SKILL_MD"
  [ "$status" -ne 0 ]
}

# Motifs de CLASSE uniquement, jamais une valeur reelle. Un test public qui enumere
# les identifiants qu'il protege les PUBLIE en pretendant les defendre : le motif
# devient la fuite. Les listes nominatives restent cote prive, dans le scan de
# secrets au commit. Couvre desormais les trois plages RFC1918, pas seulement une.
@test "SKILL.md ne contient aucune adresse d'hote interne" {
  run grep -nE "\b10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b|\b172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}\b|\b192\.168\.[0-9]{1,3}\.[0-9]{1,3}\b|localhost:[0-9]+|127\.0\.0\.1:[0-9]+" "$SKILL_MD"
  [ "$status" -ne 0 ]
}

@test "SKILL.md ne contient aucun identifiant de personne ou de machine" {
  run grep -nE "/home/[a-z_][a-z0-9_-]*/|/Users/[a-zA-Z]|[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" "$SKILL_MD"
  [ "$status" -ne 0 ]
}

@test "SKILL.md ne contient aucun secret de forme connue" {
  run grep -nE "sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{12,}|ak_[0-9a-f]{8,}" "$SKILL_MD"
  [ "$status" -ne 0 ]
}
