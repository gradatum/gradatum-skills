---
rfc: RFC-0008
title: Audit-noise allowlist appliquée à Gradatum CI (cargo-audit, cargo-deny)
status: Draft
author: opérateur (Gradatum maintainer)
created: 2026-05-09
updated: 2026-05-10
version: 1
project: gradatum
phase_target: Phase 2 (post alpha.5, alignement CI)
depends_on:
  - libskills:RFC-0008
required_by: []
related_to:
  - RFC-0007
crates_touched:
  - tous (config CI au root du workspace)
license: Apache-2.0
---

# RFC-0008 — Audit-noise allowlist appliquée à Gradatum CI

> **TL;DR** — Formalise l'usage de l'audit-noise allowlist (`libskills:RFC-0008` §4.5) côté CI Gradatum : `cargo audit`, `cargo deny`, et tout outil de scan futur doivent respecter une **allowlist unique versionnée** dans `docs/security/audit-noise-allowlist.md` au format Markdown structuré (justification + reviewer + date), avec **conversion automatique** vers les formats spécifiques outils (`deny.toml`, `audit.toml`). Une seule source de vérité, justification humaine obligatoire, re-review trimestrielle automatisée par CI.

---

## 1. Contexte Gradatum

État actuel CI Gradatum (référence : `.github/workflows/ci.yml` + `deny.toml` à la racine workspace) :

- `cargo deny check advisories` exécuté à chaque PR.
- `cargo deny check licenses` exécuté à chaque PR.
- `cargo deny check bans` (interdit certaines crates) exécuté à chaque PR.
- Quelques exemptions ponctuelles dans `deny.toml` ajoutées au fil du temps **sans justification systématique** ni date ni reviewer.

Exemple problème actuel dans `deny.toml` :

```toml
[advisories]
ignore = [
    "RUSTSEC-2024-0010",  # ?
    "RUSTSEC-2023-0071",  # ?
]
```

Aucune trace de **pourquoi**, **qui a décidé**, **quand re-évaluer**. Symétrique au problème décrit dans `libskills:RFC-0008` §2.4. La `libskills:RFC-0008` a défini la solution côté audit agent (`docs/security/audit-noise-allowlist.md`) ; cette RFC l'**applique strictement à Gradatum**.

---

## 2. Mission

RFC-0008 transforme le pattern audit-noise allowlist en **discipline contraignante côté CI Gradatum**. Sa fonction unique : **garantir que toute exemption d'audit (RUSTSEC, license, ban) dans Gradatum est justifiée écrite, signée par un reviewer, datée, et re-évaluée périodiquement**.

Trois principes :

1. **Source unique de vérité** : `docs/security/audit-noise-allowlist.md` (humain-friendly).
2. **Génération automatique** des fichiers techniques (`deny.toml`, `audit.toml`) à partir de cette source.
3. **Gate CI** : modification de `deny.toml` direct rejetée par CI ; toute exemption passe par la source Markdown.

---

## 3. Motivation

### 3.1 Le problème actuel

`deny.toml` accumule des exemptions au fil des releases :

- Pas de **justification** : pourquoi cette CVE est-elle ignorée ? Surface non exposée ? Patch indisponible ?
- Pas de **reviewer** : qui a décidé ? Discutable a posteriori.
- Pas de **date** : quand a-t-on ignoré ? Encore valide aujourd'hui ?
- Pas de **re-review** : aucune revue périodique des exemptions.

Conséquence : la liste des exemptions devient un cimetière, et un nouveau contributeur (ou opérateur lui-même 6 mois plus tard) ne peut pas raisonner sur leur validité.

### 3.2 Pourquoi appliquer côté Gradatum (et pas seulement skills agent)

`libskills:RFC-0008` a défini le pattern pour les **rapports d'audit `/cso`** (audit agent en cours de PR review). RFC-0008 applique le **même pattern aux scans CI automatisés** (`cargo audit`, `cargo deny`).

Cohérence essentielle : un opérateur qui maintient deux allowlist différentes (une pour `/cso`, une pour CI) finit par les laisser diverger. **Une source unique** simplifie.

