#!/usr/bin/env bats
# skill-refs.bats — Atteignabilité des SKILLS nommés (symétrique de mcp-tools-reachable.bats).
#
# Deux couches, comme pour les outils MCP :
#
#  1. Les tests unitaires exercent le VÉRIFICATEUR sur des skills fabriqués. Ils
#     ne prouvent rien sur le produit — seulement que le contrôle rougit quand
#     il doit rougir, distingue ses deux diagnostics, et refuse de conclure
#     quand il n'a rien vu.
#  2. Le test PRODUIT exerce les SKILL.md livrés. C'est la seule assertion qui
#     porte sur le produit, et elle n'est jamais passée : rien ne dépend d'un
#     serveur ou d'un binaire externe ici.
#
# Aucune liste de skills n'est écrite dans ce fichier : l'ensemble du produit
# est dérivé du contenu de skills/ à l'exécution.
#
# Prérequis : bats-core >= 1.9.0
# Exécution : bats tests/bats/skill-refs.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
VERIFY="$REPO_ROOT/tests/verify-skill-refs.sh"

setup() {
  FIXT="$BATS_TEST_TMPDIR/skills"
  HOOKS="$BATS_TEST_TMPDIR/hooks"
  KNOWN="$BATS_TEST_TMPDIR/known.txt"
  mkdir -p "$FIXT" "$HOOKS"
  printf 'alpha-local\nbeta-local\ngamma-local\n' > "$KNOWN"
}

# Fabrique un skill de test dont le corps est le texte passé en $2
fixture_skill() {
  mkdir -p "$FIXT/$1"
  { printf -- '---\nname: %s\n---\n\n' "$1"; printf '%s\n' "$2"; } > "$FIXT/$1/SKILL.md"
}

fixture_hook() {
  printf '%s\n' "$2" > "$HOOKS/$1"
}

verifie() {
  run bash "$VERIFY" --skills-dir "$FIXT" "$@"
}

# ---------------------------------------------------------------------------
# Chemin vert
# ---------------------------------------------------------------------------

@test "vert : une référence vers un autre skill du produit" {
  fixture_skill alpha 'Enchaîne sur /beta après lecture.'
  fixture_skill beta 'Invoqué par /alpha.'
  verifie --known-skills "$KNOWN"
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}

# ---------------------------------------------------------------------------
# Les deux diagnostics, distincts
# ---------------------------------------------------------------------------

@test "RED-PROOF : un skill produit nommant un skill local -> DÉPENDANCE INVERSÉE" {
  fixture_skill alpha 'Après écriture, invoque /memo pour synchroniser.'
  verifie --known-skills "$KNOWN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"DÉPENDANCE INVERSÉE"* ]]
  [[ "$output" == *"/memo"* ]]
  [[ "$output" == *"alpha/SKILL.md"* ]]
}

@test "RED-PROOF : une référence vers un nom qui n'existe nulle part -> SKILL INEXISTANT" {
  fixture_skill alpha 'Enchaîne sur /nexiste-pas-du-tout.'
  verifie --known-skills "$KNOWN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SKILL INEXISTANT"* ]]
  [[ "$output" == *"nexiste-pas-du-tout"* ]]
}

@test "les deux diagnostics ne se confondent pas dans un même passage" {
  fixture_skill alpha 'Invoque /memo puis /nexiste-pas-du-tout.'
  verifie --known-skills "$KNOWN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"DÉPENDANCE INVERSÉE"* ]]
  [[ "$output" == *"SKILL INEXISTANT"* ]]
}

@test "sans --known-skills le contrôle rougit quand même, sous un diagnostic dégradé" {
  # Le pouvoir de détection ne dépend pas du référentiel ; seule la finesse du
  # diagnostic en dépend, et le script le dit au lieu de le taire.
  fixture_skill alpha 'Invoque /memo.'
  verifie
  [ "$status" -ne 0 ]
  [[ "$output" == *"HORS PRODUIT"* ]]
  [[ "$output" == *"--known-skills"* ]]
}

# ---------------------------------------------------------------------------
# Hooks — le sens local -> produit est légitime
# ---------------------------------------------------------------------------

@test "un hook a le droit de nommer un skill local" {
  fixture_skill alpha 'Rien à signaler.'
  fixture_hook rappel.sh 'echo "pense à /memo"'
  verifie --hooks-dir "$HOOKS" --known-skills "$KNOWN"
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}

