# ARCHITECTURE — gradatum-skills

> Initialisé 2026-05-10. Révisé 2026-08-01 (migration MCP-native : plus aucun script ni
> transport HTTP côté client).

## Vue d'ensemble

Plugin Claude Code distribuable. Composition à 2 niveaux : skills L1 (logique de décision) →
skills L0 (appel d'un outil MCP atomique).

Le dépôt ne contient **que des documents**. Un skill L0 nomme un outil MCP du serveur `gradatum`
dans son champ `allowed-tools` et décrit quand et comment l'appeler ; c'est le harnais qui exécute
l'appel. Il n'y a ni script, ni binaire, ni client HTTP, ni gestion de credential dans ce dépôt.

## Arbre fonctionnel

```
gradatum-skills/                                      [CORE]    plugin Claude Code
├── .claude-plugin/plugin.json                        [CORE]    manifeste — autorité de la liste
│                                                               de candidats au retrait (cf README)
├── skills/
│   ├── gradatum-vault-search/SKILL.md                [FEATURE] L0 — recherche vault
│   ├── gradatum-vault-read/SKILL.md                  [FEATURE] L0 — lecture d'une note par chemin
│   ├── gradatum-vault-write/SKILL.md                 [FEATURE] L0 — écriture (create / update RMW)
│   ├── gradatum-vault-timeline/SKILL.md              [FEATURE] L0 — requête temporelle
│   ├── gradatum-lessons-recall/SKILL.md              [FEATURE] L0 — recall des leçons par classe
│   ├── gradatum-code-map/SKILL.md                    [FEATURE] L0 — carte de code dérivée
│   ├── gradatum-skill-reminder/SKILL.md              [FEATURE] L1 — métamémoire (chercher)
│   ├── gradatum-memorize/SKILL.md                    [FEATURE] L1 — capture/synthèse (écrire)
│   ├── gradatum-knowledge-base-usage/SKILL.md        [FEATURE] L1 — routage entre bases
│   └── gradatum-feature-eval/SKILL.md                [FEATURE] L1 — auto-évaluation PROPOSE-ONLY
├── tests/
│   ├── bats/                                         [UTILITY] tests unitaires hors réseau
│   ├── smoke/                                        [UTILITY] tests contre un serveur joignable
│   ├── verify-install.sh                             [UTILITY] conformité de l'installation
│   └── verify-mcp-tools.sh                           [UTILITY] atteignabilité des outils nommés
├── docs/RFC/                                         [UTILITY] RFC de conception (historiques)
└── (workflows CI du dépôt)                           [HOOK]    lint + tests unitaires + smoke
```

## Relations sémantiques

| Source | Relation | Cible | Note |
|---|---|---|---|
| `/gradatum-skill-reminder` | utilise | `/gradatum-vault-search`, `/gradatum-vault-timeline` | Composition L1 → L0 |
| `/gradatum-memorize` | utilise | `/gradatum-vault-write` | Composition L1 → L0, via search-before-write |
| skills L0 | dépendent de | outils MCP du serveur `gradatum` | Nommés dans `allowed-tools` de chaque `SKILL.md` |
| `tests/bats/` | teste | structure des `SKILL.md` + manifeste + procédure d'installation | Hors réseau |
| `tests/verify-mcp-tools.sh` | confronte | outils nommés ↔ outils exposés | Deux surfaces distinctes : serveur et client |
| `tests/smoke/` | déclenche | un serveur `gradatum` joignable | Aller-retour réel |
| workflow CI | exécute | `tests/bats/` + `tests/smoke/` | Runner du dépôt |

## Services externes

### Consommés

| Service | Accès | Configuration |
|---|---|---|
| Serveur `gradatum` | outils MCP `mcp__gradatum__*` | Serveur MCP déclaré côté harnais (transport, adresse et jeton portés par cette configuration, pas par ce dépôt) |

### Fournis

Aucun (plugin sans runtime permanent).

## Diagramme

```
                        ┌─────────────────────────────────┐
                        │   Orchestrateur (LLM principal) │
                        └──────────┬──────────────────────┘
                                   │ invoke
                                   ▼
                  ┌──────────────────────────────────────┐
                  │  skill L1 (ex. skill-reminder)       │
                  │  pure logique CHERCHE / SKIP         │
                  └──────────┬───────────────────────────┘
                             │ compose
                             ▼
                  ┌──────────────────────────────────────┐
                  │  skill L0 (ex. vault-search)         │
                  │  nomme un outil MCP, n'exécute rien  │
                  └──────────┬───────────────────────────┘
                             │ appel d'outil, par le harnais
                             ▼
                  ┌──────────────────────────────────────┐
                  │  serveur MCP `gradatum`              │
                  │  mcp__gradatum__vault_search         │
                  └──────────────────────────────────────┘
```

## Notes architecture

- **Stateless** : aucun cache local. Chaque invocation = un appel d'outil frais.
- **Aucun runtime côté client** : ni Bash, ni Node, ni Python, ni Rust. Un skill est un document.
  La portabilité multi-harnais ne dépend plus d'un shell mais de la présence d'un client MCP.
- **Pas de hook** `UserPromptSubmit` ni autre mécanisme propre à un harnais → le déclenchement
  repose sur la `description` du `SKILL.md` et sur une règle de configuration harnais.
- **Sécurité** : aucun secret n'est lu, nommé ni transporté par ce dépôt. Le credential du serveur
  `gradatum` appartient à la configuration du serveur MCP du consommateur. En revanche,
  `allowed-tools` **ne réduit aucune surface** : le champ *pré-autorise* les outils listés le temps
  du tour qui invoque le skill, pour éviter une demande de permission. Il ne retire rien — tout
  outil du harnais reste appelable, et les règles de permission du consommateur continuent de
  gouverner ceux qui n'y figurent pas. Le champ qui restreint est `disallowed-tools` ; ce dépôt
  n'en déclare aucun. La surface d'appel effective est donc celle que le consommateur configure,
  jamais celle que ce dépôt imposerait.
- **Asynchronie de l'écriture** : `vault_write` accuse une mise en file ; l'état réel se lit via
  `job_status` jusqu'à ce que le champ `terminal` soit vrai — jamais par une liste d'états gravée
  côté client.