### 3.3 Pourquoi génération automatique vers `deny.toml`

`cargo deny` ne lit pas le Markdown. Il faut bien générer le `deny.toml`. Option retenue : Source Markdown + script `scripts/generate-deny-config.sh`. Le `deny.toml` devient un **artefact généré**, **non éditable directement** (gate CI).

### 3.4 Pourquoi re-review trimestrielle imposée par CI

Sans rappel, les allowlist deviennent obsolètes. CI execute un check passif :

- Si une entrée a `re-review: 2026-04-30` et la date courante > 2026-04-30 + 30 jours de grâce → CI échoue avec message clair.
- Force l'opérateur à re-évaluer périodiquement, sans dépendre de sa volonté pure.

---

## 4. Scope

### 4.1 In scope

- Format normatif `docs/security/audit-noise-allowlist.md` strict (suit `libskills:RFC-0008` §4.5 + ajouts CI).
- Script `scripts/generate-deny-config.sh` qui produit `deny.toml` depuis le Markdown.
- Script `scripts/check-allowlist-staleness.sh` qui vérifie les re-review dates.
- Gate CI : refus si `deny.toml` hors sync / si entrée past-due > 30 jours.
- Migration des exemptions actuelles `deny.toml` vers le Markdown (one-time).
- Documentation `docs/security/CONTRIBUTING-allowlist.md`.

### 4.2 Out of scope

- **Allowlist côté tests fuzz** : hors scope CI standard.
- **Génération vers d'autres outils** (ex: `cargo geiger`) : reportée si besoin.
- **Auto-création d'entrée allowlist par PR** : exclu — l'ajout reste manuel et reviewé.

### 4.3 Non-objectifs

- L'allowlist n'est **pas** un mécanisme de bypass perpétuel. Toute exemption est temporaire.
- L'allowlist ne **garantit pas** l'absence de vulnérabilités — elle documente les choix conscients.

---

## 5. Design

### 5.1 Format `docs/security/audit-noise-allowlist.md` (texte normatif)

Structure obligatoire par entrée :

```markdown
### AL-<ID-stable> — <titre court>

- **Tool** : cargo-deny | cargo-audit | both | other:<name>
- **Section** : advisories | licenses | bans | sources
- **Pattern** : <identifiant exact, ex: RUSTSEC-2024-0010, GPL-3.0, etc.>
- **Justification** : <pourquoi cette exemption>
- **Reviewer** : <pseudonyme ou username>
- **Date d'ajout** : <YYYY-MM-DD>
- **Re-review prévue** : <YYYY-MM-DD>
- **Conditions de retrait** : <ce qui rendrait cette exemption invalide>
```

### 5.2 Script `scripts/generate-deny-config.sh` (texte normatif)

Comportement :

1. Lit `docs/security/audit-noise-allowlist.md`.
2. Parse les blocs `### AL-...` (regex sur `Tool`, `Section`, `Pattern`, `Re-review prévue`).
3. Vérifie validité de chaque entrée : champs obligatoires présents + pattern non-wildcard.
4. Vérifie staleness : Re-review + 30 jours de grâce ≥ aujourd'hui.
5. Génère `deny.toml` avec en-tête `# AUTO-GENERATED — DO NOT EDIT`.
6. Si erreur de validation : exit non-zero, message clair.

### 5.3 Script `scripts/check-allowlist-staleness.sh`

Comportement :

1. Parse `docs/security/audit-noise-allowlist.md` pour extraire `Re-review prévue`.
2. Si dépassement < 30 jours : warning (CI passe avec message).
3. Si dépassement ≥ 30 jours : erreur (CI fail). Exit code 1.

### 5.4 Gate CI (texte normatif)

```yaml
# .github/workflows/ci.yml — extrait

jobs:
  audit-allowlist-integrity:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Verify deny.toml is up-to-date with allowlist source
        run: |
          ./scripts/generate-deny-config.sh > deny.toml.expected
          diff -u deny.toml deny.toml.expected || {
            echo "::error::deny.toml is out of sync with docs/security/audit-noise-allowlist.md"
            exit 1
          }

      - name: Check allowlist staleness
        run: ./scripts/check-allowlist-staleness.sh

      - name: cargo deny check
        run: cargo deny check --all-features
```

