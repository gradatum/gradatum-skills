---
rfc: RFC-0009
title: Success criteria measurable in RFCs — boomerang plan vs reality
status: Draft
author: opérateur (Gradatum maintainer)
created: 2026-05-09
updated: 2026-05-10
version: 1
project: gradatum
phase_target: meta-process (applicable immédiatement à toutes nouvelles RFC + rétroactivement aux RFC actives)
depends_on: []
required_by:
  - all future RFC-XXXX
related_to:
  - gradatum:RFC-0001
crates_touched:
  - aucun (changement de processus + RFC-TEMPLATE.md)
license: Apache-2.0
---

# RFC-0009 — Success criteria measurable in RFCs

> **TL;DR** — Modifie `RFC-TEMPLATE.md` Gradatum pour exiger des **critères de succès chiffrés** dans toute RFC : F1w cible, latence cible, RAM cible, tout autre métrique pertinente. Mesure obligatoire à la sortie de la phase d'implémentation. Si la métrique est ratée : décision documentée (accepter, ré-itérer, abandonner). Pattern boomerang qui ferme la boucle plan→implémentation→validation et empêche les RFC "définies par l'intention" sans mesure.

---

## 1. Contexte Gradatum

Le processus RFC actuel de Gradatum (cf. `gradatum:RFC-0001`) impose un template structuré. Les RFC produites jusqu'ici contiennent typiquement :

- Mission / Motivation / Scope.
- Design détaillé.
- Workflow et examples.
- Edge cases / Failure modes.
- Migration / Rollback.
- Validation : critères fonctionnels (oui/non) + critères qualitatifs ("acceptable", "OK").

**Ce qui manque** : des **critères chiffrés mesurables** qui permettent de répondre, après implémentation, à la question *"l'objectif a-t-il été atteint ?"*

Conséquence : une RFC peut être "implémentée" et "mergée" sans que l'on puisse jamais affirmer si elle a livré la valeur promise. La boucle plan → implémentation → mesure → décision est ouverte.

RFC-0009 ferme cette boucle.

---

## 2. Mission

Sa fonction unique : **imposer dans chaque nouvelle RFC Gradatum une section "Success Criteria" avec critères chiffrés, et un mécanisme de boomerang qui revient mesurer effectivement ces critères à la sortie de la phase d'implémentation**.

Trois principes :

1. **Critères chiffrés obligatoires** : pas de "acceptable", "raisonnable", "bon". Chiffres concrets.
2. **Mesure obligatoire à exit phase** : étape "Validation chiffrée" dans le workflow merge.
3. **Décision documentée si raté** : pas de bypass silencieux. Accepter (avec justification) / ré-itérer / abandonner.

