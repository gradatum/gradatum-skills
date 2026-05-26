---
name: gradatum-vault-search
description: >
  Recherche dans le vault gradatum (LIVE :19090) — invoquer en réflexion
  ("ai-je déjà une note sur X ?", "on a tranché ce sujet ?", "je vais proposer/décider/écrire"),
  recherche explicite ("trouve les notes sur Y"), planification, brainstorming,
  avant toute écriture vault (anti-doublon). Output compact ULID + score.
  Composable par /gradatum-skill-reminder.
type: gradatum
compatibility: claude-code (>= 2.1.0)
argument-hint: "<query sémantique>"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/search.sh *)
---

# /gradatum-vault-search

Outil atomique de recherche dans le vault gradatum. Réutilisable par
n'importe quel skill L1 (reminder, memorize) ou agent en réflexion.

## Quand invoquer

- Réflexion sur un sujet potentiellement déjà traité (avant proposition / décision / planification)
- Recherche explicite demandée par l'utilisateur ou un autre skill
- Vérification anti-doublon avant écriture vault (futurs skills L1 d'écriture)
- Composition par /gradatum-skill-reminder sur prompt utilisateur non trivial

## Usage

!`${CLAUDE_SKILL_DIR}/scripts/search.sh "$ARGUMENTS"`

## Output format

Le script renvoie une ligne unique :

```
🧠 N notes : <ulid-26> [<score>], <ulid-26> [<score>], ...
```

Ou si aucun résultat :

```
🧠 0 note pertinente sur ce sujet
```

| Élément | Signification |
|---|---|
| `🧠 N` | N notes vault retournées par gradatum pour la query |
| `<ulid-26>` | ID note — utilisable avec `mcp__gradatum__vault_read` |
| `[<score>]` | Score de pertinence BM25 (plage variable selon version gradatum) |

## Comment décider (interprétation par l'agent)

1. **Vérifier "déjà connu"** : si l'ULID figure déjà dans le contexte conversationnel courant
   (grep mental), tu as déjà cette info — pas besoin de relire.

2. **Action de lecture** : invoquer `mcp__gradatum__vault_read` avec `note_id="<ulid>"`
   pour récupérer le contenu détaillé d'un résultat pertinent.

3. **Si N=0** : pas d'historique vault sur ce sujet — ce n'est pas un échec.

## Variables d'environnement (optionnelles)

| Variable | Défaut | Description |
|---|---|---|
| `GRADATUM_SERVER_URL` | `http://<gradatum-server>` | URL du serveur gradatum |
| `GRADATUM_API_KEY_FILE` | `/etc/gradatum/claude-code.api-key` | Fichier contenant la clé API |
| `GRADATUM_REMINDER_TOP_K` | `10` | Nombre max de résultats retournés |
| `GRADATUM_REMINDER_LOG` | `0` | `1` pour activer le log dans `/tmp/gradatum-reminder-stats.log` |

## Erreurs

Si gradatum :19090 retourne une erreur HTTP (5xx, timeout, 404) ou si l'échange JWT échoue,
le script propage le code d'erreur en stderr. L'agent décide quoi faire (retry manuel, ignore).

Pas de fallback dans le scope du script — les fallbacks sont gérés par gradatum-server côté serveur.

## Exemples d'invocation

```bash
# Recherche full-text
/gradatum-vault-search "council Art.19 renommage skills 2026-05"

# Recherche par section (via variable d'env non encore supportée dans search.sh v1 — passer dans la query)
/gradatum-vault-search "decisions vault-mem gradatum pivot 2026-05"

# Anti-doublon avant écriture
/gradatum-vault-search "leader-override the maintainer gradatum primary"
```