**Gates concrets** :

- Une PR qui modifie `deny.toml` directement (sans modification correspondante du Markdown) **échoue**.
- Une PR qui n'a pas re-généré `deny.toml` après modification du Markdown **échoue**.
- Une PR qui n'agit pas sur une entrée past-due > 30 jours **échoue**.

### 5.5 Migration one-time des exemptions actuelles

1. Lecture du `deny.toml` actuel.
2. Pour chaque entry : création entrée Markdown avec justification "À compléter — exemption héritée pré-RFC-0008".
3. Reviewer = "opérateur (migration)". Date d'ajout = date commit (best-effort). Re-review = migration + 30 jours.
4. Création issue de tracking pour compléter les justifications dans les 30 jours.

---

## 6. Workflow d'application

### 6.1 Workflow PR ajout exemption

```text
[contributeur identifie une CVE bloquante en CI]
   ↓
[édite docs/security/audit-noise-allowlist.md : ajoute AL-<ID>]
   ↓
[lance scripts/generate-deny-config.sh > deny.toml]
   ↓
[lance scripts/check-allowlist-staleness.sh]
   ↓
[git add docs/security/audit-noise-allowlist.md deny.toml]
   ↓
[commit + push + PR]
   ↓
[CI vérifie : sync OK + staleness OK + cargo deny passe]
   ↓
[reviewer humain valide la justification dans le Markdown]
   ↓
[merge]
```

### 6.2 Workflow CI sur PR routine

```text
[CI démarre]
   ↓
[job audit-allowlist-integrity]
   ↓
[scripts/generate-deny-config.sh comparé à deny.toml courant]
   ├─ identique → OK
   └─ diff → FAIL
   ↓
[scripts/check-allowlist-staleness.sh]
   ├─ tout OK → succès
   ├─ warnings only → succès avec warning
   └─ fail past-due > 30j → CI échoue
   ↓
[cargo deny check]
```

---

## 7. Edge cases

| Cas | Comportement attendu |
|---|---|
| Entrée Markdown sans champ obligatoire | Script exit 1 avec message pointant ligne fautive. |
| Pattern wildcard (`RUSTSEC-*`, `*`, `.*`) | Refus à la génération. |
| Re-review = même jour qu'ajout | Avertissement. |
| Doublon ID stable | Refus avec message "AL-X défini 2 fois". |
| Markdown vide ou absent | Génère `deny.toml` minimal sans `ignore` custom. |
| Migration : entry "À compléter" past-due | Past-due détecté, force opérateur à compléter. |

---

## 8. Failure modes

| Mode | Symptôme | Mitigation |
|---|---|---|
| Script `generate-deny-config.sh` cassé | CI fail systématique | Tests dédiés du script. |
| Allowlist devient cimetière | Discipline contournée | `--strict` mode optionnel refusant re-review > 12 mois. |
| Pattern incorrect (typo CVE) | Exemption ne s'applique pas | `cargo deny` continue de remonter la CVE → CI fail → auto-correction. |
| Re-review date au format invalide | Script exit 1 | Format strict YYYY-MM-DD validé. |

---

## 9. Alternatives considérées

### 9.1 Édition directe `deny.toml` avec commentaires structurés

**Rejetée** : TOML difficile à lire/écrire pour l'humain, format moins riche, pas d'historique des entries retirées.

### 9.2 YAML au lieu de Markdown

**Rejetée** : YAML moins lisible humain, perte de la valeur "lecture continue".

### 9.3 Re-review trimestrielle obligatoire (90 jours hardcoded)

**Rejetée pour v1** : licenses stables sur 1+ an, forcer 90 jours = bruit. Re-review configurable par entrée, défaut suggéré 6 mois.

### 9.4 CI bot qui auto-update re-review

**Rejetée** : invalide la logique disciplinaire — l'opérateur DOIT re-évaluer activement.

---

## 10. Drawbacks et open questions

### 10.1 Drawbacks acceptés

