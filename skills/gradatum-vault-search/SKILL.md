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

3. **Si N=0** : pas d'historique vault **classé** sur ce sujet — ce n'est pas un échec.

4. **Preuve d'absence (`corpus_match_count`)** — usage avancé, off par défaut. La recherche est
   **hybride** (lexicale BM25/FTS5 ∪ sémantique vectorielle) : les `N` résultats incluent **toujours**
   des voisins sémantiques. Conséquence attendue (cas nominal, pas une anomalie) : sur une query dont
   aucun mot n'est dans le corpus, on observe `N>0` (voisins sémantiques) **avec** `corpus_match_count=0`.
   Donc `N>0` ne prouve jamais qu'une note traite réellement du sujet. Activer cette preuve d'absence
   seulement quand le besoin est strict : avant d'affirmer « on n'a jamais écrit le terme X », ou un
   anti-doublon sur un terme court/ambigu (acronyme, nom propre) — pour un titre descriptif normal,
   `N` + scores suffisent (ne pas payer le coût systématiquement).

   Activation : `GRADATUM_INCLUDE_CORPUS_COUNT=1` (gradatum **≥ v0.5.2**). La sortie ajoute alors
   `corpus_match_count=<n>` = nombre de **matchs lexicaux** (BM25/FTS5) de la query dans tout le corpus
   — compteur **lexical**, indépendant du ranking et **découplé de `N`**.
   - `corpus_match_count=0` ⇒ **aucun match lexical** : absence prouvée du terme. Les résultats
     affichés (même si `N>0`, cas attendu) sont exclusivement des voisins sémantiques → à écarter
     pour un « a-t-on déjà ce terme ? ».
   - `corpus_match_count>0` ⇒ des notes contiennent les termes. Si elles ne figurent pas dans le
     top-K affiché, elles ont été déclassées par le ranking — relancer **une nouvelle recherche**
     avec un `GRADATUM_REMINDER_TOP_K` plus élevé ou une query affinée (ce n'est pas un retour
     automatique : c'est un appel explicite supplémentaire, à faire seulement si le besoin le justifie).
   - Sur gradatum **< v0.5.2** le compteur est absent (ligne non affichée) — pas de preuve d'absence
     disponible, seulement l'absence de résultat classé.

## Variables d'environnement (optionnelles)

| Variable | Défaut | Description |
|---|---|---|
| `GRADATUM_SERVER_URL` | `http://<gradatum-server>` | URL du serveur gradatum |
| `GRADATUM_API_KEY_FILE` | `/etc/gradatum/claude-code.api-key` | Fichier contenant la clé API |
| `GRADATUM_REMINDER_TOP_K` | `10` | Nombre max de résultats retournés |
| `GRADATUM_REMINDER_LOG` | `0` | `1` pour activer le log dans `/tmp/gradatum-reminder-stats.log` |
| `GRADATUM_INCLUDE_CORPUS_COUNT` | `0` | `1` → ajoute `corpus_match_count` (preuve d'absence ; gradatum ≥ v0.5.2) |

## Erreurs

Si gradatum :19090 retourne une erreur HTTP (5xx, timeout, 404) ou si l'échange JWT échoue,
le script propage le code d'erreur en stderr. L'agent décide quoi faire (retry manuel, ignore).

Pas de fallback dans le scope du script — les fallbacks sont gérés par gradatum-server côté serveur.

## Exemples d'invocation

```bash
# Recherche full-text
/gradatum-vault-search "architecture skills renommage 2026-05"

# Recherche par section (via variable d'env non encore supportée dans search.sh v1 — passer dans la query)
/gradatum-vault-search "decisions gradatum pivot 2026-05"

# Anti-doublon avant écriture
/gradatum-vault-search "pattern gradatum primary source unique"
```
