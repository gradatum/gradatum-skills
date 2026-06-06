# ARCHITECTURE — gradatum-skills

> Initialisé 2026-05-10. Sera enrichi par `/dependency-architecture-tree` après livraison Phase 1.

## Vue d'ensemble

Plugin Claude Code distribuable. Composition à 2 niveaux : skills L1 (logique décision) → skills L0 (transport HTTP atomique).

## Arbre fonctionnel

```
gradatum-skills/                                      [CORE]   plugin Claude Code
├── .claude-plugin/plugin.json                        [CORE]   manifest plugin
├── skills/
│   ├── gradatum-vault-search/                        [FEATURE] L0 atomique lecture vault
│   │   ├── SKILL.md                                  [SUB]    frontmatter + corps + doctrine output
│   │   └── scripts/search.sh                         [SUB]    Bash POSIX wrapper curl + jq
│   └── gradatum-skill-reminder/                      [FEATURE] L1 métamémoire auto-déclenchée
│       └── SKILL.md                                  [SUB]    pure logique décision (pas de script)
├── tests/
│   ├── bats/                                         [UTILITY] tests unitaires script
│   └── smoke/                                        [UTILITY] tests E2E LIVE
├── docs/superpowers/
│   ├── specs/                                        [UTILITY] spec design Phase 1
│   └── plans/                                        [UTILITY] plan implémentation Phase 1
└── .forgejo/workflows/ci.yml                         [HOOK]   CI Forgejo Actions
```

## Relations sémantiques

| Source | Relation | Cible | Note |
|---|---|---|---|
| `/gradatum-skill-reminder` | utilise | `/gradatum-vault-search` | Composition L1 → L0 |
| `/gradatum-vault-search` | dépend de | `gradatum-server :19090` | HTTP `POST /api/v1/vault_search` |
| `/gradatum-vault-search` | utilise auth | `/etc/gradatum/claude-code.api-key` | API key → JWT 24h via `/auth/exchange` |
| `tests/bats/` | teste | `scripts/search.sh` | Unit isolés (mock curl) |
| `tests/smoke/` | déclenche | `gradatum-server :19090` | E2E LIVE, write canary + verify |
| `.forgejo/workflows/ci.yml` | exécute | `tests/bats/` + `tests/smoke/` | Runner self-hosted |

## Services externes

### Consommés

| Service | Port | URL | Variables env |
|---|---|---|---|
| `gradatum-server` | 19090 | `http://<gradatum-server>` | `GRADATUM_SERVER_URL`, `GRADATUM_API_KEY_FILE` |

### Fournis

Aucun (Chemin A — plugin sans runtime permanent).

## Diagramme

```
                        ┌─────────────────────────────────┐
                        │   Orchestrateur (LLM principal) │
                        └──────────┬──────────────────────┘
                                   │ invoke
                                   ▼
                  ┌──────────────────────────────────────┐
                  │  /gradatum-skill-reminder (L1)       │
                  │  pure logique décision MEMORIZE/SKIP │
                  └──────────┬───────────────────────────┘
                             │ compose
                             ▼
                  ┌──────────────────────────────────────┐
                  │  /gradatum-vault-search (L0)         │
                  │  Bash + curl + jq                    │
                  └──────────┬───────────────────────────┘
                             │ HTTP POST
                             ▼
                  ┌──────────────────────────────────────┐
                  │  gradatum-server :19090              │
                  │  /api/v1/vault_search                │
                  └──────────────────────────────────────┘
```

## Notes architecture

- **Stateless** : aucun cache local. Chaque invocation = 1 appel HTTP frais.
- **Bash POSIX uniquement** : pas de Node, pas de Python, pas de Rust côté client. Maximum portabilité multi-harness.
- **Pas de hook** `UserPromptSubmit` ni autre mécanisme spécifique Claude Code natif → portable goose, gemini-cli, open-code (Phase 4).
- **Sécurité** : API key sur disque (`chmod 600`), JWT 24h en mémoire, jamais persisté.
