# Changelog — gradatum-skills

Format : [Keep a Changelog](https://keepachangelog.com/) — SemVer.

## [Unreleased — interne]

> Développé en interne, pas encore publié (tag public synchronisé avec la release gradatum v0.5.2).

### Added — couche L0 lecture (set indispensable)
- `skills/gradatum-vault-read/` — L0 atomique : lit le contenu COMPLET d'une note par chemin —
  outil MCP natif `mcp__gradatum__vault_read`. Complément de vault-search (qui ne renvoie
  que des ULID). Output : path + section + sha256 + corps markdown.
- `skills/gradatum-lessons-recall/` — L0 atomique : recall des leçons F-60 par classe —
  outil MCP natif `mcp__gradatum__vault_lessons_recall` (12 classes contrôlées). Recall JIT
  avant un gate à risque.
- `skills/gradatum-vault-timeline/` — L0 atomique : requête temporelle du vault —
  outil MCP natif `mcp__gradatum__vault_timeline` (fenêtre epoch ms, filtre `Static`/`Event`).

### Changed — migration MCP-native (council Art.19 Round 2, lot B révisé)
- `skills/gradatum-vault-read/`, `skills/gradatum-lessons-recall/`, `skills/gradatum-vault-timeline/`
  — appel direct de l'outil MCP au lieu du wrapper shell (les 3 scripts d'origine, qui compactaient
  la réponse via `jq`, sont retirés). `gradatum-vault-search` et `gradatum-vault-write` restent des
  wrappers (hors périmètre de ce lot). Coût mesuré : perte de compaction côté client (+83 %
  `lessons-recall`, +53 % `vault-timeline` par appel) — voir note datée dans chaque SKILL.md.

### Added — couche L1 capture
- `skills/gradatum-memorize/` — L1 pure-logique : décide QUOI persister durablement (décision/leçon/
  analyse/post-mortem/résultat) + route vers la bonne section canonique, puis délègue à
  /gradatum-vault-write (via vault-search anti-doublon → vault-read sha → vault-write). Symétrique de
  skill-reminder (chercher) côté écrire. Council Art.19 GO-CAVEATS. NB : memo-snapshot/incremental
  (boucle checkpoint→synthèse) NON portés en public — infra homelab, hors primitif produit.

### Added — couche L0 code
- `skills/gradatum-code-map/` — L0 atomique : interroge la carte de code dérivée d'un projet
  (`POST /api/v1/code_scope`, vault `code-<projet>`, tree-sitter zéro-LLM). 3 modes `query`/`symbol`/
  `path` + option corps exact (`body`). Budget tokens adaptatif (`GRADATUM_BUDGET_TOKENS`, bump auto
  en mode body), flags truncation affichés, garde charset vault `^code-[a-z0-9-]+$`. Pattern 2 passes
  (signatures → body sur retenus). Script `scripts/scope.sh`. Council Art.19 (Auditeur APPROVED).
  Version PUBLIQUE (root-bridge homelab retiré, refresh délégué à `gradatum-admin code ingest/update`).

### Added — couche L0 écriture
- `skills/gradatum-vault-write/` — L0 atomique : écriture vault (`POST /api/v1/vault_write`), modes
  **create** (note neuve) et **update** in-place (RMW `note_id` + `expected_sha256`, concurrence-safe :
  sha périmé → `Conflict`, note non écrasée). Corps markdown sur stdin (immunisé ARG_MAX via stdin
  jq+curl). Poll async jusqu'à l'état terminal. Garde anti-doublon (chercher avant créer). Script
  `scripts/write.sh`. Council Art.19 3/3 GO-CAVEATS (sécu write path : injection neutralisée argv+body,
  garde sha client+serveur, secret via FD).

### Security
- Tous les nouveaux scripts : secret (clé API, JWT) passé à curl via en-tête sur descripteur de
  fichier (`-H @<(...)`) — jamais en argv (pas d'exposition `/proc/<pid>/cmdline`). Fallback clé en
  `sudo -n` (non-bloquant). Validation d'arguments (epoch ms entiers, `doc_kind` ∈ {Static,Event}).
- Council Art.19 3/3 GO-CAVEATS ; smoke LIVE :19090 validé pour les 3.

## [0.1.0] — 2026-05-25

### Added
- `skills/gradatum-vault-search/SKILL.md` — L0 atomique HTTP, wrapper `POST /api/v1/vault_search`
- `skills/gradatum-vault-search/scripts/search.sh` — script Bash POSIX, ~60 lignes, auth JWT + search + format `🧠 N notes`
- `skills/gradatum-skill-reminder/SKILL.md` — L1 logique de décision CHERCHE/SKIP, 11 sections canoniques, anti-patterns
- `tests/bats/vault-search.bats` — 22 assertions unitaires (structure SKILL.md + script + anti-leak)
- `tests/bats/skill-reminder.bats` — 20 assertions unitaires (structure + logique L1 + séparation L0/L1)
- `tests/smoke/end-to-end.sh` — 12 checks E2E contre gradatum LIVE (health + auth + vault_search + search.sh)

### Changed
- `plugin.json` version `0.1.0-alpha.1` → `0.1.0`
- `README.md` section Phase 1 enrichie (skills livrés, usage, output format)

### Notes techniques
- Score BM25 (plage 0.03-0.04 alpha.13) : threshold 0.7 spec désactivé — retour top-K sans filtre
- ULID extrait depuis le champ `path` (format `<locus>/<ulid>`) de l'API alpha.13
- Champ `caller` de la spec non supporté par l'API alpha.13 (422) — retiré

## [0.1.0-alpha.1] — 2026-05-10

### Added
- Bootstrap projet (Chemin A — lib/tool/plugin Claude Code)
- Arborescence standard (CLAUDE-GRADATUM-SKILLS.md, README.md, ARCHITECTURE.md, DEPENDENCIES.md)
- Repo source + GitHub mirror (`gradatum/gradatum-skills`)
- Spec design Phase 1 (`docs/superpowers/specs/2026-05-09-gradatum-skill-reminder-design.md`)
- Plan d'implémentation Phase 1 (`docs/superpowers/plans/2026-05-09-gradatum-skill-reminder-plan.md`)
- LICENSE Apache-2.0
- CI Forgejo Actions placeholder (`.forgejo/workflows/ci.yml`)
