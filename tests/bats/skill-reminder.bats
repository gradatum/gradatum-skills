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

@test "SKILL.md délègue les sections canoniques à l'autorité /gradatum-vault-write" {
  # Le lot répudie tout cardinal gravé : le SKILL ne doit plus énumérer ni compter les
  # sections canoniques (la taxonomie évolue — tout nombre gravé dérive), mais pointer vers
  # l'autorité unique. On atteste la délégation, pas une liste ni un compte.
  grep -q "Sections canoniques" "$SKILL_MD"
  grep -q "gradatum-vault-write" "$SKILL_MD"
}

@test "SKILL.md contient la convention de titre vault" {
  grep -q "CATÉGORIE" "$SKILL_MD"
}

@test "SKILL.md atteste l'absence d'état entre invocations" {
  # DETTE ANTI-RÉGRESSION : l'assertion porte sur la PROPRIÉTÉ (le skill ne mémorise pas
  # d'état d'un tour à l'autre), PAS sur un vocabulaire. Ne PAS re-clouer à un mot :
  # le token anglais « stateless » a été épuré par le refacto F-46 alors que la propriété
  # tenait toujours — c'est ce clouage lexical qui avait produit une suite rouge silencieuse.
  # Double ancre indépendante : le test ne rougit que si la propriété disparaît des DEUX
  # formulations, c.-à-d. si elle n'est réellement plus documentée (rouge alors légitime).
  grep -qiE "état entre invocations|tour courant" "$SKILL_MD"
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
