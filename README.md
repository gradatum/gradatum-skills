# gradatum-skills

> Plugin Claude Code (Apache-2.0) — skills atomiques + métamémoire pour `gradatum`.

Composition L1 (logique de décision) → L0 (atomique HTTP). Stateless. Bash POSIX.

## Phase 1 — Skills disponibles (v0.1.0)

Deux skills livrés en phase 1 :

| Skill | Niveau | Rôle | Statut |
|---|---|---|---|
| `/gradatum-vault-search` | L0 | Wrapper HTTP atomique sur `POST /api/v1/vault_search` du serveur gradatum (`:19090`). Script Bash POSIX `scripts/search.sh`. | ✅ LIVRÉ |
| `/gradatum-skill-reminder` | L1 | Métamémoire auto-déclenchée — détermine si le contexte courant nécessite une recherche vault, délègue à `/gradatum-vault-search`. Pure logique de décision. | ✅ LIVRÉ |

### /gradatum-vault-search (L0 — atomique HTTP)

Recherche dans le vault gradatum via `POST /api/v1/vault_search`.

**Output** : `🧠 N notes : <ulid-26> [<score>], ...`

**Auth** : API key file `/etc/gradatum/claude-code.api-key` → JWT EdDSA Ed25519 24h via `/auth/exchange`.

**Invoquer quand** : réflexion sur un sujet traité, anti-doublon avant écriture, recherche explicite.

### /gradatum-skill-reminder (L1 — logique décision)

Déclencheur métamémoire basé sur des règles de décision CHERCHE/SKIP.

**CHERCHE** si le prompt est : question, brainstorming, diagnostic, planification, amorce de tâche substantielle.

**SKIP** si : validation seule ("oui", "go"), commande directe, slash-command, trivial.

**Sections canoniques** : `decisions`, `council`, `commits`, `debug`, `lessons-learned`, `architecture`, `agent-issues`, `roadmap`, `retrospectives`, `reasoning`, `project-bootstrap`.

## Roadmap

- **Phase 2** — `/gradatum-vault-write` (L0) + `/gradatum-skill-memorize` (L1) + débranchement de 12 skills existants
- **Phase 3** — Atomiques L0 supplémentaires (downgrade, classify, graph, trace, context, read, list, status, authors, tags)
- **Phase 4** — Compatibilité multi-agent (goose, gemini-cli, open-code)
- **Phase 5** — Distribution `/plugin install gradatum/skills`

Détails : `docs/superpowers/specs/2026-05-09-gradatum-skill-reminder-design.md` + roadmap `~/tmp/scratch/2026-05-09-gradatum-skills-roadmap-future.md`.

## Pré-requis

- Serveur `gradatum-server` LIVE sur `http://<gradatum-server>` (<container>)
- Auth API key file `/etc/gradatum/claude-code.api-key` (Path 2 → JWT 24h)
- `bash` 5+, `curl`, `jq`

## Installation (locale, dev)

Symlinks depuis `~/.claude/skills/` vers ce projet :

```bash
ln -sf ~/projects/gradatum-skills/skills/gradatum-vault-search ~/.claude/skills/gradatum-vault-search
ln -sf ~/projects/gradatum-skills/skills/gradatum-skill-reminder ~/.claude/skills/gradatum-skill-reminder
```

## Wire-up (CLAUDE.md anchor)

Les symlinks ci-dessus exposent les skills, mais l'invocation **systématique** de `/gradatum-skill-reminder` repose sur la discipline LLM (pas de hook par design — portabilité multi-agent). Sans la règle suivante dans votre fichier de configuration harness, le skill ne sera invoqué que sporadiquement.

Ajouter à votre fichier harness (Claude Code : `~/CLAUDE.md` · goose : `~/.config/goose/config.yaml` · gemini-cli : `~/.gemini/GEMINI.md` · open-code : à évaluer) :

```markdown
## Métamémoire vault gradatum (skill /gradatum-skill-reminder)

AVANT toute réponse substantielle (proposition, planification, écriture vault, diagnostic, décision, brainstorming) — invoquer /gradatum-skill-reminder.

Tu n'évalues pas manuellement la pertinence — le skill tranche en interne. Le coût d'un SKIP est négligeable (logique locale, zéro vault call).

Exception SKIP : slash command (/...) · réponse courte de validation/négation sans amorce de tâche ("oui" seul, "non" seul, "ok" seul) · exécution commande directe.
Note : "go" suivi d'une description de tâche = amorce substantielle → invoquer.
```

Sans ce wire-up, l'invocation est laissée à la discrétion de l'agent (≈ sporadique). Avec, l'agent invoque le skill systématiquement et le skill lui-même décide CHERCHE vs SKIP en interne.

**Référence design** : `docs/superpowers/specs/2026-05-09-gradatum-skill-reminder-design.md` section 6 « Mécanisme de déclenchement systématique » (3 leviers L-1 description SKILL.md + L-2 règle harness + L-3 mention boot).

## Architecture

Voir `ARCHITECTURE.md` (généré par `/dependency-architecture-tree`).

## Tests

```bash
# Unit Bats (script atomique L0)
cd tests/bats && bats test_search_helpers.bats

# Smoke E2E (write canary + invoke search + verify)
bash tests/smoke/smoke-e2e.sh
```

## Licence

Apache-2.0 — voir `LICENSE`.

## Contexte projet

`CLAUDE-GRADATUM-SKILLS.md` — état, roadmap détaillée, décisions structurantes.
