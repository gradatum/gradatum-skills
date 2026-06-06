# Changelog — gradatum-skills

Format : [Keep a Changelog](https://keepachangelog.com/) — SemVer.

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
