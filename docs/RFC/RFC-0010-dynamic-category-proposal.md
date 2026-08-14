---
rfc: RFC-0010
title: Dynamic category proposal & promotion
status: Draft
author: '@gradatum-maintainer'
created: 2026-05-10
updated: 2026-05-10
version: 1
depends_on:
  - RFC-0001  # multi-tag classification (gradatum-skills) — base classifier
  - RFC-0007  # confidence ladder (gradatum-skills) — pattern promotion réutilisable
related_to:
  - RFC-0003  # consolidate KB distillation (gradatum-skills) — concepts émergents
  - libskills:RFC-0001  # Constitution iron law + Quarantaine (pattern promotion)
required_by: []
category: skill
scope: gradatum-curator + les sections canoniques du serveur
artefact: TBD (proposition à clarifier avec opérateur)
license: Apache-2.0
---

# RFC-0010 — Dynamic category proposal & promotion

> **TL;DR (Draft)** — Aucun RFC actuel ne couvre la création/promotion **dynamique** de catégories de classification (ex: nouvelle section de vault au-delà des 11 canoniques actuelles, ou nouveau tag de skill). RFC-0001 fait du multi-tag sur catégories fixes, RFC-0003 détecte des concepts émergents, RFC-0007 promote des notes individuelles. Trou identifié 2026-05-10. Cette RFC propose un mécanisme de proposition + promotion de nouvelles catégories quand le curator détecte des clusters récurrents qui débordent une catégorie hétérogène. **Orientation à clarifier opérateur avant `Discussion` :** catégories canoniques (les sections canoniques du serveur) vs tags libres vs sous-catégories per-projet.

---

## 1. Motivation

État actuel (Phase 2.0c) :
- `gradatum-curator` classifie les notes parmi **sections canoniques** (sections canoniques du serveur : architecture, decisions, council, debug, reasoning, feedback, lessons-learned, retrospectives, experiments, agent-issues, reference)
- Les sections sont **fixes** — toute extension nécessite un une revue de gouvernance
- RFC-0001 (multi-tag) ajoute le multi-classe sur ces 11 sections, mais ne crée pas de nouvelles sections

**Constats émergents (à valider par dogfooding ≥3 mois)** :
- Certaines catégories deviennent **hétérogènes** (ex: `agent-issues` mélange "issues comportementales agents" + "incidents prod" + "sécurité findings")
- L'opérateur **classe à la main** dans `decisions` des notes qui auraient mérité une catégorie distincte (ex: `incidents`, `security-findings`, `governance`)
- Les **tags secondaires** s'accumulent et révèlent des clusters stables qui pourraient devenir des sections à part entière

**Problème** : extension manuelle des sections via une revue de gouvernance est **lourde** et **rétroactive**. On ajoute une section quand le besoin a déjà créé du désordre.

**Cette RFC propose** un mécanisme amont qui :
1. **Détecte** les clusters de tags qui débordent une section hétérogène (sur N notes en M jours, seuils à définir)
2. **Propose** une nouvelle catégorie au format `{nom-court}` avec justification statistique (X notes affectées, Y% de réduction d'hétérogénéité)
3. **Promote** après validation (une revue de gouvernance — toujours required pour extension §10) ou cycle alternatif (auto-promotion à seuil + signalement)

---

## 2. Orientation à clarifier (UNRESOLVED — bloquant `Discussion`)

Trois interprétations possibles de "catégories dynamiques" — l'opérateur doit trancher avant que ce RFC passe `Draft → Discussion` :

### Option A — Catégories canoniques les sections canoniques du serveur dynamiques

Étendre **les 11 sections canoniques** dynamiquement (12e section, 13e, ...).
- **Pour** : alignement avec l'architecture du vault, sections = invariants fondamentaux
- **Contre** : les sections canoniques du serveur est verrouillée une revue de gouvernance (seuil max post 2026-05-09). Toute auto-extension viole le verrou. Solution = proposer mais validation humaine obligatoire (pas auto-promotion).
- **Granularité** : grosse maille (chaque section impacte tout le système)

### Option B — Tags libres organisés en taxonomie émergente

Permettre à l'opérateur (ou au curator) de **créer dynamiquement des tags** qui s'organisent en taxonomie hiérarchique sans toucher aux 11 sections fixes.
- **Pour** : flexibilité maximale, pas de verrou, dogfooding rapide
- **Contre** : risque de prolifération chaotique (drift "tag soup"). Demande mécanisme de canonicalisation/dédup
- **Granularité** : fine (1 tag par concept)

### Option C — Sous-catégories per-projet

Chaque projet (`gradatum`, `gradatum-skills`, `monarch`, etc.) déclare ses propres **sous-catégories** au sein des 11 sections canoniques (ex: `agent-issues:gradatum:curator`, `agent-issues:monarch:tui`).
- **Pour** : isolation par projet, pas de drift transversal, alignement avec multi-tenant `tenant_id`
- **Contre** : complexité requête (besoin de filtre `section + sub-category`), risque de duplication de patterns inter-projets
- **Granularité** : moyenne (per-projet)

---

## 3. Design (TBD — fonction de l'orientation Option A/B/C)

À compléter une fois l'opérateur a tranché Option A vs B vs C.

---

## 4. Migration impact

À compléter (fonction de l'orientation).

---

## 5. Alternatives considered

- **Statu quo** : continuer avec les sections actuelles + extensions ponctuelles via une revue de gouvernance. Inconvénient : réactif, pas proactif.
- **Catégorisation par projet uniquement** (Option C seule) : trop limitatif pour patterns transversaux.
- **Taxonomie pré-définie exhaustive** : impossible (catégories émergent du dogfooding réel).

---

## 6. Drawbacks

- Complexité ajoutée au curator (analyse statistique clusters tags)
- Risque drift si auto-promotion sans gate humaine (cf les sections canoniques du serveur verrou)
- Nécessite ≥3 mois dogfooding réel pour calibrer seuils détection clusters

---

## 7. Unresolved questions

1. **Orientation amont** : Option A, B, ou C ? (BLOQUANT `Discussion`)
2. Seuils détection cluster : combien de notes / quelle période / quel taux d'hétérogénéité ?
3. Mécanisme validation : 100% une revue de gouvernance (option A) ou auto-promotion à seuil + signalement (options B/C) ?
4. Rétroactivité : appliquer le mécanisme aux notes existantes ou seulement aux nouvelles ?
5. Cohabitation gradatum (multi-tenant `tenant_id`) : catégories tenant-scoped ou globales ?
6. Trace : note `decisions/` dans le vault à chaque promotion de catégorie (cf §9-bis.f Trace) ?

---

## Status note

Ce RFC est en **status `Draft` initial — orientation amont non encore validée par l'opérateur**. Il est listé dans `docs/RFC/README.md` table comme `Draft` pour visibilité, mais ne passera `Discussion` qu'après clarification §2 (Option A/B/C).

Origine : trou identifié 2026-05-10 lors de l'analyse synthèse des 9 RFCs gradatum-skills, après que l'opérateur ait demandé "quel RFC permet d'ajouter des catégories dynamiquement ?". Réponse : aucun. Cette RFC ferme le trou en proposant le draft initial pour discussion.
