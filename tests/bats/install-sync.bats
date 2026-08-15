#!/usr/bin/env bats
# install-sync.bats — La synchronisation d'installation retire aussi (lot 4b) et
# la conformité d'installation est vérifiable (lot 4c-1).
#
# Le bloc exécuté ici n'est PAS une copie de la procédure documentée : il est
# EXTRAIT du README entre les marqueurs SYNC-INSTALL. Un README qui dérive de ce
# qui est testé rend la suite rouge, et une procédure corrigée sans mise à jour
# du README aussi.
#
# Le seul geste destructif du produit est testé par red-proof : un skill étranger
# est posé dans un répertoire d'installation JETABLE, la synchronisation est
# lancée, sa survie est asserée. Aucun test n'écrit hors de $BATS_TEST_TMPDIR.
#
# Prérequis : bats-core >= 1.9.0, git
# Exécution : bats tests/bats/install-sync.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  SNAP="$BATS_TEST_TMPDIR/repo"
  DEST="$BATS_TEST_TMPDIR/skills-install"
  FAKE_HOME="$BATS_TEST_TMPDIR/home"
  SYNC="$BATS_TEST_TMPDIR/sync.sh"
  RECEIPT="$DEST/.gradatum-skills.installed"

  mkdir -p "$SNAP" "$DEST" "$FAKE_HOME"

  # Instantané commité du répertoire de travail : la synchronisation lit un objet
  # commit, or les modifications en cours ne sont pas encore commitées dans le
  # dépôt réel. L'instantané rend le test valable avant comme après le commit.
  tar -C "$REPO_ROOT" --exclude=.git -cf - . | tar -C "$SNAP" -xf -
  git -C "$SNAP" init -q
  git -C "$SNAP" add -A
  git -C "$SNAP" -c user.email=tests@example.invalid -c user.name=tests commit -qm instantane

  extract_sync_snippet > "$SYNC"
}

# Bloc de synchronisation, extrait du README entre ses marqueurs
extract_sync_snippet() {
  awk '/SYNC-INSTALL:BEGIN/{f=1;next} /SYNC-INSTALL:END/{exit} f' "$REPO_ROOT/README.md" \
    | sed '/^```/d'
}

run_sync() {
  run env -i PATH="$PATH" HOME="$FAKE_HOME" \
    GRADATUM_SKILLS_REPO="$SNAP" CLAUDE_SKILLS_DIR="$DEST" GRADATUM_SKILLS_REF=HEAD \
    bash "$SYNC"
}

manifest_entries() {
  awk '/"skills"[[:space:]]*:/{f=1} f{print} f && /\]/{exit}' "$SNAP/.claude-plugin/plugin.json" \
    | grep -o '"\./skills/[^"/]*"' | tr -d '"' | sed 's|^\./skills/||' | sort
}

# Ajoute au produit (instantané) un skill jetable, puis commite
add_product_skill() {
  mkdir -p "$SNAP/skills/$1"
  printf -- '---\nname: %s\ndescription: skill jetable de test\n---\n\nContenu.\n' "$1" \
    > "$SNAP/skills/$1/SKILL.md"
  sed -i "s|\"skills\": \[|\"skills\": [\n    \"./skills/$1\",|" "$SNAP/.claude-plugin/plugin.json"
  git -C "$SNAP" add -A
  git -C "$SNAP" -c user.email=tests@example.invalid -c user.name=tests commit -qm "ajout $1"
}

# Retire ce skill du produit, puis commite
remove_product_skill() {
  rm -rf "$SNAP/skills/$1"
  sed -i "\|\"\./skills/$1\"|d" "$SNAP/.claude-plugin/plugin.json"
  git -C "$SNAP" add -A
  git -C "$SNAP" -c user.email=tests@example.invalid -c user.name=tests commit -qm "retrait $1"
}

# Skill étranger au produit, tel qu'en pose un opérateur (gov-*, memo, safety-*…)
put_foreign_skill() {
  mkdir -p "$DEST/$1"
  printf -- '---\nname: %s\n---\n\nSkill local, étranger au produit.\n' "$1" > "$DEST/$1/SKILL.md"
}

# ---------------------------------------------------------------------------
# Le bloc testé est bien celui du README
# ---------------------------------------------------------------------------

