---
name: gradatum-vault-write
description: >
  Écrit une note dans le vault gradatum (LIVE :19090) — CRÉATION d'une note neuve ou MISE À JOUR
  in-place d'une note existante (RMW : note_id + sha256). Invoquer pour persister durablement une
  décision, une leçon, une analyse, un compte-rendu. AVANT de créer : chercher d'abord
  (/gradatum-vault-search) pour éviter un doublon — si une note couvre déjà le sujet, la METTRE À
  JOUR (update) plutôt que d'en créer une seconde. L'écriture est asynchrone (le script attend la
  confirmation). Le corps markdown est passé sur stdin.
type: gradatum
compatibility: claude-code (>= 2.1.0)
argument-hint: "create --section <s> --title <t> [--tags a,b]  (corps sur stdin)"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/write.sh *)
---

# /gradatum-vault-write

> ⚠️ **DRAFT — NON ACTIF** (non enregistré dans `plugin.json`, pas de symlink). Bloqué tant que
> le bug **F-41** n'est pas corrigé : un `update` avec `sha256` périmé est correctement **rejeté**
> (données protégées, pas d'écrasement) mais le job retourne `Done` au lieu de `Conflict` — l'appelant
> ne peut donc PAS détecter le rejet (no-op silencieux). Une promesse de concurrence-safety
> *observable* est requise avant d'activer ce skill d'écriture. Suivi : finding debug F-41 + gov-todo P1.

Outil atomique d'écriture dans le vault gradatum. Deux modes : **create** (note neuve) et
**update** (MAJ in-place d'une note existante).

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

Pour modifier une note existante SANS créer de doublon :

1. Lire la note d'abord : `/gradatum-vault-read "<section>/<ulid>"` → récupérer le **`sha256`**.
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
| `✅ Done note_id=<ulid>` | job terminé sans erreur | 0 |
| `⚠️ Conflict` | sha périmé (état cible — **NON surfacé actuellement, cf F-41**) | 2 |
| `❌ Failed/DLQ` | écriture échouée | 3 |
| `⏳ job non terminal après timeout` | poll épuisé — vérifier l'état | 4 |

> ⚠️ **Limitation F-41 (à corriger)** : un `update` avec `sha256` périmé retourne `Done` (pas
> `Conflict`) ALORS QUE la note n'est PAS modifiée (silent no-op, données protégées). Tant que F-41
> n'est pas corrigé : après un `update`, **re-lire via vault-read** pour confirmer que la modification
> a bien été appliquée (sha/corps changés). Ne pas se fier au seul `Done`.

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
