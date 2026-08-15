#!/usr/bin/env bats
# mcp-tools-reachable.bats — Atteignabilité des outils MCP (lot 4c-2).
#
# Deux couches distinctes, volontairement :
#
#  1. Les tests unitaires exercent le VÉRIFICATEUR sur des skills et des listes
#     fabriqués. Ils ne prouvent rien sur le produit — seulement que le contrôle
#     rougit quand il doit rougir, y compris quand il n'a rien à contrôler.
#  2. Le test LIVE exerce le PRODUIT contre la liste réelle du serveur, obtenue
#     par la méthode MCP `tools/list`. C'est la seule assertion qui porte sur les
#     SKILL.md livrés ; elle est passée si aucun serveur n'est joignable.
#
# DEUX SURFACES. L'existence côté serveur ne fait pas l'exécutabilité : la liste
# d'outils d'un client MCP est figée à sa connexion. Cas mesuré le 2026-08-01 —
# serveur 26 outils, surface d'un client connecté 24, `job_status` absent du
# second alors que deux skills livrés en font leur instruction centrale. Un
# contrôle qui n'interroge que le serveur rend vert sur ce cas. Les tests
# ci-dessous clouent la distinction et ses deux diagnostics.
#
# Aucune liste d'outils n'est écrite dans ce fichier et aucun cardinal n'est
# attendu : la surface exposée par le serveur a changé plusieurs fois en une
# semaine. La comparaison porte sur des ensembles de noms.
#
# Prérequis : bats-core >= 1.9.0
# Exécution : bats tests/bats/mcp-tools-reachable.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
VERIFY="$REPO_ROOT/tests/verify-mcp-tools.sh"

load helpers   # skip_bruyant

setup() {
  FIXT="$BATS_TEST_TMPDIR/skills"
  mkdir -p "$FIXT"
}

# Fabrique un skill de test nommant les outils passés en arguments
fixture_skill() {
  local nom="$1"; shift
  mkdir -p "$FIXT/$nom"
  {
    printf -- '---\nname: %s\nallowed-tools:' "$nom"
    for t in "$@"; do printf ' mcp__gradatum__%s,' "$t"; done
    printf -- '\n---\n\n'
    for t in "$@"; do printf 'Appelle `mcp__gradatum__%s`.\n' "$t"; done
  } > "$FIXT/$nom/SKILL.md"
}

verify_with() {
  # $1 = liste exposée (noms séparés par des espaces)
  run bash -c "printf '%s\n' $1 | bash '$VERIFY' --skills-dir '$FIXT'"
}

# ---------------------------------------------------------------------------
# Chemin vert et chemin rouge du vérificateur
# ---------------------------------------------------------------------------

@test "vert : tout outil nommé figure dans la liste exposée" {
  fixture_skill demo alpha beta
  verify_with "alpha beta gamma"
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}

@test "RED-PROOF : un outil nommé absent de la liste exposée fait échouer" {
  fixture_skill demo alpha beta
  verify_with "alpha gamma"
  [ "$status" -ne 0 ]
  [[ "$output" == *"beta"* ]]
}

@test "l'échec nomme le SKILL.md fautif" {
  fixture_skill coupable orphelin
  fixture_skill innocent alpha
  verify_with "alpha"
  [ "$status" -ne 0 ]
  [[ "$output" == *"coupable/SKILL.md"* ]]
}

