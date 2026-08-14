---
name: gradatum-lessons-recall
description: >
  Rappelle les leçons du vault gradatum pour une CLASSE à risque (deploy/release/migration/anti-leak/auth-secrets/data-integrity…) — recall JIT F-60 avant action risquée. Output compact ULID+titre+snippet. Non bloquant. Composable par gradatum-skill-reminder et gates sécurité.
compatibility: claude-code (>= 2.1.0)
allowed-tools: mcp__gradatum__vault_lessons_recall
---

# /gradatum-lessons-recall

Outil atomique de rappel des leçons par classe (F-60). Le pendant LECTURE de la boucle
d'apprentissage : on rappelle une leçon au moment où elle s'applique, plutôt que de compter sur
la mémoire.

## Quand invoquer

- **Au déclenchement d'un gate à risque** : avant un deploy → classe `deploy` ; avant une
  release → `release` ; avant une migration → `migration` ; etc. Le recall JIT évite de répéter
  une erreur de la même classe.
- En réflexion sur une action appartenant clairement à une classe (ci-dessous).

## Classes contrôlées (vocabulaire fermé)

`deploy` · `release` · `migration` · `crates-io` · `anti-leak` · `api-external` · `archi` ·
`git-hygiene` · `ci-cd` · `auth-secrets` · `data-integrity` · `process-discipline`

Une classe hors-liste est rejetée (400) par le serveur.

## Usage

Appeler directement l'outil **`mcp__gradatum__vault_lessons_recall`** — requis : `class` (une
des classes ci-dessus). `limit`, `semantic`, `query`, `rank` sont documentés par l'inputSchema de
l'outil ; ne pas les recopier ici.

Deux comportements que le schéma documente mais qui méritent d'être soulignés avant l'usage,
pas après une surinterprétation du résultat :

- `semantic: true` peut **retomber silencieusement sur BM25** si l'embedding échoue. Ne pas
  présenter un résultat comme « recall sémantique » sur la seule foi du paramètre envoyé.
- `rank: "relevance"` est un **no-op** strictement équivalent à l'omission du champ — seul
  `rank: "recency-boosted"` change réellement l'ordre.

## Output

```
{ "items": [ { "path": "<section>/<ulid>", "title": "...", "snippet": "..." }, ... ] }
```

`items: []` = aucune leçon codifiée pour cette classe — pas une erreur.

⚠️ **Coût mesuré le 2026-07-31** : depuis le retrait du script
`recall.sh` (qui compactait la réponse via `jq`), l'appel direct de l'outil MCP coûte **+83 %
par appel** (2660 octets bruts vs 1454 octets compactés) — cause : snippets non tronqués et
`tags[]` exposés dans la réponse JSON brute. Remède attendu : une projection compacte côté
serveur (pas encore livrée) ; en l'état, ce surcoût est structurel, pas un bug de ce skill.

## Comment décider (interprétation)

1. Chaque leçon retournée est une **méthodologie** ou une **anticipation** réutilisable —
   l'appliquer à l'action en cours, pas la copier aveuglément.
2. **`items` vide ≠ « aucun risque »** : seulement qu'aucune leçon de cette classe n'est encore
   capturée. Ne jamais lire un recall vide comme un feu vert.
3. Le recall est **best-effort non bloquant** : un échec ne doit pas empêcher l'action — mais il
   doit être signalé, pas avalé.

## Anti-patterns

- Ne pas inventer une classe hors des 12 listées — rejet 400.
- Ne pas utiliser pour une recherche libre (→ /gradatum-vault-search) : le recall est
  class-scopé, pas une recherche générale.
- Ne pas bloquer une action sur un échec de recall (best-effort).
- Ne pas passer `query` sans `semantic: true` — il est ignoré, et croire l'avoir appliqué conduit
  à surinterpréter le résultat.
- Ne pas présenter un `semantic: true` comme garanti sémantique — repli BM25 silencieux possible.
