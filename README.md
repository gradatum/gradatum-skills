# gradatum-skills

> Plugin Claude Code (Apache-2.0) — skills atomiques + métamémoire pour `gradatum`.

Composition L1 (logique de décision) → L0 (atomique HTTP). Stateless. Bash POSIX.

## Phase 1 — Skills disponibles (v0.1.0)

Skills disponibles :

| Skill | Niveau | Rôle | Statut |
|---|---|---|---|
| `/gradatum-vault-search` | L0 | Wrapper HTTP atomique sur `POST /api/v1/vault_search` du serveur gradatum (`:19090`). Script Bash POSIX `scripts/search.sh`. | ✅ LIVRÉ |
| `/gradatum-vault-read` | L0 | Lit le contenu COMPLET d'une note par chemin — outil MCP natif `mcp__gradatum__vault_read`. Complément de vault-search (qui ne renvoie que des ULID). | ✅ LIVRÉ |
| `/gradatum-lessons-recall` | L0 | Recall des leçons apprises (F-60) par classe — outil MCP natif `mcp__gradatum__vault_lessons_recall`. Recall JIT avant un gate à risque. | ✅ LIVRÉ |
| `/gradatum-vault-timeline` | L0 | Requête temporelle du vault — outil MCP natif `mcp__gradatum__vault_timeline` (fenêtre epoch ms, `Static`/`Event`). | ✅ LIVRÉ |
| `/gradatum-vault-write` | L0 | Écriture vault (`POST /api/v1/vault_write`) — create + update in-place RMW (concurrence-safe sha256). Corps sur stdin, poll async, garde anti-doublon. | ✅ LIVRÉ |
| `/gradatum-code-map` | L0 | Carte de code dérivée (`POST /api/v1/code_scope`, vault `code-<projet>`, tree-sitter). Modes query/symbol/path + corps. Comprendre/naviguer du code sans lire les fichiers entiers. | ✅ LIVRÉ |
| `/gradatum-memorize` | L1 | Décide QUOI persister durablement + route vers la bonne section, délègue à `/gradatum-vault-write`. Symétrique de skill-reminder (écrire vs chercher). Pure logique. | ✅ LIVRÉ |
| `/gradatum-skill-reminder` | L1 | Métamémoire auto-déclenchée — détermine si le contexte courant nécessite une recherche vault, délègue à `/gradatum-vault-search`. Pure logique de décision. | ✅ LIVRÉ |
| `gradatum-desktop` | MCP-only | Variante consolidée pour **Claude Desktop** via connecteur MCP (`/mcp` Streamable HTTP + Bearer) — aucun script local. Search-before-write, triage des sections, gatekeeper, prudence outils destructifs. Les autres skills ciblent Claude Code (Bash local) et ne fonctionnent pas sur Desktop. | ✅ LIVRÉ |

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

Détails : `docs/superpowers/specs/2026-05-09-gradatum-skill-reminder-design.md`.

## Pré-requis

- Serveur `gradatum-server` LIVE sur `http://<gradatum-server>` (self-hosted)
- Auth API key file `/etc/gradatum/claude-code.api-key` (Path 2 → JWT 24h)
- `bash` 5+, `curl`, `jq`

## Installation (locale, dev)

**Copies figées depuis un commit, jamais un symlink vers ce dépôt.** `git archive` lit l'objet
commit, pas le répertoire de travail — la commande ci-dessous installe donc toujours l'état
commité, même si le worktree a des modifications en cours :

```bash
mkdir -p ~/.claude/skills
REF="$(git -C ~/projects/gradatum-skills rev-parse HEAD)"
git -C ~/projects/gradatum-skills archive "$REF" skills \
  | tar -x --strip-components=1 -C ~/.claude/skills
```

Pour installer un commit ou un tag précis plutôt que le dernier : remplacer la ligne `REF=` par
`REF=<commit-ou-tag>`.

### Pourquoi pas un symlink

Un symlink transforme chaque écriture dans le dépôt en activation immédiate côté runtime : il
n'y a plus de délai entre modifier et exécuter, donc plus de fenêtre pour un commit, une revue
ou un verdict de council — les gates du projet supposent tous ce délai, le symlink le supprime
en silence. Décision actée : `decisions/01KYX31HZVW04AQC6ZCJ9T912W`.

### Contrepartie : dérive possible

La copie peut diverger du dépôt dès qu'un commit ultérieur modifie un skill installé — rien ne
la resynchronise automatiquement, il n'existe pas encore d'outil dédié (dette assumée). Après
tout commit touchant un skill déjà installé, relancer manuellement la commande d'archive
ci-dessus pour le remettre à jour.

## Wire-up (CLAUDE.md anchor)

La copie ci-dessus expose les skills, mais l'invocation **systématique** de `/gradatum-skill-reminder` repose sur la discipline LLM (pas de hook par design — portabilité multi-agent). Sans la règle suivante dans votre fichier de configuration harness, le skill ne sera invoqué que sporadiquement.

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