@test "le préfixe d'alias serveur est normalisé des deux côtés" {
  # La liste peut arriver en noms nus (serveur) ou préfixés (surface client) ;
  # l'alias `gradatum` est une valeur de configuration du consommateur.
  fixture_skill demo alpha
  verify_with "mcp__autre_alias__alpha"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Gardes anti-vacuité — un contrôle vert parce qu'il n'a rien vu ment
# ---------------------------------------------------------------------------

@test "vacuité : liste exposée vide -> échec" {
  fixture_skill demo alpha
  verify_with "''"
  [ "$status" -ne 0 ]
}

@test "vacuité : aucun SKILL.md à scanner -> échec" {
  verify_with "alpha"
  [ "$status" -ne 0 ]
}

@test "vacuité : des skills mais aucun outil nommé -> échec" {
  mkdir -p "$FIXT/muet"
  printf -- '---\nname: muet\n---\n\nAucun outil.\n' > "$FIXT/muet/SKILL.md"
  verify_with "alpha"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Surface CLIENT — celle qui décide de l'exécutabilité
# ---------------------------------------------------------------------------

liste_fichier() {
  # $1 = nom de fichier ; $2… = noms d'outils
  local f="$BATS_TEST_TMPDIR/$1"; shift
  printf '%s\n' "$@" > "$f"
  echo "$f"
}

@test "RED-PROOF : un outil exposé par le serveur mais hors surface client échoue" {
  # Le cas mesuré : le serveur connaît l'outil, le client connecté ne l'offre
  # pas. Rien n'est cassé côté serveur, et pourtant l'instruction est
  # inexécutable — c'est exactement ce qu'un contrôle serveur-seul manquait.
  fixture_skill demo alpha job_status
  srv=$(liste_fichier srv.txt alpha job_status)
  cli=$(liste_fichier cli.txt alpha)
  run bash "$VERIFY" --skills-dir "$FIXT" --tools "$srv" --client-tools "$cli"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ABSENT DE LA SURFACE CLIENT"* ]]
  [[ "$output" == *"job_status"* ]]
}

@test "le même cas est VERT si l'on n'interroge que le serveur (défaut couvert)" {
  # Preuve que le contrôle précédent a un pouvoir discriminant réel : sans la
  # surface client, ce même dépôt passe.
  fixture_skill demo alpha job_status
  srv=$(liste_fichier srv.txt alpha job_status)
  run bash "$VERIFY" --skills-dir "$FIXT" --tools "$srv"
  [ "$status" -eq 0 ]
}

@test "les deux diagnostics ne se confondent pas : INEXISTANT vs ABSENT DU CLIENT" {
  fixture_skill demo alpha job_status fantome
  srv=$(liste_fichier srv.txt alpha job_status)
  cli=$(liste_fichier cli.txt alpha)
  run bash "$VERIFY" --skills-dir "$FIXT" --tools "$srv" --client-tools "$cli"
  [ "$status" -ne 0 ]
  [[ "$output" == *"fantome — INEXISTANT"* ]]
  [[ "$output" == *"job_status — ABSENT DE LA SURFACE CLIENT"* ]]
}

@test "la surface client seule suffit comme source d'autorité" {
  fixture_skill demo alpha beta
  cli=$(liste_fichier cli.txt alpha beta)
  run bash "$VERIFY" --skills-dir "$FIXT" --client-tools "$cli"
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}

@test "l'absence de surface client est ANNONCÉE, pas tue" {
  # Un garde-fou qui ne dit pas ce qu'il n'a pas vérifié équivaut à un silence.
  fixture_skill demo alpha
  verify_with "alpha"
  [ "$status" -eq 0 ]
  [[ "$output" == *"AVERTISSEMENT"* ]]
  [[ "$output" == *"exécutabilité client NON vérifiée"* ]]
}

@test "vacuité : surface client fournie mais vide, sans surface serveur -> échec" {
  fixture_skill demo alpha
  cli=$(liste_fichier cli.txt "")
  run bash "$VERIFY" --skills-dir "$FIXT" --client-tools "$cli" </dev/null
  [ "$status" -ne 0 ]
}

@test "RED-PROOF : --client-tools seul ne lit jamais stdin (aucune attente non bornée)" {
  # Défaut mesuré le 2026-08-01 : le script décidait de lire stdin sur une
  # heuristique `[ ! -t 0 ]`. Or stdin peut n'être ni un terminal, ni jamais
  # alimenté (bats, cron, service) — la lecture attendait alors sans fin et sans
  # message, de façon non déterministe d'un run à l'autre. La règle est
  # désormais structurelle : stdin n'est lu que si aucune liste n'est nommée.
  fixture_skill demo alpha
  cli=$(liste_fichier cli.txt alpha)
  # stdin est un tube ouvert mais JAMAIS alimenté : toute lecture y bloque.
  run timeout 10 bash -c "bash '$VERIFY' --skills-dir '$FIXT' --client-tools '$cli' < <(sleep 25)"
  [ "$status" -ne 124 ] || {
    echo "BLOCAGE : le vérificateur a attendu un flux stdin qui ne vient jamais" >&2
    return 1
  }
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}

@test "le préfixe d'alias serveur est normalisé aussi sur la surface client" {
  fixture_skill demo alpha
  cli=$(liste_fichier cli.txt "mcp__un_autre_alias__alpha")
  run bash "$VERIFY" --skills-dir "$FIXT" --client-tools "$cli"
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}

# ---------------------------------------------------------------------------
# LIVE — la seule assertion qui porte sur les SKILL.md du produit
# ---------------------------------------------------------------------------

@test "LIVE : chaque outil nommé par les skills livrés est exposé par le serveur" {
  # Seule assertion de ce fichier qui interroge le monde réel plutôt que des
  # fixtures. Chacun de ses sauts est donc un trou de vérification, pas une
  # commodité : ils sont annoncés, jamais tus.
  local url="${GRADATUM_URL:-}"
  if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    skip_bruyant "les outils nommés par les skills livrés existent côté serveur" \
      "curl ou jq absent"
  fi
  if ! curl -sS --max-time 3 "$url/health" >/dev/null 2>&1; then
    skip_bruyant "les outils nommés par les skills livrés existent côté serveur" \
      "aucun serveur joignable sur $url"
  fi
  run bash "$REPO_ROOT/tests/smoke/mcp-tools-live.sh"
  # `IDENTITÉ INDISPONIBLE` est le marqueur stable des deux voies d'échec
  # d'identité : variable d'installation non fournie, ou fichier illisible.
  # Aucun chemin par défaut n'existe côté script — ce dépôt n'en prescrit pas.
  if [ "$status" -ne 0 ] && [[ "$output" == *"IDENTITÉ INDISPONIBLE"* ]]; then
    skip_bruyant "les outils nommés par les skills livrés existent côté serveur" \
      "serveur joignable, mais aucune identité fournie (GRADATUM_API_KEY_FILE / GRADATUM_TOKEN)"
  fi
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}
