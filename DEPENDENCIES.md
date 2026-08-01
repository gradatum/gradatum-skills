# DEPENDENCIES — gradatum-skills

> Initialisé 2026-05-10. Révisé 2026-08-01 (migration MCP-native). Pas de gestionnaire de paquets :
> le produit livré n'est constitué que de documents. Maintenu manuellement.

## Runtime des skills

**Aucune.** Un skill est un `SKILL.md` : il nomme un outil MCP, il ne l'exécute pas. Il n'y a ni
script, ni binaire, ni client HTTP, ni parseur JSON côté client.

| Dépendance | Version min | Rôle | Source |
|---|---|---|---|
| Serveur `gradatum` | — | Expose les outils MCP `mcp__gradatum__*` que les skills nomment | self-hosted — https://github.com/gradatum/gradatum |
| Client MCP du harnais | — | Déclare le serveur `gradatum` et exécute l'appel d'outil | Fourni par le harnais (Claude Code, Claude Desktop, …) |

Le contrat n'est pas une version de serveur mais un **ensemble de noms d'outils** : chaque
`SKILL.md` déclare les siens dans `allowed-tools`. La compatibilité se vérifie, elle ne se déduit
pas d'un numéro de version — voir `tests/verify-mcp-tools.sh`.

## Installation

| Dépendance | Version min | Rôle |
|---|---|---|
| `git` | 2.x | `git archive` depuis une référence commitée |
| `tar` | — | Extraction de l'archive vers le répertoire de skills |
| Utilitaires POSIX | — | `awk`, `grep`, `sed`, `sort` (procédure de synchronisation du README) |

## Tests

| Dépendance | Version min | Rôle | Source |
|---|---|---|---|
| `bats-core` | 1.10+ | Tests unitaires (hors réseau) | https://github.com/bats-core/bats-core |
| `bats-assert` | latest | Helpers d'assertions Bats | https://github.com/bats-core/bats-assert |
| `shellcheck` | 0.9+ | Lint des scripts de test et de vérification | https://www.shellcheck.net/ |
| `bash` | 4.x+ | Exécution des vérificateurs et des smokes (`tests/*.sh`) | Système |

Ces dépendances concernent **les tests et vérificateurs du dépôt**, jamais les skills livrés :
un consommateur qui installe le plugin n'en a besoin d'aucune.

## CI

| Dépendance | Rôle |
|---|---|
| Runner du dépôt | Exécute lint, tests unitaires et smoke |
| `actions/checkout@v4` | Récupération des sources |

## Notes

- Aucune dépendance Node, Python, Rust ou Go, à aucun étage.
- La portabilité multi-harnais ne dépend plus de la disponibilité d'un shell, mais de la présence
  d'un client MCP et d'un mécanisme de skills côté harnais.
