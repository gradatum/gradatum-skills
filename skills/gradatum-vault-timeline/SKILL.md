---
name: gradatum-vault-timeline
description: >
  Interroge le vault gradatum (LIVE :19090) selon l'axe TEMPOREL — liste les notes par
  fenêtre de temps (bornes en epoch millisecondes), filtrable par type (`Static` faits durables /
  `Event` événements). Invoquer pour « qu'a-t-on décidé/changé entre telle et telle date ? »,
  reconstruire une chronologie, ou récupérer l'état d'un sujet à une période donnée (as-of) —
  par le TEMPS, pas par pertinence sémantique (≠ /gradatum-vault-search). Composable par
  /gradatum-skill-reminder.
type: gradatum
compatibility: claude-code (>= 2.1.0)
argument-hint: "[from_epoch_ms] [to_epoch_ms] [doc_kind:Static|Event]"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/timeline.sh *)
---

# /gradatum-vault-timeline

Outil atomique de requête temporelle. Là où /gradatum-vault-search classe par pertinence,
timeline classe par **temps** — pour les questions « quand » et les chronologies.

## Quand invoquer

- « Qu'a-t-on décidé / changé entre <date1> et <date2> ? »
- Reconstituer la chronologie d'un milestone / d'une période.
- Récupérer l'état *à une période donnée* (as-of) plutôt que la note la plus pertinente.
- Distinguer les **faits durables** (`Static`) des **événements** (`Event`) sur une fenêtre.

## Usage

```bash
# Tout (ordre temporel)
/gradatum-vault-timeline

# Fenêtre temporelle (epoch MILLISECONDES, bornes incluses)
/gradatum-vault-timeline 1717200000000 1717800000000

# Filtrer par type
/gradatum-vault-timeline 1717200000000 1717800000000 Event
```

`from_epoch_ms` / `to_epoch_ms` sont des **timestamps epoch en millisecondes** (pas secondes).
Les deux sont optionnels (absence = pas de borne de ce côté). `doc_kind` ∈ {`Static`, `Event`}.

## Output

```
🕰️ N entrée(s) :
  <anchor_ms epoch> | <doc_kind> | <ulid> — <titre>
  ...
```

Ou `🕰️ 0 entrée sur cette fenêtre`. L'ancre est l'epoch ms brut (`anchor_ms`).

## Comment décider (interprétation)

1. Les entrées sont ordonnées par `anchor_ms` (ancre temporelle de la note).
2. `Static` = fait durable (décision, architecture) ; `Event` = événement daté (incident,
   livraison). Filtrer selon la question.
3. Pour le détail complet d'une entrée → /gradatum-vault-read sur son ULID.

## Variables d'environnement

| Variable | Défaut | Description |
|---|---|---|
| `GRADATUM_SERVER_URL` | `http://<gradatum-server>` | URL du serveur gradatum |
| `GRADATUM_API_KEY_FILE` | `/etc/gradatum/claude-code.api-key` | Fichier de la clé API |

## Anti-patterns

- Ne pas utiliser pour une recherche par pertinence (→ /gradatum-vault-search).
- Ne pas confondre `anchor_ms` (epoch **millisecondes**) avec des secondes.