- **Friction d'ajout** : un contributeur doit éditer Markdown, regen, commit deux fichiers. Acceptée — la friction est exactement la valeur.
- **Script à maintenir** : ~80 lignes bash. Acceptée — coût faible, ROI élevé.
- **Migration one-time exigeante** : exemptions historiques sans doc à compléter. Acceptée — dette explicite, traitée en 30 jours.

### 10.2 Open questions

- **Formatter Markdown automatique** : prettier/markdownlint pour le fichier ?
- **Notification re-review imminente** (J-30) : currently CI silencieux jusqu'à past-due. Pourrait warning à J-30. v2.
- **Cross-repo allowlist** : si l'opérateur a 5 projets Rust avec exemptions communes, faut-il un mécanisme partagé ?
- **Intégration `/cso` agent → CI** : si `/cso` propose ajout allowlist, l'opérateur valide et écrit dans le même fichier. Workflow cohérent grâce à `libskills:RFC-0008`.

---

## 11. Conformité constitutionnelle (libskills:RFC-0001)

RFC-0008 applique **directement** le pattern défini dans `libskills:RFC-0008` §4.5 au CI Gradatum. Conformité par construction.

---

## 12. Migration

### 12.1 Étapes de migration

**Phase 2.0** — Préparation :

1. Merger RFC.
2. Création `docs/security/audit-noise-allowlist.md` initial vide avec format.
3. Création `docs/security/CONTRIBUTING-allowlist.md`.
4. Création scripts `scripts/generate-deny-config.sh` et `scripts/check-allowlist-staleness.sh`.

**Phase 2.1** — Migration des exemptions actuelles :

5. Pour chaque exemption héritée dans `deny.toml` : création entrée Markdown.
6. Régénération `deny.toml` initial via le script.
7. Commit + PR.

**Phase 2.2** — Activation CI gates :

8. Ajout job `audit-allowlist-integrity` dans `.github/workflows/ci.yml`.

**Phase 2.3** — Complétion des justifications :

9. Sur 30 jours, compléter justifications réelles et ajuster re-review.

### 12.2 Rollback

```bash
git rm scripts/generate-deny-config.sh scripts/check-allowlist-staleness.sh
git rm docs/security/audit-noise-allowlist.md
git rm docs/security/CONTRIBUTING-allowlist.md
# Retrait du job CI 'audit-allowlist-integrity'
```

---

## 13. Acceptance criteria

| # | Criterion | Method | Expected |
|---|---|---|---|
| C1 | Script generate-deny-config.sh produit deny.toml valide | Test dry-run | conforme |
| C2 | Script check-allowlist-staleness.sh détecte past-due | Test scénario | exit 1 si >30j |
| C3 | CI fail si deny.toml hors-sync | Test PR avec edit direct | job FAIL |
| C4 | CI fail si entry past-due >30j | Test PR avec entry expirée | job FAIL |
| C5 | CI passe si tout conforme | Test PR routine | job PASS |
| C6 | Migration one-time des exemptions actuelles | Diff post-migration | identique |
| C7 | Format Markdown rejette wildcards | Test entry `pattern = "*"` | refus |
| C8 | cargo deny check passe sur deny.toml généré | CI run normal | PASS |

---

## 14. References

- **libskills:RFC-0008 §4.5** — Audit-noise allowlist (pattern source côté agent).
- **cargo-deny documentation** : https://embarkstudios.github.io/cargo-deny/

---

## Changelog

| Date | Author | Change |
|---|---|---|
| 2026-05-09 | opérateur | Création initiale, status: Draft, target Phase 2 alignement CI |
| 2026-05-10 | opérateur | Migration NAS → gradatum-skills public repo, renumérotation RFC-SKILL-GRADATUM-0011 → RFC-0008, refs mises à jour (`libskills:RFC-0008`, RFC-0007 intra-repo) |

---

## License

Cette RFC est publiée sous licence Apache-2.0, alignée sur le projet Gradatum. Elle s'inspire intellectuellement du projet gstack (garrytan/gstack, MIT) sans en reprendre le code source.

---

*End RFC-0008.*
