# Changelog — gradatum-skills

Format : [Keep a Changelog](https://keepachangelog.com/) — SemVer.

## [Unreleased]

> Pas encore publié. Le tag public est synchronisé avec une release du serveur `gradatum`.

### Fixed — conformité frontmatter pour les chemins de packaging spec (2026-08-14)

- Retrait de la clé `type: gradatum` du frontmatter des 10 `SKILL.md`. Cette clé n'était lue par
  aucun test, aucun hook, ni le manifeste du plugin — elle n'a jamais eu de rôle fonctionnel dans
  Claude Code, qui est permissif sur les clés hors spec. La spécification officielle des skills
  n'autorise que six propriétés (`name`, `description`, `license`, `compatibility`, `metadata`,
  `allowed-tools`) pour les chemins claude.ai skill uploads / Skills API / `package_skill.py`, et
  rejette toute clé hors liste par une erreur dure au packaging. **Ce retrait ne corrige aucun
  défaut observé dans Claude Code lui-même** — il lève un blocage latent pour les chemins de
  distribution alternatifs à ce harnais.

### Fixed — `allowed-tools` manquant sur `gradatum-skill-reminder` (2026-08-14)

- Le skill appelait `vault_timeline`, `vault_proactive_recall` et `vault_proactive_recall_feedback`
  sans les déclarer, seul des neuf skills appelant un outil à ne pas le faire. `DEPENDENCIES.md` et
  `ARCHITECTURE.md` affirmaient pourtant la propriété pour tous. La déclaration est ajoutée ;
  `vault_search` n'y figure pas — le skill ne l'appelle jamais lui-même, il délègue à
  `/gradatum-vault-search`, qui le déclare. Un `allowed-tools` n'agrège pas les outils de ses
  délégués.

### Fixed — affirmation de sécurité inexacte dans `ARCHITECTURE.md` (2026-08-14)

- Le document affirmait que « la surface d'attaque d'un skill se réduit à ce que son champ
  `allowed-tools` autorise ». C'est l'inverse du mécanisme documenté : `allowed-tools` **pré-autorise**
  les outils listés le temps du tour, pour éviter une demande de permission ; il ne retire rien, et
  tout outil du harnais reste appelable. Le champ qui restreint est `disallowed-tools`, qu'aucun
  skill de ce dépôt ne déclare. Formulation corrigée pour décrire le mécanisme réel.

### Fixed — tests anti-fuite qui publiaient les identifiants protégés (2026-08-14)

- Deux tests `bats` vérifiaient l'absence d'identifiants internes dans les `SKILL.md` en énumérant
  ces identifiants dans leur motif `grep` — publiant ainsi, dans un dépôt public, exactement ce
  qu'ils défendaient. Les motifs nominatifs sont retirés au profit de motifs de **classe** : les
  trois plages RFC1918 (au lieu d'une seule auparavant), `localhost:<port>` et loopback avec port,
  chemins de répertoire personnel, adresses e-mail, et formes de secret connues. La propriété
  testée est préservée ; aucune valeur réelle n'est plus nommée.

### Changed — migration MCP-native complète (2026-08-01)

- **Les six skills L0 appellent désormais un outil MCP.** Plus aucun `curl`, plus aucun script
  shell, plus aucun parseur JSON dans `skills/` — le répertoire `scripts/` est supprimé du produit.
  Cela **supersède** la note « lot B » ci-dessous, qui laissait `gradatum-vault-search` et
  `gradatum-vault-write` en wrappers : ce n'est plus le cas.
- Conséquence pour un consommateur : les prérequis `bash`/`curl`/`jq` disparaissent, ainsi que
  toute configuration de credential côté skill. Le transport, l'adresse du serveur et le jeton
  appartiennent à la configuration du serveur MCP du harnais.
- `gradatum-code-map` : la mise à jour de l'index de code est explicitement une opération
  d'administration côté serveur, **pas** une opération MCP ; le skill ne couvre que l'interrogation.

### Fixed — promesse de sécurité retirée de la documentation publique

- La formulation « concurrence-safe » associée à `gradatum-vault-write` est **retirée**. Le skill
  décrit désormais le **mécanisme** (mise à jour in-place sous verrou optimiste : identifiant de
  note + hash attendu, conflit → relecture obligatoire avant nouvel essai) et non une garantie.
  La tenue effective du verrou est une propriété du **serveur** exécuté par le consommateur, pas
  du skill : elle se vérifie, elle ne se promet pas depuis ce dépôt.
- Le README décrivait encore l'architecture à scripts (`scripts/search.sh`, corps « sur stdin »,
  endpoints HTTP, chemin de fichier de credential) et une liste de sections canoniques divergente.
  La liste des sections n'est plus recopiée : son autorité unique est le skill
  `/gradatum-vault-write`. Aucun cardinal n'est gravé.

