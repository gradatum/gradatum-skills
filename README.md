# gradatum-skills

> Plugin Claude Code (Apache-2.0) — skills atomiques + métamémoire pour `gradatum`.

Composition L1 (logique de décision) → L0 (appel d'outil MCP atomique). Stateless.

Les skills n'embarquent **aucun script, aucun binaire, aucune dépendance locale** : chaque skill L0
nomme un outil MCP du serveur `gradatum` et le harnais l'appelle. Le transport, l'authentification
et le format de réponse appartiennent au serveur MCP, pas à ce dépôt.

## Skills disponibles

| Skill | Niveau | Rôle | Statut |
|---|---|---|---|
| `/gradatum-vault-search` | L0 | Recherche dans le vault — outil MCP `mcp__gradatum__vault_search`. Ne renvoie que des chemins + scores, pas le corps des notes. | ✅ LIVRÉ |
| `/gradatum-vault-read` | L0 | Lit le contenu COMPLET d'une note par chemin — outil MCP `mcp__gradatum__vault_read`. Complément de vault-search. | ✅ LIVRÉ |
| `/gradatum-lessons-recall` | L0 | Recall des leçons apprises par classe — outil MCP `mcp__gradatum__vault_lessons_recall`. Recall juste-à-temps avant un gate à risque. | ✅ LIVRÉ |
| `/gradatum-vault-timeline` | L0 | Requête temporelle du vault — outil MCP `mcp__gradatum__vault_timeline` (fenêtre epoch ms, `Static`/`Event`). | ✅ LIVRÉ |
| `/gradatum-vault-write` | L0 | Écriture vault — outils MCP `mcp__gradatum__vault_write` + `mcp__gradatum__job_status`. Création, ou mise à jour in-place sous verrou optimiste (identifiant de note + hash attendu). Écriture asynchrone : le résultat se lit en pollant l'état du job. | ✅ LIVRÉ |
| `/gradatum-code-map` | L0 | Interroge la carte de code dérivée d'un projet (vault `code-<projet>`, extraction tree-sitter) — outil MCP `mcp__gradatum__code_scope`. Comprendre/naviguer du code sans lire les fichiers entiers. La mise à jour de l'index est une opération d'administration côté serveur, pas une opération MCP. | ✅ LIVRÉ |
| `/gradatum-memorize` | L1 | Décide QUOI persister durablement + route vers la bonne section, délègue à `/gradatum-vault-write`. Symétrique de skill-reminder (écrire vs chercher). Pure logique. | ✅ LIVRÉ |
| `/gradatum-skill-reminder` | L1 | Métamémoire auto-déclenchée — détermine si le contexte courant nécessite une recherche vault, délègue à `/gradatum-vault-search`. Pure logique de décision. | ✅ LIVRÉ |
| `/gradatum-knowledge-base-usage` | L1 | Guide de routage entre le vault (décisions, council, architecture, debug) et l'index de code dérivé. Porte la règle search-before-write, le triage signal → section et les conventions d'écriture. | ✅ LIVRÉ |
| `/gradatum-feature-eval` | L1 | Auto-évaluation périodique des features réellement exploitées, puis propositions priorisées. **PROPOSE-ONLY** : ne modifie jamais le produit, rend un rapport. | ✅ LIVRÉ |
| `gradatum-desktop` | MCP-only | Variante consolidée pour **Claude Desktop** via connecteur MCP (Streamable HTTP + Bearer). Search-before-write, triage des sections, gatekeeper, prudence sur les outils destructifs. Les autres skills déclarent `compatibility: claude-code` et ciblent l'invocation par slash-command du harnais. | ✅ LIVRÉ |

### /gradatum-vault-search (L0)

Recherche dans le vault gradatum.

**Output** : des chemins de notes (`<section>/<ulid>`) et leurs scores — **jamais le corps des
notes**. L'étape suivante naturelle est `/gradatum-vault-read` sur un chemin retenu. Le format
exact appartient à l'outil MCP ; il n'est plus mis en forme par ce dépôt.

**Invoquer quand** : réflexion sur un sujet traité, anti-doublon avant écriture, recherche explicite.

### /gradatum-skill-reminder (L1 — logique décision)

Déclencheur métamémoire basé sur des règles de décision CHERCHE/SKIP.

**CHERCHE** si le prompt est : question, brainstorming, diagnostic, planification, amorce de tâche substantielle.

**SKIP** si : validation seule ("oui", "go"), commande directe, slash-command, trivial.

**Sections canoniques** : la liste et la sémantique des sections ont pour **autorité unique le skill
`/gradatum-vault-write`**, lui-même reflet des sections que le serveur expose. Elles ne sont ni
recopiées ni comptées ici : une liste dupliquée dérive en silence. Ce README en portait une copie
de onze noms, dont trois ne désignaient plus rien et quatre sections réelles manquaient — sans que
rien ne le signale.

## Roadmap

Livré : tous les skills du tableau ci-dessus, en appel MCP natif. La liste installable fait
foi dans `.claude-plugin/plugin.json` — elle n'est comptée nulle part.

- **Atomiques L0 supplémentaires** — couvrir d'un skill les outils que le serveur expose et
  qu'aucun skill ne nomme encore. L'écart se constate en confrontant la liste que le serveur
  renvoie (`tools/list`) aux outils nommés dans les `SKILL.md` ; il n'est gravé nulle part ici.
- **Compatibilité multi-agent** — harnais autres que Claude Code (goose, gemini-cli, open-code).
  La contrainte n'est plus le shell mais la disponibilité d'un client MCP et d'un mécanisme de
  skills côté harnais.
- **Distribution** — installation par gestionnaire de plugins plutôt que par la synchronisation
  manuelle décrite ci-dessous.

## Pré-requis

- Un serveur `gradatum` joignable, et **un serveur MCP nommé `gradatum` configuré dans le harnais**,
  exposant les outils que les skills nomment dans leur champ `allowed-tools`.
- Pour **exécuter** les skills : aucune dépendance locale — ni `curl`, ni `jq`, ni runtime, ni
  script. Un skill est un document ; c'est le harnais qui appelle l'outil MCP.
- Pour **installer** par la procédure ci-dessous : `git` et `tar` (outils POSIX usuels).
- L'authentification (jeton, en-tête) est portée par la configuration du serveur MCP du harnais.
  Aucun skill de ce dépôt ne lit de secret ni ne nomme un chemin de fichier de credential.

Le script `tests/smoke/mcp-tools-live.sh` (voir « Vérifier que l'installation est opérationnelle »)
interroge un serveur joignable et vérifie que les outils nommés par les skills y existent. Il ne
prouve pas qu'ils sont appelables depuis votre client — cette seconde surface se fournit séparément.

## Installation (synchronisation depuis une référence commitée)

**Copies figées depuis un commit, jamais un symlink vers ce dépôt.** `git archive` lit l'objet
commit, pas le répertoire de travail — la commande ci-dessous installe donc toujours l'état
commité, même si le worktree a des modifications en cours.

C'est une **synchronisation**, pas une simple copie : elle installe les skills déclarés au
manifeste de la référence choisie **et retire** ceux qu'une installation précédente avait posés
et que le produit ne contient plus. Elle est idempotente — la relancer sans changement de
référence ne modifie rien.

> **Le champ `skills` de `.claude-plugin/plugin.json` n'est pas du poids mort.** Il est redondant
> pour le *chargement* — un harnais qui scanne `skills/` trouve les mêmes répertoires sans lui.
> Mais il est la **seule autorité sur la liste de candidats au retrait** (étape 3 ci-dessous) : la
> synchronisation ne connaît d'un skill que ce que deux manifestes en disent. Le supprimer parce
> qu'il « fait doublon » ne casse rien de visible à l'installation, et casse **silencieusement**
> le retrait des skills sortis du produit — qui resteront alors installés indéfiniment.

Variables, toutes optionnelles :

| Variable | Défaut | Rôle |
|---|---|---|
| `GRADATUM_SKILLS_REPO` | `$PWD` | clone de ce dépôt |
| `CLAUDE_SKILLS_DIR` | `$HOME/.claude/skills` | répertoire des skills du harness |
| `GRADATUM_SKILLS_REF` | `HEAD` | commit, tag ou branche à installer |

<!-- SYNC-INSTALL:BEGIN — bloc extrait et exécuté tel quel par tests/bats/install-sync.bats ; ne pas le dupliquer ailleurs -->
```bash
set -eu

REPO="${GRADATUM_SKILLS_REPO:-$PWD}"
DEST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
REF="${GRADATUM_SKILLS_REF:-HEAD}"
RECEIPT="$DEST/.gradatum-skills.installed"

mkdir -p "$DEST"

# 1. Manifeste de la référence à installer : seule autorité sur les noms de skills
#    du produit. Rien d'autre ne nomme un skill dans cette procédure.
WANTED=$(git -C "$REPO" show "$REF:.claude-plugin/plugin.json" \
  | awk '/"skills"[[:space:]]*:/{f=1} f{print} f && /\]/{exit}' \
  | grep -o '"\./skills/[^"/]*"' | tr -d '"' | sed 's|^\./skills/||' | sort -u)
if [ -z "$WANTED" ]; then
  echo "manifeste vide ou illisible à la référence $REF — abandon" >&2
  exit 1
fi

# 2. Installation : copie figée depuis l'objet commit, jamais le répertoire de travail.
set --
for s in $WANTED; do set -- "$@" "skills/$s"; done
git -C "$REPO" archive "$REF" "$@" | tar -x --strip-components=1 -C "$DEST"

# 3. Retrait des skills sortis du produit. Candidats = reçu de l'installation
#    précédente (lui-même une copie de manifeste) MOINS manifeste courant.
#    Le répertoire d'installation n'est JAMAIS balayé : un skill qui n'appartient
#    pas à ce produit n'est nommé par aucun manifeste, donc n'est jamais candidat.
if [ -f "$RECEIPT" ]; then
  OBSOLETE=$(sort -u "$RECEIPT" | grep -vxF "$WANTED" || true)
  for s in $OBSOLETE; do
    case "$s" in ''|.|..|*/*|.*) continue ;; esac
    if [ -L "$DEST/$s" ] || [ ! -d "$DEST/$s" ]; then continue; fi
    rm -rf -- "${DEST:?}/${s:?}"
    echo "retiré : $s"
  done
fi

# 4. Nouveau reçu — reflet exact du manifeste installé.
printf '%s\n' "$WANTED" > "$RECEIPT"
```
<!-- SYNC-INSTALL:END -->

### Ce que la synchronisation ne touche jamais

Le seul geste destructif est l'étape 3, et ses candidats sortent exclusivement de **deux
manifestes** : celui de l'installation précédente (le reçu `.gradatum-skills.installed`) et
celui de la référence installée. Un skill qui n'appartient pas à ce produit — quel que soit son
nom, y compris s'il commence par `gradatum-` — n'apparaît dans aucun des deux, donc dans aucune
liste de candidats, et survit à toute synchronisation. À la première installation, sans reçu,
rien n'est retiré.

Propriété vérifiée par red-proof dans `tests/bats/install-sync.bats` : un skill étranger est
posé dans un répertoire d'installation jetable, la synchronisation est lancée, sa survie est
asserée.

### Pourquoi pas un symlink

Un symlink transforme chaque écriture dans le dépôt en activation immédiate côté runtime : il
n'y a plus de délai entre modifier et exécuter, donc plus de fenêtre pour un commit, une revue
ou un verdict de revue — les gates du projet supposent tous ce délai, le symlink le supprime
en silence.

### Vérifier que l'installation est opérationnelle

Deux vérifications indépendantes, exécutables sans droits particuliers :

```bash
# 1. Conformité — chaque skill du manifeste est installé à l'identique de la
#    référence commitée (diff récursif, sortie 1 au premier écart).
bash tests/verify-install.sh

# 2. Atteignabilité — chaque outil MCP nommé par un SKILL.md existe dans la liste
#    exposée par le serveur. La liste attendue est lue sur l'entrée standard ou
#    sur un fichier ; elle n'est jamais gravée dans le vérificateur.
bash tests/smoke/mcp-tools-live.sh        # interroge le serveur, puis vérifie
bash tests/verify-mcp-tools.sh --tools ma-liste.txt   # liste déjà obtenue
```

« Installé » et « opérationnel » sont deux propriétés distinctes : la première ne dit rien d'un
skill qui nomme un outil que le serveur n'expose pas.

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

Trois leviers concourent au déclenchement systématique : la `description` du `SKILL.md` (que le
harnais lit pour décider d'invoquer), la règle harnais ci-dessus, et une mention au démarrage de
session. Le premier seul ne suffit pas.

## Architecture

Voir `ARCHITECTURE.md`.

## Tests

```bash
# Suite unitaire complète (hors réseau, exécutable par un consommateur externe)
cd tests/bats && bats ./*.bats

# Vérificateurs d'installation (voir « Vérifier que l'installation est opérationnelle »)
bash tests/verify-install.sh
bash tests/verify-mcp-tools.sh --tools <fichier>

# Smoke E2E contre un serveur gradatum joignable
bash tests/smoke/end-to-end.sh
bash tests/smoke/mcp-tools-live.sh
```

## Licence

Apache-2.0 — voir `LICENSE`.

