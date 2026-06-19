---
name: gradatum-lessons-recall
description: >
  Rappelle les leçons du vault gradatum pour une CLASSE à risque (deploy/release/migration/anti-leak/auth-secrets/data-integrity…) — recall JIT F-60 avant action risquée. Output compact ULID+titre+snippet. Non bloquant. Composable par gradatum-skill-reminder et gates sécurité.
type: gradatum
compatibility: claude-code (>= 2.1.0)
argument-hint: "<classe> [limit]"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/recall.sh *)
---

# /gradatum-lessons-recall

Outil atomique de rappel des leçons par classe (F-60). Le pendant LECTURE de la boucle
d'apprentissage : on rappelle une leçon au moment où elle s'applique, plutôt que de compter
sur la mémoire.

## Quand invoquer

- **Au déclenchement d'un gate à risque** : avant un deploy → classe `deploy` ; avant une
  release → `release` ; avant une migration → `migration` ; etc. Le recall JIT évite de
  répéter une erreur de la même classe.
- En réflexion sur une action appartenant clairement à une classe (ci-dessous).

## Classes contrôlées (12)

`deploy` · `release` · `migration` · `crates-io` · `anti-leak` · `api-external` · `archi` ·
`git-hygiene` · `ci-cd` · `auth-secrets` · `data-integrity` · `process-discipline`

Une classe hors-liste retourne une erreur 400 (vocabulaire fermé).

## Usage

```bash
/gradatum-lessons-recall "deploy"
/gradatum-lessons-recall "auth-secrets" 5
```

`limit` (optionnel, défaut 5) borne le nombre de leçons retournées.

## Output

```
🎓 N leçon(s) [classe=deploy] :
  <ulid> — <titre> :: <snippet>
  ...
```

Ou `🎓 0 leçon pour la classe <classe>` si aucune leçon codifiée n'existe encore.

## Comment décider (interprétation)

1. Chaque leçon retournée est une **méthodologie** ou une **anticipation** réutilisable —
   l'appliquer à l'action en cours, pas la copier aveuglément.
2. `0 leçon` ≠ « aucun risque » : juste qu'aucune leçon de cette classe n'est encore capturée.
3. Le recall est **best-effort non bloquant** : une erreur de recall ne doit pas empêcher
   l'action (mais elle est signalée).

## Variables d'environnement

| Variable | Défaut | Description |
|---|---|---|
| `GRADATUM_SERVER_URL` | `http://<gradatum-server>` | URL du serveur gradatum |
| `GRADATUM_API_KEY_FILE` | `/etc/gradatum/claude-code.api-key` | Fichier de la clé API |

## Anti-patterns

- Ne pas inventer une classe hors des 12 — le serveur rejette (400).
- Ne pas utiliser pour une recherche libre (→ /gradatum-vault-search) : recall est class-scopé.
- Ne pas bloquer une action sur un échec de recall (best-effort).
