---
name: gradatum-vault-timeline
description: >
  Interroge le vault gradatum (LIVE :19090) selon l'axe TEMPOREL — liste les notes par fenêtre de
  temps (bornes en epoch millisecondes), filtrable par type (`Static` faits durables / `Event`
  événements). Invoquer pour « qu'a-t-on décidé/changé entre telle et telle date ? »,
  reconstruire une chronologie, ou récupérer l'état d'un sujet à une période donnée (as-of) — par
  le TEMPS, pas par pertinence sémantique (≠ /gradatum-vault-search). Composable par
  /gradatum-skill-reminder.
type: gradatum
compatibility: claude-code (>= 2.1.0)
allowed-tools: mcp__gradatum__vault_timeline
---

# /gradatum-vault-timeline

Outil atomique de requête temporelle. Là où /gradatum-vault-search classe par pertinence,
timeline classe par **temps** — pour les questions « quand » et les chronologies. Tri serveur :
`anchor_ms DESC, note_id DESC`.

## Quand invoquer

- « Qu'a-t-on décidé / changé entre `<date1>` et `<date2>` ? »
- Reconstituer la chronologie d'un milestone / d'une période.
- Récupérer l'état **à une période donnée** (fenêtre d'ancres — voir la mise en garde `as_of_ms`
  ci-dessous, ce n'est PAS un filtrage de validité).
- Distinguer les **faits durables** (`Static`) des **événements** (`Event`) sur une fenêtre.

## Usage

Appeler directement l'outil **`mcp__gradatum__vault_timeline`** — tous les paramètres
(`from_ms`/`to_ms`, `doc_kind`, `limit`, `cursor`, `as_of_ms`, `include_expired`, `tenant_id`,
`vault_id`) sont optionnels. Leurs défauts et contraintes sont documentés par l'inputSchema de
l'outil — ne pas les recopier ici.

### ⚠️ Bornes epoch — toujours par commande, jamais de calcul mental

```bash
TZ="Europe/Paris" date -d "2026-07-10 00:00:00" +%s%3N          # début de fenêtre
TZ="Europe/Paris" date -d "2026-07-14 23:59:59.999" +%s%3N      # fin de fenêtre
```

### ⚠️ `as_of_ms` est exposé mais N'EST PAS un filtrage de validité utile

Le schéma de l'outil annonce un « filtre strict » (`anchor_ms ≤ T` **et** non expirée) distinct
d'un « filtre historique ». **Cette distinction est indiscernable dans les données réelles** : le
champ `valid_until_ms` (réservé fenêtrage temporel) n'est **jamais peuplé par le chemin
d'écriture live**.

Vérifié le 2026-07-31 sur le code source :

- Le chemin d'écriture live (`vault_write`) construit systématiquement l'entrée temporelle avec
  `valid_until_ms: None`, fixé **en dur**.
- Une fonction d'extraction capable de produire `Some(valid_until_ms)` à partir d'un champ
  `valid_until` en frontmatter existe bien dans le dépôt, mais elle n'est appelée **que par les
  tests**, jamais depuis le chemin d'écriture live.

⇒ Le prédicat `(valid_until IS NULL OR T < valid_until)` est donc **toujours vrai** en pratique.
Les deux branches (`as_of_ms` seul vs `as_of_ms` + `include_expired`) rendent **le même
résultat**. `as_of_ms` se réduit à un **plafond d'ancre**, strictement équivalent à `to_ms`.
`include_expired` est inerte.

**Ne pas présenter un résultat comme un état as-of validé.**

⚠️ **Coût mesuré le 2026-07-31** (council Art.19 Round 2, Bob) : depuis le retrait du script
`timeline.sh` (qui compactait la réponse via `jq`), l'appel direct de l'outil MCP coûte **+53 %
par appel** (1938 octets bruts vs 1265 octets compactés). Remède attendu : une projection
compacte côté serveur (pas encore livrée) ; en l'état, ce surcoût est structurel, pas un bug de
ce skill.

## Comment décider (interprétation)

1. Question **« quand »** ou chronologie → timeline. Question **« sur quoi »** → search.
   Sujet **et** temps → search avec `from_ms`/`to_ms` (ne pas doubler d'un appel timeline).
2. `next_cursor` présent dans la réponse ⇒ la fenêtre est **tronquée** : ne pas présenter le
   résultat comme exhaustif sans avoir paginé, ou dire explicitement qu'il est partiel.
3. Une note **sans** entrée `temporal_index` n'apparaît dans **aucune** fenêtre bornée. Un
   résultat vide ne prouve donc pas l'absence d'événement sur la période.

## Anti-patterns

- Ne pas calculer une borne epoch de tête — toujours `date +%s%3N`.
- Ne pas confondre secondes et millisecondes : un facteur 1000 place la fenêtre en 1970.
- Ne pas conclure « rien ne s'est passé » sur une fenêtre vide (voir §3).
- Ne pas utiliser pour chercher un sujet (→ /gradatum-vault-search).
- Ne pas présenter `as_of_ms` comme une garantie de validité temporelle — voir la mise en garde
  ci-dessus.
