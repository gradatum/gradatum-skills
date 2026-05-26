---
rfc: RFC-0002
title: Contribution enrichments to gradatum self-improvement RFC
status: Draft
author: '@the operator'
created: 2026-05-08
updated: 2026-05-10
version: 1
depends_on: []
required_by: []
related_to:
  - gradatum:RFC-0005
category: proposal
scope: gradatum-engine
crates_touched: []
phase_target: meta (proposal layer, no crates)
tracking_issue: pending — for discussion at next gradatum:RFC-0005 re-evaluation
license: Apache-2.0
---

# RFC-0002 — Contribution enrichments to gradatum self-improvement RFC

## Status note

This document is a **documented contribution note** (apport pré-council) — it does NOT define a new feature on its own. It proposes three additive enrichments to the gradatum self-improvement RFC (`gradatum:RFC-0005`) based on analysis of two prior ex-specs (#5 Skill Mining + #6 Skill Registry). It targets the next council re-evaluation of `gradatum:RFC-0005` and is captured here for traceability.

The gradatum self-improvement RFC targets Phase 3+ (≥6 months post-D5). This contribution can wait.

---

## 1. Pourquoi cette note

Le 2026-05-08, deux specs ont été produites en parallèle de la documentation native Gradatum :

- ex-spec #5 — Skill Mining (détection de patterns récurrents dans la KB consolidée pour produire des skills candidats)
- ex-spec #6 — Skill Registry (couche neutre stockage/exposition des skills, pattern ports & adapters)

Une lecture postérieure du RFC self-improvement Gradatum (`gradatum:RFC-0005`) révèle que ces deux specs sont entièrement couvertes par les phases du RFC :

- Spec #5 ↔ self-improvement Phase 2 (Analyze) : détection clusters + scoring 6 critères
- Spec #6 ↔ self-improvement Phase 3 (Propose) + §7 (validation interface)

Plutôt que de créer deux RFCs redondants, cette note propose **trois apports concrets** qui peuvent enrichir `gradatum:RFC-0005` sans bouleverser sa structure ni son scope. Le RFC garde sa numérotation et son auteur d'origine.

---

## 2. Apport 1 — Décomposition explicite producer / registry

### 2.1 État actuel du RFC self-improvement

Le RFC self-improvement décrit les trois phases (Observe / Analyze / Propose) comme un pipeline linéaire. La Phase 3 produit des « capability drafts » qui sont ensuite soumis à un mécanisme de validation externe (§7).

L'architecture interne de la Phase 3 n'est pas décomposée. Le draft est implicitement produit par un seul composant qui fait tout : détection → génération → stockage → exposition.

### 2.2 Apport proposé

Décomposer Phase 3 selon le pattern ports & adapters :

```
Phase 2 outputs
        │
        ▼
   Producer trait              (interface entrée)
        │
        ▼ submit(candidate, source)
   Capability Registry         (couche neutre)
   ├─ Storage (markdown + index)
   ├─ Lifecycle FSM (candidate → drafted → validated → ...)
   ├─ Validation cross-source (détection duplicates entre producers)
   └─ Versioning (semver per capability)
        │
        ▼ get / list / search / subscribe
   Consumer trait              (interface sortie)
   ├─ External validation (operator review, council Art.19, threshold auto)
   ├─ Agent runtime consumer
   └─ Export tool
```

### 2.3 Bénéfices

- **Producers interchangeables.** Phase 2 (auto-mining) n'est plus le seul fournisseur. À terme, on peut ajouter : création manuelle UI, import externe (Anthropic skills, vaults tiers Gradatum, vault-mem v1.6.x predecessor en migration). Chacun implémente le même `Producer` trait.
- **Consumers découplés.** L'external validation (§7 du RFC self-improvement) devient un Consumer parmi d'autres. Idem pour des futurs consumers (skill executor, MCP server gateway).
- **Évolution sans casse.** Ajouter un producer ou un consumer = nouvelle impl, pas une modification du registry.

### 2.4 Modification suggérée du RFC self-improvement

Insertion d'une nouvelle sous-section §6.6 « Producer/Registry/Consumer decomposition (architectural pattern) » dans Phase 3. Aucune modification de §7 (validation) — celui-ci devient un Consumer par implémentation.

---

## 3. Apport 2 — Lifecycle FSM explicite

### 3.1 État actuel du RFC self-improvement

Le RFC self-improvement §5.5 mentionne les status `under_threshold | eligible | rejected | drafted`. §6 ajoute la production de drafts. La transition entre ces status n'est pas formalisée.

### 3.2 Apport proposé

Formaliser une FSM explicite :

```
        ┌─────────────────┐
        │ Phase 2 cluster │
        └────────┬────────┘
                 │
        ┌────────▼─────────┐
        │ scorer 6-criteria │
        └────────┬─────────┘
                 │
   ┌─────────────┼──────────────┬────────────────┐
   ▼             ▼              ▼                ▼
[under_threshold] [eligible] [rejected]  (auto-promote ≥ threshold)
                     │            │              │
                     │ Phase 3    │              │
                     ▼            │              │
                 [drafted]        │              │
                     │            │              │
                     ▼            │              │
              [validated]         │              │
                     │            │              │
                     ▼            │              │
              [active]            │              │
                     │            │              │
        deprecate()  │            │              │
                     ▼            │              │
              [deprecated] ◄──────┴──────────────┘
```

### 3.3 Garde-fous transitions

- Toute transition est auditée (qui, quand, raison) dans `audit_log` (`gradatum:RFC-0005` §17.6).
- Une transition `active → deprecated` requiert une raison explicite.
- Suppression définitive (`deleted`) requiert confirmation à 2 facteurs + tombstone Git.
- Réactivation possible : `deprecated → eligible` avec audit.

### 3.4 Modification suggérée du RFC self-improvement

Ajout d'une nouvelle sous-section §6.7 « Capability lifecycle FSM » avec le diagramme + les garde-fous.

---

## 4. Apport 3 — Format pivot frontmatter normalisé

### 4.1 État actuel du RFC self-improvement

`gradatum:RFC-0005` Phase 3 produit des artefacts (procédures formelles, patterns, références consolidées) sans spécifier un format de frontmatter normalisé. Le storage (§17.1) mentionne `/var/lib/gradatum/self-improvement/drafts/*.md` mais sans schéma.

### 4.2 Apport proposé

Définir un frontmatter normalisé pour tous les artefacts produits par self-improvement, indépendant du producer. Cela facilite :

- Validation cross-source (Apport 1) — détecter qu'un draft auto-miné et un import externe parlent de la même chose
- Évolution future (UI, export) — un seul schéma à apprendre
- Diff / merge entre versions

### 4.3 Schéma proposé

```yaml
---
# === Section 1: Identité ===
capability: "configure-rocm-vulkan-radeon"   # slug unique kebab-case
title: "Configure ROCm + Vulkan sur Radeon RDNA"
type: procedural                              # procedural | declarative | analytical | narrative | relational | meta

# === Section 2: Périmètre ===
scope: "Setup ROCm 6.x + Vulkan backend pour AMD RDNA 3.x"
prerequisites:
  - "[[ubuntu-24-04]]"
  - "[[gpu-amd-rdna]]"
applicable_to:
  - "[[radeon-8060s]]"

# === Section 3: Provenance ===
source:
  type: mining                                # mining | manual | import
  producer: "self-improvement-phase2"
  producer_version: "0.1.0"
  source_data:                                # producer-specific
    cluster_id: "..."
    notes: ["...", "..."]
  imported_from: null                         # if type=import: origin format

# === Section 4: Mining metadata (if producer=mining) ===
mining:
  recurrence_count: 3
  cohesion: 0.81
  signals_at_extraction: 2026-05-08T10:00:00Z

# === Section 5: Eligibility ===
eligibility:
  composite_score: 0.78
  scorer_version: v0.1.0
  per_criterion:
    recurrence: 0.9
    discriminating_trigger: 0.7
    universal_applicability: 0.8
    reproducibility: 0.85
    added_value: 0.7
    stability: 0.65

# === Section 6: Lifecycle ===
status: validated                             # cf. FSM §3.2
created_at: 2026-05-08T10:00:00Z
last_modified_at: 2026-05-08T14:32:00Z
last_reviewed_at: 2026-05-08T14:32:00Z
reviewed_by: "the operator"
deprecated_reason: null

# === Section 7: Versioning ===
version: "0.1.0"                              # semver per capability
git_commit: "abc123def"
---
```

### 4.4 Modification suggérée du RFC self-improvement

Ajout d'une nouvelle sous-section §10.3 « Capability frontmatter schema » avec ce format. La sous-section §10.2 existante (storage) peut référencer ce schéma sans la dupliquer.

---

## 5. Validation cross-source — bonus

Si l'Apport 1 (Producer/Registry/Consumer) est retenu, la validation cross-source devient un cas d'usage concret. Quand deux producers soumettent des capabilities similaires, le Registry doit détecter et proposer une résolution. Sinon, les imports massifs ou les producers simultanés pollueraient la base.

### 5.1 Détection de similarité

Au moment de chaque submit :

- Match exact sur slug → rejet immédiat (collision de nom)
- Match sémantique sur title + scope (cosine via bge-small-en-v1.5) → seuil 0.90 = duplicate potentiel
- Match sur prerequisites + applicable_to → indicateur de scope identique

### 5.2 Résolution

| Cas | Action recommandée |
|---|---|
| Producer = même que existant | UseExisting (ignore submission, retour silencieux) |
| Producer différent, contenu très proche | MergeProposal (création draft de fusion, revue humaine) |
| Scope partiellement différent | KeepBothDistinct (acceptation avec rename auto) |
| Capability existante deprecated | Replace (remplace l'ancienne après confirmation) |

Cet apport est conditionnel à l'Apport 1. Si la décomposition Producer/Registry n'est pas retenue, la validation cross-source perd son intérêt.

---

## 6. Synthèse — modifications proposées à gradatum:RFC-0005

| Section RFC self-improvement | Modification | Statut |
|---|---|---|
| §6 Phase 3 — Propose | Ajout §6.6 Producer/Registry/Consumer decomposition | Apport 1 |
| §6 Phase 3 — Propose | Ajout §6.7 Capability lifecycle FSM | Apport 2 |
| §10 Technical architecture | Ajout §10.3 Capability frontmatter schema | Apport 3 |
| §6 Phase 3 — Propose | Ajout §6.8 Cross-source validation (conditionnel à §6.6) | Bonus |

Aucune modification destructive. Tous les apports sont additifs et n'invalident pas le contenu existant de `gradatum:RFC-0005`.

---

## 7. Décision attendue

Cette note est un **apport pré-council**. Trois suites possibles :

1. **Council décide d'intégrer les apports** → modifications appliquées à `gradatum:RFC-0005`, statut maintenu `proposal`
2. **Council décide de n'intégrer qu'une partie** → cherry-pick par apport, justification logguée
3. **Council décide de ne pas intégrer** → cette note reste comme trace historique, `gradatum:RFC-0005` reste en l'état

Aucune urgence : `gradatum:RFC-0005` cible Phase 3+ (≥6 mois post-D5). La discussion peut attendre la maturité de Phase 2.

---

## 8. Sources

- ex-spec #5 — `gradatum-spec-05-skill-mining-v02.docx` (2026-05-08, 469 paragraphes)
- ex-spec #6 — `gradatum-spec-06-skill-registry.docx` (2026-05-08, 545 paragraphes)
- `gradatum:RFC-0005` — Self-improvement RFC (2026-05-05, 609 lignes, statut `proposal`)
- Gradatum architecture: `ARCHITECTURE.md`
- `PROJECT-CONTEXT.md`, `AGENTS.md`

---

## Changelog

| Date | Author | Change |
|---|---|---|
| 2026-05-08 | @the operator | Initial creation from ex-specs #5+#6 analysis, status: Draft |
| 2026-05-10 | opérateur | Migration NAS → gradatum-skills public repo, renumérotation RFC-SKILL-GRADATUM-0005 → RFC-0002, table header → YAML frontmatter, refs mises à jour |

---

## License

This RFC is published under Apache-2.0, aligned with the Gradatum project.

---

*End RFC-0002.*