@test "RED-PROOF : un hook nommant un skill inexistant échoue" {
  fixture_skill alpha 'Rien à signaler.'
  fixture_hook rappel.sh 'echo "pense à /skill-fantome"'
  verifie --hooks-dir "$HOOKS" --known-skills "$KNOWN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SKILL INEXISTANT"* ]]
}

@test "--hooks-dir sans --known-skills est refusé plutôt que rendu vide" {
  fixture_skill alpha 'Invoque /alpha.'
  verifie --hooks-dir "$HOOKS"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--known-skills"* ]]
}

# ---------------------------------------------------------------------------
# Discrimination — ce qui a la forme d'une invocation sans en être une
# ---------------------------------------------------------------------------

@test "chemins, URL, balises fermantes et coupes françaises ne sont pas des références" {
  fixture_skill alpha "$(printf '%s\n' \
    'Le fichier /etc/exemple/config.yaml est lu au démarrage.' \
    'Endpoint : https://un-hote/mcp' \
    '<details><summary><code>x</code></summary>' \
    '</details>' \
    'Ce qui a été décidé/changé hier.' \
    '<repertoire de session>/checkpoints/date.md' \
    'Enchaîne sur /beta.')"
  fixture_skill beta 'Cible.'
  verifie --known-skills "$KNOWN"
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}

@test "une référence entre accents graves est bien vue" {
  # Le cas mesuré dans le produit : un skill local cité en code inline.
  fixture_skill alpha 'Le writer canonique est `/beta-local`, indisponible ici.'
  verifie --known-skills "$KNOWN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"beta-local"* ]]
}

# ---------------------------------------------------------------------------
# Exemptions — elles ne peuvent pas éteindre une vérification réelle
# ---------------------------------------------------------------------------

@test "un jeton exempté est affiché à chaque exécution" {
  fixture_skill alpha 'Enchaîne sur /alpha.'
  verifie --known-skills "$KNOWN"
  [[ "$output" == *"[IGNORE] /mcp"* ]]
}

@test "RED-PROOF : exempter un jeton qui est un skill du produit fait échouer" {
  fixture_skill alpha 'Enchaîne sur /alpha.'
  fixture_skill beta 'Cible.'
  verifie --known-skills "$KNOWN" --ignore beta
  [ "$status" -ne 0 ]
  [[ "$output" == *"éteindrait une vérification réelle"* ]]
}

@test "une exemption ad hoc neutralise le jeton visé, et lui seul" {
  fixture_skill alpha 'Voir /jeton-technique et /memo.'
  verifie --known-skills "$KNOWN" --ignore jeton-technique
  [ "$status" -ne 0 ]
  # Le jeton exempté figure au récapitulatif des exemptions, jamais parmi les
  # écarts — c'est la distinction que ce test cloue.
  [[ "$output" == *"[IGNORE] /jeton-technique"* ]]
  [[ "$output" != *"[FAIL] /jeton-technique"* ]] || {
    echo "le jeton exempté est encore compté comme écart" >&2; return 1; }
  [[ "$output" == *"[FAIL] /memo"* ]]
}

# ---------------------------------------------------------------------------
# Gardes anti-vacuité — un contrôle vert parce qu'il n'a rien vu ment
# ---------------------------------------------------------------------------

@test "vacuité : aucun répertoire de skill -> échec" {
  verifie --known-skills "$KNOWN"
  [ "$status" -ne 0 ]
}

@test "vacuité : des skills mais aucune référence nommée -> échec" {
  fixture_skill alpha 'Aucune invocation ici.'
  verifie --known-skills "$KNOWN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"aucune référence"* ]]
}

@test "vacuité : --known-skills fourni mais vide -> échec" {
  fixture_skill alpha 'Enchaîne sur /alpha.'
  : > "$KNOWN"
  verifie --known-skills "$KNOWN"
  [ "$status" -ne 0 ]
}

@test "vacuité : répertoire de skills inexistant -> échec" {
  run bash "$VERIFY" --skills-dir "$BATS_TEST_TMPDIR/nulle-part"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# PRODUIT — la seule assertion qui porte sur les SKILL.md livrés
# ---------------------------------------------------------------------------

@test "PRODUIT : toute référence /skill des SKILL.md livrés résout dans le produit" {
  # Aucun skip : ce contrôle ne dépend d'aucun service ni binaire externe.
  # Un échec ici nomme un `/skill` que le consommateur du produit, qui reçoit
  # skills/ et rien d'autre, ne pourra pas invoquer.
  run bash "$VERIFY"
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}
