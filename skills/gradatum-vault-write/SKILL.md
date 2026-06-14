---
name: gradatum-vault-write
description: >
  Écrit une note dans le vault gradatum (LIVE :19090) — CRÉATION ou MISE À JOUR in-place (RMW).
  RÈGLE OBLIGATOIRE : avant toute création, invoquer /gradatum-vault-search d'abord — si une note
  couvre déjà le sujet, faire un UPDATE (note_id + sha256) plutôt que de créer un doublon.
  Usage : persister durablement une décision, une leçon, une analyse, un compte-rendu.
  Corps markdown sur stdin. L'écriture est asynchrone (poll jusqu'à confirmation).
type: gradatum
compatibility: claude-code (>= 2.1.0)
argument-hint: "create --section <s> --title <t> [--tags a,b]  (corps sur stdin)"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/write.sh *)
---

# /gradatum-vault-write

Outil atomique d'écriture dans le vault gradatum. Deux modes : **create** (note neuve) et
**update** (MAJ in-place d'une note existante, **concurrence-safe** via optimistic-lock sha256).

## Avant d'écrire : anti-doublon (OBLIGATOIRE)

Avant une CRÉATION, chercher d'abord avec /gradatum-vault-search sur le sujet. Si une note couvre
déjà le sujet → **METTRE À JOUR** cette note (mode `update`), ne PAS créer un doublon. Le vault doit
rester une source unique par sujet, pas une accumulation de variantes.

## Mode CREATE

```bash
/gradatum-vault-write create --section decisions --title "Choix du reranker BGE-v2-m3" --tags reranker,search <<'BODY'
## Contexte
...corps markdown...
BODY
```

- `--section` : une des 11 sections canoniques (ci-dessous).
- `--title` : titre factuel et spécifique (verbe + objet + résultat).
- `--tags` : liste `a,b,c` (optionnel — le curator peut en ajouter).
- **Corps** : sur stdin (heredoc `<<'BODY' ... BODY`).

## Mode UPDATE (in-place, RMW concurrence-safe)

> ⚠️ **ATTENTION** : le corps fourni **REMPLACE le corps ENTIER** de la note. Envoyer la version
> complète et finale — pas un diff, pas un extrait. Un corps partiel **détruit silencieusement** les
> sections non transmises (le serveur accepte, exit 0).

Pour modifier une note existante SANS créer de doublon :

1. Lire la note d'abord : `/gradatum-vault-read "<section>/<ulid>"` → récupérer le **`sha256`** ET le
   **corps actuel complet** (pour composer la version de remplacement intégrale).
2. Écrire avec le `note_id` + le `sha256` lu :

```bash
/gradatum-vault-write update --note-id 01KV2P38DTQ0V9H9581GF0RVTQ --sha <sha256-lu> --title "<titre inchangé>" --tags ... <<'BODY'
...corps modifié intégral...
BODY
```

- `--sha` = le `sha256` retourné par vault-read (optimistic-lock F-41). Si la note a changé entre la
  lecture et l'écriture → job **`Conflict`** (la note n'est PAS écrasée) → re-lire, ré-appliquer.
- Le corps fourni REMPLACE le corps entier (fournir la version complète, pas un diff).

## 11 sections canoniques

`architecture` · `decisions` · `council` · `debug` · `reasoning` · `feedback` · `lessons-learned` ·
`retrospectives` · `experiments` · `agent-issues` · `reference`

## Comportement asynchrone

`vault_write` est **asynchrone** : le script poste (HTTP 202) puis attend (poll) la confirmation
jusqu'à un état terminal. Output :

| Sortie | Sens | Exit |
|---|---|---|
| `✅ Done note_id=<ulid>` | écrit | 0 |
| `⚠️ Conflict` | `sha256` périmé : une écriture concurrente a eu lieu → la note n'est PAS modifiée. Re-lire via /gradatum-vault-read pour le sha frais, ré-appliquer la modification, ré-écrire. | 2 |
| `❌ Failed/DLQ` | écriture échouée | 3 |
| `⏳ job non terminal après timeout` | poll épuisé — vérifier l'état | 4 |

## Variables d'environnement

| Variable | Défaut | Description |
|---|---|---|
| `GRADATUM_SERVER_URL` | `http://<gradatum-server>` | URL du serveur gradatum |
| `GRADATUM_API_KEY_FILE` | `/etc/gradatum/claude-code.api-key` | Fichier de la clé API |

## Anti-patterns

- Ne JAMAIS créer une note sans chercher d'abord (doublon).
- Ne JAMAIS faire un `update` sans le `sha256` frais de la note (concurrence-safe).
- Ne pas écrire de contenu éphémère (détails de debug jetables, état de session) — le vault est durable.
- Le titre doit être spécifique : « Note sur X » est un mauvais titre.
- Ne JAMAIS deviner la section sans consulter les 11 sections canoniques ci-dessus — une décision
  rangée dans `debug`, ou un fait d'architecture dans `decisions`, casse le routage sémantique des
  recherches futures (la section est la dimension de routage principale).