> **Inspiration** : pattern "boomerang" gstack (initialement RFC-SKILL #5 candidat, retiré côté skills, **maintenu et formalisé côté Gradatum** parce que pertinent pour un projet à métriques claires comme un memory backbone).

---

## 3. Motivation

### 3.1 Le problème actuel

Sans critères chiffrés, la validation d'une RFC dépend du jugement subjectif post-merge. Trois symptômes typiques :

1. **Drift silencieux** : "Cette feature devait améliorer la latence" → mergée → personne ne mesure → 6 mois plus tard, latence en réalité dégradée.
2. **Sur-promesse impunie** : RFC promet "réduction RAM 50%" sans plan de mesure → impossible de vérifier.
3. **Décision-non-décision** : si l'objectif est raté, le projet n'a pas de mécanisme structuré pour décider quoi faire.

### 3.2 Pourquoi côté Gradatum (et pas côté skills)

Gradatum est un projet à **métriques claires** :

- Latence search (p50, p95, p99) en ms.
- Throughput insertions par seconde.
- Empreinte RAM par locus.
- Taille DB par 100k notes.
- Précision/recall search (F1w score).

À l'inverse, les RFC skills agent (`/office-hours`, `/cso`, etc.) ont des métriques bien plus diffuses — d'où la décision de réserver le pattern à Gradatum.

### 3.3 Pourquoi imposer dans le template

Section **obligatoire** dans le template. La friction d'écriture est précisément la valeur — elle force le rédacteur à se poser la question.

### 3.4 Pourquoi mesure obligatoire à exit phase

Sans étape de mesure, les critères deviennent décoratifs. Imposer un workflow :

1. RFC mergée avec critères § Success Criteria.
2. À exit phase : **mesure** des critères + comparaison à la cible.
3. Décision : ✓ atteint / ⚠ partiel / ✗ raté.
4. Si non-atteint : ré-itération ou décision d'acceptation explicite.

Le résultat est commit dans `docs/rfc-validation/<rfc-id>-<phase>.md`.

---

## 4. Scope

### 4.1 In scope

- Modification de `RFC-TEMPLATE.md` Gradatum : ajout section "Success Criteria" obligatoire.
- Format normatif des critères chiffrés (métrique, baseline, cible, méthode de mesure, fenêtre temporelle).
- Workflow de validation à exit phase : commit `docs/rfc-validation/<rfc>-phase-N.md`.
- Format normatif du rapport de validation (atteint / partiel / raté + décision).
- Application **immédiate à toutes nouvelles RFC** post-merge.
- Application **rétroactive aux RFC déjà mergées** mais pas encore implémentées.

### 4.2 Out of scope

- **Système de tracking automatique** des métriques (Grafana, Prometheus dashboards dédiés) : exclu pour v1.
- **Dashboards d'historique cross-RFC** : reportée.
- **Validation de RFC déjà implémentées** : exclue — coût rétroactif trop élevé.
- **Application aux RFC SKILL agent** : hors scope (cf. §3.2).

### 4.3 Non-objectifs

- RFC-0009 ne **garantit pas** que les RFC futures atteindront leurs cibles. Elle garantit seulement que la **mesure** sera faite.
- RFC-0009 n'**impose pas** un nombre minimum de critères. Une RFC peut avoir 1 critère central. Mais la section ne peut pas être vide.

---

## 5. Design

### 5.1 Format de la section "Success Criteria" (texte normatif)

Toute RFC Gradatum doit inclure une section dédiée :

```markdown
## X. Success Criteria

> Critères chiffrés mesurables qui définissent le succès de cette RFC.
> À mesurer à exit de la phase d'implémentation correspondante.

### X.1 Critères obligatoires (≥1, peut être plus)

| # | Métrique | Baseline (avant) | Cible (après) | Méthode de mesure | Fenêtre |
|---|---|---|---|---|---|
| SC1 | <métrique> | <valeur référence> | <valeur cible> | <comment mesurer> | <quand> |

### X.2 Critères secondaires (optionnel, ≥0)

[idem, métriques nice-to-have]

### X.3 Anti-objectifs (régressions à éviter)

| # | Métrique | Seuil de régression toléré | Méthode |
|---|---|---|---|
| AO1 | <métrique non-cible mais à protéger> | <max régression acceptable> | <comment> |

### X.4 Plan de mesure

- **Outils** : <bench harness, prometheus query, etc.>
- **Environnement** : <local dev / CI runner / staging>
- **Reproductibilité** : <comment d'autres pourraient re-mesurer>
- **Données de référence** : <dataset, fixtures>
```

#### Exemples de métriques bien formées

```markdown
| # | Métrique | Baseline | Cible | Méthode | Fenêtre |
|---|---|---|---|---|---|
| SC1 | Latence search p95 | 47 ms | < 30 ms | bench `gradatum-server-bench search` 10k samples | exit Phase 3.3 |
| SC2 | RAM resident process gradatum-server | 312 MB | < 280 MB | mesure `ps -o rss` après warmup 60s | exit Phase 3.3 |
| SC3 | F1w score sur corpus eval-ref | 0.78 | ≥ 0.82 | `gradatum-bench eval --corpus=eval-ref` | exit Phase 3.4 |
```

#### Exemples de métriques mal formées (refusées par template)

| Métrique | Pourquoi refusé |
|---|---|
| "Latence améliorée" | Pas de chiffre. |
| "RAM acceptable" | Subjectif. |
| "Performance OK" | Vague + pas de métrique. |
| "Tests passent" | Tautologique (déjà critère fonctionnel). |
| "Code lisible" | Subjectif, qualitatif sans seuil. |

### 5.2 Format du rapport de validation

Fichier : `docs/rfc-validation/<rfc-id>-phase-<N>.md`

```markdown
---
rfc: RFC-XXXX
phase: <N>
validation_date: 2026-MM-DD
validator: opérateur
implementation_pr: #N
status: atteint | partiel | raté
---

# Validation — RFC-XXXX — Phase <N>

## 1. Critères mesurés

| # | Métrique | Baseline | Cible | Mesuré | Δ | Statut |
|---|---|---|---|---|---|---|
| SC1 | ... | ... | ... | ... | ... | ✓ atteint |

## 2. Anti-objectifs

| # | Métrique | Seuil régression | Mesuré | Statut |
|---|---|---|---|---|
| AO1 | ... | ... | ... | ✓ |

## 3. Statut global

[atteint | partiel | raté]

## 4. Méthode et reproductibilité

[Détails outils, environnement, dataset]

## 5. Décision (obligatoire si pas "atteint")

[Décision : Accepter / Ré-itérer / Abandonner + justification]

## 6. Observations qualitatives

[3-5 lignes]

## 7. Prochaine validation prévue

[Si la RFC a plusieurs phases]
```

### 5.3 Workflow boomerang

```text
[RFC en draft]
   ↓
[opérateur rédige § Success Criteria avec critères chiffrés]
   ↓
[RFC reviewée + mergée (status: accepted)]
   ↓
[Phase d'implémentation démarre]
   ↓
[Exit Phase atteint]
   ↓
[opérateur exécute les mesures planifiées]
   ↓
[opérateur rédige docs/rfc-validation/<rfc>-phase-N.md]
   ↓
[Statut atteint / partiel / raté établi]
   ↓
[Si pas atteint : décision documentée]
   ↓
[Commit + tag de la RFC : phase-N-validated]
```

### 5.4 Modifications `RFC-TEMPLATE.md`

Ajout section obligatoire avec note :

```markdown
## X. Success Criteria

> **OBLIGATOIRE** depuis RFC-0009 (2026-05-09).
> Toute RFC sans critères chiffrés sera retournée en révision.
```

### 5.5 Gate CI optionnel (extension future)

Pour les phases d'implémentation, un job CI peut vérifier la présence de `docs/rfc-validation/<rfc>-phase-N.md`. Pour v1, le mécanisme est **discipliné, pas enforced** par CI.

### 5.6 Application rétroactive aux RFC actives

Pour les RFC actuellement actives mais pas encore en phase d'implémentation :

- RFC-0007 (curator confidence ladder) : status Draft, modifier draft pour ajouter Success Criteria avant merge.
- RFC-0008 (audit-noise allowlist) : status Draft, idem.

---

## 6. Workflow d'application

### 6.1 Workflow d'écriture RFC

```text
[opérateur initie RFC]
   ↓
[copie RFC-TEMPLATE.md → docs/RFC/RFC-XXXX-<slug>.md]
   ↓
[remplit sections Mission, Motivation, ..., Design]
   ↓
[atteint section Success Criteria]
   ↓
[se demande : "comment je saurai si cette RFC a réussi ?"]
   ↓
[formule ≥1 critère chiffré avec méthode de mesure]
   ↓
[review opérateur ou contributeur]
   ↓
[si critères vagues : reviewer demande chiffres concrets]
   ↓
[merge RFC]
```

### 6.2 Workflow décision si raté

```text
[critère SC2 raté]
   ↓
[options :]
   ├─ (a) Accepter le résultat → justifier + mettre à jour RFC (status: accepted-with-deviation)
   ├─ (b) Ré-itérer → ouvrir RFC mineure RFC-XXXX-bis
   └─ (c) Abandonner → status RFC : "abandoned" + post-mortem
```

---

## 7. Edge cases

| Cas | Comportement attendu |
|---|---|
| RFC très exploratoire (pas de baseline existant) | Baseline = "n/a (composant nouveau)", cible définie en absolu. |
| RFC sans impact perf direct (ex: doc, refacto interne) | Critères peuvent être "réduction nombre de modules de 12 à 8" ou "100% des sites d'appel migrés". |
| RFC multi-phases avec critères différents par phase | Section Success Criteria peut sectionner par phase. |
| Mesure impossible techniquement à exit phase | Refus à la review : reformulation requise. |
| RFC abandonnée en cours d'implémentation | Rapport marqué `status: abandoned-mid-implementation`. |

---

## 8. Failure modes

| Mode | Symptôme | Mitigation |
|---|---|---|
| Critères "performatifs" (chiffrés mais bidons) | "Latence p95 < 1000 ms" sur composant qui fait toujours <50 ms | Reviewer humain doit catch. |
| Mesure orientée pour atteindre cible | Bench design biaisé | Plan de mesure doit être détaillé et reproductible. |
| Décision "Accepter" systématique sur ratés | Discipline contournée | `/retro` Gradatum-aware peut compter ratio "accepter sans action" / total ratés. |
| Rapport de validation jamais commit | Validation non-traçable | `/retro` détecte manque rapport. |

---

## 9. Alternatives considérées

### 9.1 Critères qualitatifs autorisés (sans chiffres)

**Rejetée** : exactement le problème. Force chiffrage.

### 9.2 Section optionnelle dans le template

**Rejetée** : sera vide la moitié du temps. Obligatoire = effective.

### 9.3 Validation faite par CI uniquement (sans rapport humain)

**Rejetée pour v1** : nécessite infrastructure CI bench mature. Hybridation préférée. Possible v2 partielle.

### 9.4 Application aussi aux RFC SKILL agent

**Rejetée** : §3.2. Les skills agent ont des métriques diffuses, pattern moins applicable.

### 9.5 Boomerang plus complet (incl. mesure 6 mois post-merge)

**Rejetée pour v1** : trop ambitieux. Validation à exit phase = première étape.

---

## 10. Drawbacks et open questions

### 10.1 Drawbacks acceptés

- **Friction d'écriture** : section supplémentaire à remplir. Acceptée — c'est la valeur.
- **Coût mesure** : exit phase nécessite bench setup. Acceptée — investissement infra paye sur durée projet.
- **Risque de mesures bidons** : §8 mitigation par reviewer.
- **Application non-rétroactive aux RFC déjà implémentées** : dette acceptée.

### 10.2 Open questions

- **Format dashboard cross-RFC** : agréger tous les rapports `docs/rfc-validation/` en vue synthétique. Reportée.
- **Intégration avec `/retro`** : `/retro global` pourrait lire ces rapports et signaler patterns. À ajouter post-RFC.
- **Critères standard pour catégories de RFC** : bibliothèque "critères types pour RFC perf", "critères types pour RFC API" ? Reportée.
- **Lien avec versioning sémantique** : si une RFC vise une cible perf et la rate, est-ce un breaking change ?
- **Détection automatique de drift** : si après merge une métrique se dégrade, alerte. Hors scope v1.

---

## 11. Conformité constitutionnelle (libskills:RFC-0001)

RFC-0009 est une RFC **meta-process**. Conformité indirecte : empêche les RFC "définies par l'intention" qui produisent des fixes non-mesurés.

---

## 12. Migration

### 12.1 État actuel

- `RFC-TEMPLATE.md` Gradatum existe, ne contient pas de section Success Criteria.
- Aucune RFC mergée n'a de section Success Criteria.
- Aucun répertoire `docs/rfc-validation/`.

### 12.2 Étapes de migration

**Phase 0** — Cette RFC mergée :

1. Modification `RFC-TEMPLATE.md` : ajout section Success Criteria.
2. Modification `CONTRIBUTING.md` : note explicite "section obligatoire depuis RFC-0009".
3. Création `docs/rfc-validation/` avec README explicatif.

**Phase 1** — Application aux RFC actives non-implémentées :

4. RFC-0007 (curator confidence ladder) + RFC-0008 (audit-noise allowlist) : ajouter section avant merge.

**Phase 2** — Application aux nouvelles RFC :

5. Toute RFC créée post-merge RFC-0009 doit avoir section. Pas d'exception.

### 12.3 Rollback

Retirer la section du template, retirer mention CONTRIBUTING. Les rapports de validation existants restent (utiles).

---

## 13. Acceptance criteria

| # | Criterion | Method | Expected |
|---|---|---|---|
| C1 | RFC-TEMPLATE.md contient section Success Criteria | Inspection fichier | présente |
| C2 | CONTRIBUTING.md mentionne obligation | Inspection | présent |
| C3 | docs/rfc-validation/ existe avec README | Inspection | présent |
| C4 | RFC-0007 mise à jour avec Success Criteria avant merge | Diff RFC-0007 | section ajoutée |
| C5 | RFC-0008 idem | Diff RFC-0008 | section ajoutée |

**Success criteria de cette RFC elle-même** :

| # | Métrique | Baseline | Cible | Méthode | Fenêtre |
|---|---|---|---|---|---|
| SC1 | % des nouvelles RFC avec section Success Criteria | 0% | 100% | inspection toutes RFC mergées post-merge RFC-0009 | 90 jours post-merge |
| SC2 | Nombre de rapports de validation produits | 0 | ≥ 3 | comptage `ls docs/rfc-validation/*.md` | 180 jours post-merge |
| SC3 | % de critères ratés ayant décision documentée | n/a | 100% | inspection rapports status=raté | 180 jours post-merge |

---

## 14. References

- **gstack** : pattern boomerang plan vs reality (initialement RFC-SKILL #5 candidat, retiré côté skills, transposé ici).
- **gradatum:RFC-0001** — Versioning Gradatum et processus RFC (modifié par cette RFC).
- **DORA Metrics** — concept de mesure objective post-deployment.
- **OKR (Objectives and Key Results)** — pattern proche (objectif + key results mesurables).

---

## Changelog

| Date | Author | Change |
|---|---|---|
| 2026-05-09 | opérateur | Création initiale, status: Draft, version 1, meta-process applicable immédiatement |
| 2026-05-10 | opérateur | Migration NAS → gradatum-skills public repo, renumérotation RFC-SKILL-GRADATUM-0012 → RFC-0009, refs mises à jour (`gradatum:RFC-0001`) |

---

## License

Cette RFC est publiée sous licence Apache-2.0, alignée sur le projet Gradatum. Elle s'inspire intellectuellement du projet gstack (garrytan/gstack, MIT) sans en reprendre le code source.

---

*End RFC-0009.*