@test "le bloc de synchronisation est extractible du README et non vide" {
  [ -s "$SYNC" ]
  grep -q 'git .*archive' "$SYNC"
  grep -q 'RECEIPT' "$SYNC"
}

@test "le bloc de synchronisation ne balaie jamais le répertoire d'installation" {
  # La liste des candidats ne peut pas venir d'un listage de $DEST : aucune
  # énumération du répertoire d'installation n'est admise dans la procédure.
  run grep -nE '(ls|find)[^|]*"\$DEST"' "$SYNC"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Installation
# ---------------------------------------------------------------------------

@test "la synchronisation installe tous les skills du manifeste" {
  run_sync
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
  while IFS= read -r s; do
    [ -f "$DEST/$s/SKILL.md" ] || { echo "non installé : $s" >&2; return 1; }
  done < <(manifest_entries)
}

@test "le reçu reflète exactement le manifeste après synchronisation" {
  run_sync
  [ "$status" -eq 0 ]
  diff <(sort -u "$RECEIPT") <(manifest_entries)
}

@test "la synchronisation est idempotente" {
  run_sync
  [ "$status" -eq 0 ]
  empreinte1=$(cd "$DEST" && find . | sort | md5sum)
  run_sync
  [ "$status" -eq 0 ]
  empreinte2=$(cd "$DEST" && find . | sort | md5sum)
  [ "$empreinte1" = "$empreinte2" ]
}

@test "première installation sans reçu : aucun retrait" {
  put_foreign_skill "etranger-jetable"
  [ ! -f "$RECEIPT" ]
  run_sync
  [ "$status" -eq 0 ]
  [ -f "$DEST/safety-jetable/SKILL.md" ]
}

# ---------------------------------------------------------------------------
# RED-PROOF — le geste destructif épargne ce qui n'appartient pas au produit
# ---------------------------------------------------------------------------

@test "RED-PROOF : des skills locaux hors manifeste survivent à la synchronisation" {
  # Échantillon représentatif des familles locales de l'opérateur.
  for s in alpha-etranger beta-etranger gamma-etranger delta-etranger epsilon-etranger zeta-etranger; do
    put_foreign_skill "$s"
  done
  # Un reçu existe et porte un obsolète : le chemin destructif est bien emprunté,
  # sans quoi cette preuve serait vide.
  run_sync
  [ "$status" -eq 0 ]
  echo "gradatum-sorti-du-produit" >> "$RECEIPT"
  mkdir -p "$DEST/gradatum-sorti-du-produit"
  touch "$DEST/gradatum-sorti-du-produit/SKILL.md"

  run_sync
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }

  # Le chemin destructif a bien agi…
  [ ! -d "$DEST/gradatum-sorti-du-produit" ]
  # …et n'a touché aucun skill étranger.
  for s in alpha-etranger beta-etranger gamma-etranger delta-etranger epsilon-etranger zeta-etranger; do
    [ -f "$DEST/$s/SKILL.md" ] || { echo "détruit à tort : $s" >&2; return 1; }
  done
}

@test "RED-PROOF : un répertoire nommé gradatum-* mais hors manifeste survit" {
  # Le nom ne fait pas l'appartenance : seul un manifeste nomme un candidat.
  # Un filtre par préfixe (gradatum-*) détruirait ce répertoire — pas celui-ci.
  run_sync
  [ "$status" -eq 0 ]
  put_foreign_skill "gradatum-etranger-au-produit"
  run_sync
  [ "$status" -eq 0 ]
  [ -f "$DEST/gradatum-etranger-au-produit/SKILL.md" ]
}

@test "RED-PROOF : un lien symbolique portant le nom d'un obsolète n'est pas suivi" {
  run_sync
  [ "$status" -eq 0 ]
  mkdir -p "$BATS_TEST_TMPDIR/hors-installation"
  touch "$BATS_TEST_TMPDIR/hors-installation/temoin"
  ln -s "$BATS_TEST_TMPDIR/hors-installation" "$DEST/gradatum-lien"
  echo "gradatum-lien" >> "$RECEIPT"

  run_sync
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/hors-installation/temoin" ]
  [ -L "$DEST/gradatum-lien" ]
}

# ---------------------------------------------------------------------------
# Cycle complet : un skill sort du produit, la synchronisation le retire
# ---------------------------------------------------------------------------

