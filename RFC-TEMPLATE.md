---
rfc: RFC-XXXX
title: "<Short descriptive title>"
status: Draft
author: "<author handle or name>"
created: YYYY-MM-DD
updated: YYYY-MM-DD
version: 1
project: gradatum
phase_target: "<Phase X+ or meta-process>"
depends_on: []
required_by: []
related_to: []
crates_touched: []
license: Apache-2.0
---

# RFC-XXXX — <Title>

> **TL;DR** — One paragraph summary: what it does, why it matters, what it produces.

---

## 1. Context

What the current state of the system is that motivates this RFC. Reference the relevant crate(s) and their current behavior.

---

## 2. Mission

What this RFC defines and its unique function. Keep to 3-5 sentences.

> **Inspiration** (if applicable): upstream pattern or RFC this adapts from.

---

## 3. Motivation

### 3.1 The problem

Why this is needed. What goes wrong without it. Quantify if possible.

### 3.2 Why this approach

Explain the design rationale.

---

## 4. Scope

### 4.1 In scope

- Bullet list of what this RFC covers.

### 4.2 Out of scope

- What is explicitly excluded and why.

### 4.3 Non-objectives

- Things this RFC does NOT guarantee.

---

## 5. Design

### 5.1 Core behavior (normative text)

The system MUST / SHOULD / MAY... (normative language).

Describe the observable behavior, traits, SQL schemas, workflows.

### 5.2 New traits / types (if applicable)

```rust
// Example trait definition
```

### 5.3 New SQL tables (if applicable)

```sql
-- Migration XXXX_<name>.sql
```

### 5.4 New endpoints (if applicable)

```
GET /api/v1/...
POST /api/v1/...
```

---

## 6. Impact downstream

| Component | Impact | Effort |
|---|---|---|
| `gradatum-<crate>` | Description | ~XXX LOC |
| Schema | N new tables + 1 migration | — |

Public API surface impact: ...

---

## 7. Migration path

N/A — additive only. OR describe migration steps.

```bash
# One-shot migration command if applicable
```

Rollback: describe how to undo.

---

## 8. Edge cases

| Case | Expected behavior |
|---|---|
| <case 1> | <behavior> |

---

## 9. Failure modes

| Mode | Symptom | Mitigation |
|---|---|---|
| <failure 1> | <symptom> | <mitigation> |

---

## 10. Alternatives considered

### 10.1 Alternative A

**Idea** : ...

**Rejected** : ...

---

## 11. Drawbacks and open questions

### 11.1 Accepted drawbacks

- <drawback 1> : accepted because ...

> **AM4 reminder:** the drawbacks section must be authored without AI assistance. The author should be able to defend it in a synchronous review without referring to generated text.

### 11.2 Open questions

- <question 1>

---

## 12. Constitutional conformance (libskills:RFC-0001)

- **Iron Law** : how this RFC interacts with or supports Iron Law.
- **Quarantaine** : what artefacts this RFC produces, their kind and initial status.

---

## 13. Success Criteria

> **OBLIGATOIRE** depuis RFC-0009 (2026-05-09).
> Toute RFC sans critères chiffrés sera retournée en révision.

### 13.1 Critères obligatoires (≥1)

| # | Métrique | Baseline (avant) | Cible (après) | Méthode de mesure | Fenêtre |
|---|---|---|---|---|---|
| SC1 | <métrique> | <valeur référence> | <valeur cible> | <comment mesurer> | <quand> |

### 13.2 Anti-objectifs (régressions à éviter)

| # | Métrique | Seuil de régression toléré | Méthode |
|---|---|---|---|
| AO1 | <métrique non-cible mais à protéger> | <max régression acceptable> | <comment> |

### 13.3 Plan de mesure

- **Outils** : <bench harness, prometheus query, etc.>
- **Environnement** : <local dev / CI runner / staging>
- **Reproductibilité** : <command to reproduce>
- **Données de référence** : <dataset, fixtures>

---

## 14. Migration

### 14.1 Migration steps

1. RFC merged and tagged `accepted` after review.
2. Implementation steps...

### 14.2 Rollback

```bash
# Rollback command
```

---

## 15. Acceptance criteria

| # | Criterion | Method | Expected |
|---|---|---|---|
| C1 | <criterion 1> | <how to verify> | <expected result> |

---

## 16. References

- **libskills:RFC-0001** — Constitution Iron Law + Quarantaine (required).
- **RFC-0009** — Success criteria measurable in RFCs (required).
- <additional references>

---

## 17. Changelog

| Date | Author | Change |
|---|---|---|
| YYYY-MM-DD | <author> | Initial creation, status: Draft |

---

## 18. License

This RFC is published under Apache-2.0, aligned with the Gradatum project.

---

*End RFC-XXXX.*
