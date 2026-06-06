# DEPENDENCIES — gradatum-skills

> Initialisé 2026-05-10. Pas de gestionnaire de paquets natif (Bash POSIX). Sera maintenu manuellement + via `/dependency-architecture-tree`.

## Runtime

| Dépendance | Version min | Rôle | Source |
|---|---|---|---|
| `bash` | 5.0+ | Shell POSIX (scripts/) | Système Linux |
| `curl` | 7.68+ | HTTP client (vault_search, auth/exchange) | Système Linux |
| `jq` | 1.6+ | JSON parsing/formatting | Système Linux |
| `coreutils` | — | `cat`, `sed`, `grep`, `seq` | Système Linux |
| `gradatum-server` | 0.1.0-alpha.13+ | Backend HTTP (port 19090) | self-hosted — https://github.com/gradatum/gradatum |

## Tests

| Dépendance | Version min | Rôle | Source |
|---|---|---|---|
| `bats-core` | 1.10+ | Tests unitaires Bash | https://github.com/bats-core/bats-core |
| `bats-assert` | latest | Helpers assertions Bats | https://github.com/bats-core/bats-assert |
| `shellcheck` | 0.9+ | Lint Bash (CI) | apt install shellcheck |

## CI

| Dépendance | Version min | Rôle |
|---|---|---|
| `forgejo-runner` | 6.0+ | Runner self-hosted (self-hosted runner) |
| `actions/checkout@v4` | — | Forgejo Actions |

## Notes

- Aucune dépendance Node, Python, Rust, Go côté client → portabilité maximum.
- `gh` CLI utilisé uniquement pour bootstrap mirror GitHub (pas en runtime).
- Version `gradatum-server` LIVE testée : voir le CHANGELOG du dépôt gradatum.