@test "un skill retiré du produit est retiré de l'installation" {
  add_product_skill "gradatum-ephemere"
  run_sync
  [ "$status" -eq 0 ]
  [ -f "$DEST/gradatum-ephemere/SKILL.md" ]
  grep -qx "gradatum-ephemere" "$RECEIPT"

  remove_product_skill "gradatum-ephemere"
  run_sync
  [ "$status" -eq 0 ]
  [ ! -d "$DEST/gradatum-ephemere" ]
  run grep -qx "gradatum-ephemere" "$RECEIPT"
  [ "$status" -ne 0 ]
}

@test "un manifeste vide fait échouer la synchronisation sans rien détruire" {
  run_sync
  [ "$status" -eq 0 ]
  printf '{"name":"x","skills":[]}\n' > "$SNAP/.claude-plugin/plugin.json"
  git -C "$SNAP" add -A
  git -C "$SNAP" -c user.email=tests@example.invalid -c user.name=tests commit -qm vide

  run_sync
  [ "$status" -ne 0 ]
  # Aucun skill n'a été retiré au prétexte d'un manifeste illisible.
  [ -f "$DEST/gradatum-vault-search/SKILL.md" ]
}

# ---------------------------------------------------------------------------
# Conformité d'installation (4c-1) — vert après synchronisation, rouge sur écart
# ---------------------------------------------------------------------------

run_verify_install() {
  run env -i PATH="$PATH" HOME="$FAKE_HOME" \
    GRADATUM_SKILLS_REPO="$SNAP" CLAUDE_SKILLS_DIR="$DEST" GRADATUM_SKILLS_REF=HEAD \
    bash "$REPO_ROOT/tests/verify-install.sh"
}

@test "verify-install.sh est vert juste après une synchronisation" {
  run_sync
  [ "$status" -eq 0 ]
  run_verify_install
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}

@test "RED-PROOF : verify-install.sh rougit si un fichier installé est altéré" {
  run_sync
  [ "$status" -eq 0 ]
  echo "ligne ajoutée hors référence" >> "$DEST/gradatum-vault-search/SKILL.md"
  run_verify_install
  [ "$status" -ne 0 ]
}

@test "RED-PROOF : verify-install.sh rougit si un skill du manifeste est absent" {
  run_sync
  [ "$status" -eq 0 ]
  rm -rf "$DEST/gradatum-vault-read"
  run_verify_install
  [ "$status" -ne 0 ]
}

@test "verify-install.sh ignore les skills étrangers au manifeste" {
  run_sync
  [ "$status" -eq 0 ]
  put_foreign_skill "etranger-jetable-2"
  run_verify_install
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# La garde anti-vacuité de verify-install.sh n'est pas du code mort
# ---------------------------------------------------------------------------

@test "RED-PROOF : un manifeste aux entrées sans ./ échoue AVEC diagnostic" {
  # Défaut mesuré le 2026-08-01 : sous `set -euo pipefail`, le `grep -o` qui ne
  # matche rien faisait échouer la substitution et abandonnait le script AVANT
  # la garde anti-vacuité — laquelle n'était donc jamais atteinte. Exit 1, zéro
  # ligne de diagnostic. Fail-closed, donc pas de faux vert, mais MUET : le
  # vérificateur que le README présente comme la preuve d'opérationnalité ne
  # disait pas pourquoi il refusait. Cette assertion cloue la sortie, pas
  # seulement le code de retour.
  sed -i 's|"\./skills/|"skills/|g' "$SNAP/.claude-plugin/plugin.json"
  git -C "$SNAP" add -A
  git -C "$SNAP" -c user.email=tests@example.invalid -c user.name=tests commit -qm "entrées sans ./"

  run_verify_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"aucun skill lisible"* ]] || {
    echo "échec muet : la garde anti-vacuité n'a pas été atteinte" >&2
    echo "sortie complète : [$output]" >&2
    return 1
  }
  [[ "$output" == *"./skills/<nom>"* ]]
}

@test "RED-PROOF : une référence sans manifeste échoue AVEC son propre diagnostic" {
  # Diagnostic distinct de la vacuité : un manifeste absent n'est pas un
  # manifeste illisible, et les confondre enverrait sur la mauvaise piste.
  git -C "$SNAP" rm -q --cached .claude-plugin/plugin.json
  git -C "$SNAP" -c user.email=tests@example.invalid -c user.name=tests commit -qm "sans manifeste"

  run_verify_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"introuvable à la référence"* ]]
}