### Added — couche L1 (guidage)

- `skills/gradatum-knowledge-base-usage/` — L1 pure-logique : routage entre le vault et l'index de
  code dérivé, règle search-before-write, triage signal → section, formule d'acceptation du
  curateur.
- `skills/gradatum-feature-eval/` — L1 **PROPOSE-ONLY** : auto-évaluation périodique des features
  réellement exploitées (utilisée / sous-utilisée / sans télémétrie / en friction / cassée) puis
  propositions priorisées. Ne modifie jamais le produit.

### Added — couche L0 lecture (set indispensable)
- `skills/gradatum-vault-read/` — L0 atomique : lit le contenu COMPLET d'une note par chemin —
  outil MCP natif `mcp__gradatum__vault_read`. Complément de vault-search (qui ne renvoie
  que des ULID). Output : path + section + sha256 + corps markdown.
- `skills/gradatum-lessons-recall/` — L0 atomique : recall des leçons F-60 par classe —
  outil MCP natif `mcp__gradatum__vault_lessons_recall` (12 classes contrôlées). Recall JIT
  avant un gate à risque.
- `skills/gradatum-vault-timeline/` — L0 atomique : requête temporelle du vault —
  outil MCP natif `mcp__gradatum__vault_timeline` (fenêtre epoch ms, filtre `Static`/`Event`).

### Changed — migration MCP-native, premier lot
- `skills/gradatum-vault-read/`, `skills/gradatum-lessons-recall/`, `skills/gradatum-vault-timeline/`
  — appel direct de l'outil MCP au lieu du wrapper shell (les 3 scripts d'origine, qui compactaient
  la réponse via un parseur JSON, sont retirés). Coût mesuré à ce lot : perte de compaction côté
  client (+83 % `lessons-recall`, +53 % `vault-timeline` par appel). *Périmètre de ce lot
  uniquement : les skills restants ont migré depuis — voir l'entrée du 2026-08-01 ci-dessus.*

### Added — couche L1 capture
- `skills/gradatum-memorize/` — L1 pure-logique : décide QUOI persister durablement (décision/leçon/
  analyse/post-mortem/résultat) + route vers la bonne section canonique, puis délègue à
  /gradatum-vault-write (via vault-search anti-doublon → vault-read sha → vault-write). Symétrique de
  skill-reminder (chercher) côté écrire.

### Added — couche L0 code
- `skills/gradatum-code-map/` — L0 atomique : interroge la carte de code dérivée d'un projet
  (vault `code-<projet>`, extraction tree-sitter, zéro LLM). Modes `query` / `symbol` / `path` +
  option corps exact. Budget de tokens adaptatif, marqueurs de troncature affichés, garde de charset
  sur le nom de vault (`^code-[a-z0-9-]+$`). Pattern à 2 passes (signatures, puis corps sur les
  symboles retenus). La mise à jour de l'index est une opération d'administration côté serveur.

### Added — couche L0 écriture
- `skills/gradatum-vault-write/` — L0 atomique : écriture vault, modes **create** (note neuve) et
  **update** in-place (RMW : identifiant de note + hash attendu ; un hash périmé fait échouer
  l'écriture au lieu de l'appliquer, ce qui impose de relire la note fraîche avant de réessayer).
  Écriture asynchrone : l'accusé de mise en file ne vaut pas succès, l'état se lit en pollant le job
  jusqu'à ce que son champ `terminal` soit vrai. Garde anti-doublon (chercher avant créer).

### Security
- Aucun secret n'est lu, nommé ni transporté par ce dépôt. L'authentification vers le serveur
  `gradatum` est portée par la configuration du serveur MCP du harnais ; les skills ne connaissent
  ni jeton, ni chemin de fichier de credential.
- La surface d'appel de chaque skill est bornée par son champ `allowed-tools`.

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
- Workflow CI du dépôt (placeholder)
