---
rfc: RFC-0007
title: Curator confidence ladder — pending → confirmed → canonical
status: Draft
author: opérateur (Gradatum maintainer)
created: 2026-05-09
updated: 2026-05-10
version: 1
project: gradatum
phase_target: Phase 3 (post sqlite-vec, pré multi-tenant maturation)
depends_on:
  - gradatum:RFC-0001
  - libskills:RFC-0001
required_by: []
related_to:
  - gradatum:RFC-0002
  - gradatum:RFC-0003
crates_touched:
  - gradatum-core
  - gradatum-curator
  - gradatum-storage
  - gradatum-server
license: Apache-2.0
---

# RFC-0007 — Curator confidence ladder

> **TL;DR** — Transpose le pattern Quarantaine de `libskills:RFC-0001` §4.2 (utilisé par les skills agent) au curator de Gradatum. Étend le `status: pending_review` actuel en échelle à 3 niveaux : **pending → confirmed (N=3 réutilisations indépendantes) → canonical (N=10)**. Une note nouvelle entre en `pending`. Si elle est référencée 3 fois par des notes ou recherches indépendantes, elle promeut à `confirmed`. À 10, elle devient `canonical` et entre dans le corpus de référence du locus. Mécanisme **opt-in par locus**, désactivable.

---

## 1. Contexte Gradatum

Gradatum (alpha.5) est le memory backbone Rust open-source qui sert de support à vault-mem v2 (multi-tenant) et aux notes des agents. Le composant `gradatum-curator` (`gradatum:RFC-0001` existant) admet, classifie ou rejette les notes entrantes selon une politique versionnée.

État actuel du curator (référence : code crate `gradatum-curator/src/pipeline.rs`) :

```rust
pub enum NoteStatus {
    Admitted,
    Rejected,
    PendingReview,
}
```

Le statut `PendingReview` est un état "transit" temporaire : la note attend qu'un opérateur la classe à la main. Sans action humaine, elle reste indéfiniment `pending_review`.

Cette conception suffit pour un usage solo, mais ne capture pas la **valeur émergente** d'une note : une note est plus "vraie" si elle est **réutilisée** par d'autres notes ou requêtes que si elle est isolée. Le pattern Quarantaine (`libskills:RFC-0001` §4.2) — appliqué jusqu'ici aux skills agent uniquement — encode exactement ce critère.

---

## 2. Mission

RFC-0007 transpose le pattern Quarantaine au curator. Sa fonction unique : **faire évoluer le statut d'une note dans le temps en fonction de son usage réel, sans intervention humaine, tout en conservant un contrôle explicite par locus**.

Trois principes :

1. **Échelle à 3 niveaux** : `pending` → `confirmed` (N=3) → `canonical` (N=10).
2. **Promotion automatique** : déclenchée par la mécanique d'usage, pas par humain.
3. **Démotion possible** : une note `confirmed` qui devient obsolète ou rejetée par usage redescend.

> **Inspiration directe** : `libskills:RFC-0001` §4.2 (Quarantaine appliquée aux skills agent) + observation que vault-mem v2 et les patterns d'usage Gradatum ont la même structure logique.

---

## 3. Motivation

### 3.1 Pourquoi sur Gradatum et pas seulement les skills agent

Le pattern Quarantaine côté agent traite **les artefacts auto-générés** (skills proposés, patterns détectés). La transposition côté Gradatum traite **les notes humaines + agent**, qui sont l'output canonique du système.

Les deux problèmes ont la même structure :

| Aspect | Quarantaine agent | Curator confidence ladder |
|---|---|---|
| Entité | skill ou pattern auto-suggéré | note insérée dans un locus |
| État initial | `pending` | `pending` |
| Critère promotion | réutilisation indépendante | référencement par d'autres notes / requêtes |
| État stable | `canonical` | `canonical` |
| Effet stable | skill versé en `<agent-config>/skills/` | note inscrite au corpus de référence du locus |

Réutiliser le même mental model facilite l'adoption.

### 3.2 Le problème côté Gradatum

Sans confidence ladder, les notes Gradatum sont `Admitted` ou `Rejected` au moment de l'admission, basé uniquement sur les heuristiques curator (modèle classification, règles métier, score). Cela crée trois problèmes :

1. **Faux positifs persistants** : une note admise mais erronée pollue indéfiniment le corpus.
2. **Faux négatifs non-détectés** : une note rejetée à tort ne reviendra pas, même si elle aurait été utile.
3. **Dette de classification** : `pending_review` croît sans mécanisme automatique de résolution.

Le confidence ladder résout par évolution naturelle : si la note est utile, elle est référencée → elle promeut. Si elle est inutile, elle reste `pending` puis peut être archivée par une politique de purge.

### 3.3 Pourquoi N=3 puis N=10

Mêmes raisons que `libskills:RFC-0001` §9.2 :

- N=3 : seuil empirique en-dessous duquel le pattern n'est pas suffisamment validé (1-2 réutilisations peuvent être hasard).
- N=10 : seuil au-delà duquel la note est manifestement intégrée à l'usage du système.

Les seuils sont **par locus** dans RFC-0007 (configurables) — un locus de notes critiques peut exiger N=20, un locus exploratoire peut accepter N=2.

### 3.4 Pourquoi `confirmed` distinct de `canonical`

Trois niveaux au lieu de deux permettent de distinguer :

- `pending` (probation) : pas filtrée par défaut dans les recherches "canonical only".
- `confirmed` (validée par usage) : disponible aux requêtes de recherche standard.
- `canonical` (référence pérenne) : participe au corpus de référence pour le ranking, immutable sauf intervention manuelle.

Sur un locus avec `tier_filter = "canonical"`, seules les notes `canonical` sont retournées. Sur un locus standard, `confirmed` + `canonical` sont retournés. Sur un locus exploratoire, les trois.

### 3.5 Pourquoi opt-in par locus

Tous les locus ne bénéficient pas de la confidence ladder. Exemples :

- **Locus mémoire courte** (session-scoped, TTL 24h) : pas besoin, les notes sont éphémères.
- **Locus journal opérateur** (toutes admises par construction) : pas besoin, l'humain valide chaque note.
- **Locus knowledge base** (corpus partagé multi-tenants) : très utile, ladder activée.

L'opt-in se fait via configuration locus :

```toml
[locus.knowledge-base]
confidence_ladder.enabled = true
confidence_ladder.thresholds = { confirmed = 3, canonical = 10 }
```

---

## 4. Scope

### 4.1 In scope

- Extension du `enum NoteStatus` de gradatum-core avec ladder à 3 niveaux + counter `reuse_count`.
- Migration SQL `0002_add_confidence_ladder.sql` (gradatum-storage SQLite + sqlite-vec).
- Mécanisme de comptage des réutilisations indépendantes (pas le même utilisateur compte 2x sur même note).
- Algorithme de promotion automatique pending → confirmed → canonical.
- Algorithme de démotion (rare mais nécessaire) : si signal négatif, redescente.
- Configuration locus opt-in.
- Filtrage des recherches par tier de confiance (`?tier=canonical`, `?tier=confirmed-or-canonical`, default = tous).
- Endpoint HTTP exposant le tier + reuse_count.
- Migration des données existantes : toutes les notes `Admitted` actuelles passent en `confirmed` d'office (rétro-validation conservative).

### 4.2 Out of scope

- **Politique de purge des `pending` stales** : sera traitée dans RFC ultérieure (auto-archivage `pending` >90j sans réutilisation).
- **Historique des transitions** (audit log) : utile mais pas critique pour v1, candidat plus tard.
- **Mécanisme de challenge / vote inter-utilisateurs** : multi-tenant collaboratif, hors scope.
- **Decay temporel** (note canonical perd du score si non réutilisée pendant N mois) : reportée.
- **Synchronisation cross-locus** : si la même note est dupliquée dans 2 locus, comptage indépendant. Pas de fusion auto.

### 4.3 Non-objectifs

- Le ladder n'est **pas** un mécanisme de qualité absolue — il mesure l'usage réel, pas la véracité.
- Le ladder ne remplace **pas** le curator d'admission — il s'applique **après** l'admission.
- Le ladder n'est **pas** opt-out (si activé sur un locus, toutes les notes du locus suivent — pas de bypass note-par-note).

---

## 5. Design

### 5.1 Modification gradatum-core (`enum NoteStatus`)

```rust
// gradatum-core/src/note.rs
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NoteStatus {
    /// Note rejetée par le curator d'admission (pas dans le ladder).
    Rejected,

    /// Note en probation. Counter `reuse_count` < `confirmed_threshold`.
    Pending,

    /// Note référencée >= `confirmed_threshold` fois indépendamment.
    Confirmed,

    /// Note référencée >= `canonical_threshold` fois. Inscrite au corpus.
    Canonical,
}
```

`Admitted` (legacy) est **supprimé** — remplacé par `Pending` (nouveau défaut) ou `Confirmed` (migration des données existantes — cf. §5.10).

### 5.2 Compteur de réutilisations indépendantes

`reuse_count: u8` ajouté à la structure note (max 255, suffit pour les seuils par défaut 3 et 10). Le compteur s'incrémente sur **réutilisation indépendante**, c'est-à-dire :

| Événement | Incrémente reuse_count ? |
|---|---|
| Note référencée par wikilink dans une autre note **du même auteur** | Oui (mais une seule fois par note source) |
| Note référencée par wikilink dans une note **d'un autre auteur** (multi-tenant) | Oui (mais une seule fois par auteur source) |
| Note retournée dans une recherche FTS et **cliquée/sélectionnée** par l'utilisateur | Oui (mais une seule fois par session utilisateur dans une fenêtre 24h) |
| Note retournée dans une recherche sémantique et utilisée comme contexte pour LLM | Oui (mais une seule fois par session) |
| Note auto-référencée par son propre auteur dans la même session | **Non** (pas indépendant) |
| Note bulk-import re-trigger une révision | **Non** |

L'unicité est garantie par une table `reuse_log(note_id, source_signature, ts)` où `source_signature` capture l'origine de la réutilisation (note_id source, user_id, session_id, ou hash de la requête). UNIQUE sur `(note_id, source_signature)`.

### 5.3 Migration SQL `0002_add_confidence_ladder.sql`

```sql
-- gradatum-storage/migrations/0002_add_confidence_ladder.sql

-- 1. Enum status élargi (sqlite-friendly TEXT check constraint)
ALTER TABLE notes
    ADD COLUMN status_v2 TEXT
    CHECK (status_v2 IN ('rejected', 'pending', 'confirmed', 'canonical'))
    NOT NULL DEFAULT 'pending';

-- 2. Compteur de réutilisations
ALTER TABLE notes
    ADD COLUMN reuse_count INTEGER NOT NULL DEFAULT 0;

-- 3. Timestamp du dernier changement de tier
ALTER TABLE notes
    ADD COLUMN tier_changed_at TIMESTAMP;

-- 4. Migration data existante : Admitted → Confirmed (rétro-validation conservative)
UPDATE notes SET status_v2 = 'confirmed', tier_changed_at = CURRENT_TIMESTAMP
    WHERE status = 'admitted';
UPDATE notes SET status_v2 = 'rejected'
    WHERE status = 'rejected';
UPDATE notes SET status_v2 = 'pending'
    WHERE status = 'pending_review';

-- 5. Drop l'ancienne colonne après validation
-- (geste séparé en 0003_drop_legacy_status.sql après période de coexistence)

-- 6. Table de log des réutilisations indépendantes
CREATE TABLE IF NOT EXISTS reuse_log (
    note_id BLOB NOT NULL,
    source_signature TEXT NOT NULL,
    locus_id TEXT NOT NULL,
    ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (note_id, source_signature)
);

CREATE INDEX idx_reuse_log_note ON reuse_log(note_id);
CREATE INDEX idx_reuse_log_locus_ts ON reuse_log(locus_id, ts);

-- 7. Configuration ladder par locus
CREATE TABLE IF NOT EXISTS locus_config (
    locus_id TEXT PRIMARY KEY,
    confidence_ladder_enabled INTEGER NOT NULL DEFAULT 0,
    confirmed_threshold INTEGER NOT NULL DEFAULT 3,
    canonical_threshold INTEGER NOT NULL DEFAULT 10,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

Migration rollback fournie en `0002_add_confidence_ladder_DOWN.sql`.

### 5.4 Algorithme de promotion (texte normatif)

```rust
// gradatum-curator/src/ladder.rs (nouveau module)

pub fn record_reuse(
    storage: &dyn StorageBackend,
    note_id: NoteId,
    locus_id: &LocusId,
    source: ReuseSource,
) -> Result<Option<TierTransition>, LadderError> {
    let config = storage.get_locus_config(locus_id)?;
    if !config.confidence_ladder_enabled {
        return Ok(None);
    }

    let signature = source.signature();

    // Insert reuse log entry; UNIQUE constraint dedup automatiquement
    let inserted = storage.insert_reuse_log(note_id, &signature, locus_id)?;
    if !inserted {
        // Doublon, pas de comptage
        return Ok(None);
    }

    // Incrémenter reuse_count
    let new_count = storage.increment_reuse_count(note_id)?;

    // Vérifier promotion
    let current_status = storage.get_note_status(note_id)?;
    let new_status = match (current_status, new_count) {
        (NoteStatus::Pending, n) if n >= config.confirmed_threshold => {
            NoteStatus::Confirmed
        }
        (NoteStatus::Confirmed, n) if n >= config.canonical_threshold => {
            NoteStatus::Canonical
        }
        (status, _) => status, // pas de transition
    };

    if new_status != current_status {
        storage.update_note_status(note_id, new_status)?;
        Ok(Some(TierTransition {
            note_id,
            from: current_status,
            to: new_status,
            at: Utc::now(),
        }))
    } else {
        Ok(None)
    }
}
```

**Règles dérivées** :

- Promotion `Pending` → `Canonical` directe **interdite** (doit passer par `Confirmed`).
- `reuse_count` ne peut décroître **sauf via signal négatif explicite** (cf. §5.5).
- `Rejected` est terminal — pas de promotion possible (note doit être ré-admise via curator).

### 5.5 Algorithme de démotion (rare mais prévu)

Une note `Confirmed` ou `Canonical` peut redescendre si signal négatif fort :

| Signal | Effet |
|---|---|
| Note explicitement supprimée par auteur | Status → Rejected (terminal) |
| Note retournée dans recherche puis **flagged** par utilisateur ("not useful", "outdated") ≥ 3 fois | Démotion d'un cran (Canonical → Confirmed, ou Confirmed → Pending) |
| Note avec contenu hash modifié ≥ 80% (édition majeure) | Démotion à Pending + reuse_count reset (option configurable, default OFF) |
| Audit manuel admin | Status forcé à n'importe quelle valeur |

### 5.6 Configuration locus

```toml
[locus.knowledge-base]
confidence_ladder.enabled = true
confidence_ladder.thresholds.confirmed = 3
confidence_ladder.thresholds.canonical = 10
confidence_ladder.demotion.enabled = true
confidence_ladder.demotion.threshold = 3

[locus.session-scratch]
confidence_ladder.enabled = false  # locus éphémère, pas de ladder

[locus.curated-references]
confidence_ladder.enabled = true
confidence_ladder.thresholds.confirmed = 5    # seuils plus stricts
confidence_ladder.thresholds.canonical = 20
```

API HTTP :

```
GET  /v1/loci/{locus_id}/config
PUT  /v1/loci/{locus_id}/config
```

### 5.7 Endpoint de recherche enrichi

```http
GET /v1/loci/{locus_id}/search?q=...&tier=canonical
GET /v1/loci/{locus_id}/search?q=...&tier=confirmed-or-canonical
GET /v1/loci/{locus_id}/search?q=...                     # tous tiers (default)
```

### 5.8 Effet sur le ranking

Pour les requêtes sans filtre `tier=`, le score de pertinence est **boosté** par tier :

```
final_score = base_score * tier_boost(status)

tier_boost(Canonical)  = 1.20
tier_boost(Confirmed)  = 1.05
tier_boost(Pending)    = 0.85
```

Coefficients **configurables par locus**.

### 5.9 Migration des données existantes

Toutes les notes actuellement `Admitted` passent à `Confirmed` (pas `Canonical`) — rétro-validation conservative. Compteur initial `reuse_count = 0` pour les notes admitted héritées.

---

## 6. Edge cases

| Cas | Comportement attendu |
|---|---|
| Locus sans ladder activée | reuse_count incrémenté quand même (gratuit), mais aucune promotion. |
| Note insérée puis immédiatement effacée | Pas de reuse_log entries, suppression cascade. |
| Compteur reuse_count atteint 255 (overflow u8) | Saturation à 255 (clamp). |
| Multi-locus, même note clonée | Comptage indépendant par locus. Pas de fusion. |
| Spam d'auto-références | Source signature inclut user_id et session_id ; auto-références déduplicquées. |
| Recherche FTS qui retourne note mais user ne clique pas | Pas de comptage. |
| Locus avec confirmed_threshold > canonical_threshold (config invalide) | Refus à l'écriture config + erreur explicite. |

---

## 7. Failure modes

| Mode | Symptôme | Mitigation |
|---|---|---|
| Promotion en avalanche après import bulk | 1000 notes promues simultanément, pollution corpus canonical | Bulk import marqué via flag `bypass_ladder = true`. |
| Démotion abusive par flagging coordonné | Trois utilisateurs malveillants flag → démotion | Multi-tenant : exiger flags de **tenants distincts**. |
| Ladder OFF sur locus critique par erreur | Notes restent toutes `Pending` | Endpoint admin + métrique d'alerte. |
| Régression du ranking suite à boost tier | Notes anciennes canonical éclipsent les nouvelles confirmed pertinentes | Coefficients tier_boost configurables par locus. |

---

## 8. Alternatives considérées

### 8.1 Échelle continue (score 0.0-1.0) au lieu de 3 tiers

**Rejetée** : complexifie la logique, peu lisible côté UI, choix arbitraire des conversions float → tier. 3 tiers discrets cohérent avec `libskills:RFC-0001`.

### 8.2 Promotion humaine uniquement

**Rejetée** : multiplie la dette manuelle. La motivation principale (§3.2) est précisément d'éviter la classification manuelle.

### 8.3 Seuils globaux (pas par locus)

**Rejetée** : différents locus ont différents besoins. Configurabilité est essentielle.

### 8.4 Migration "tout en Canonical"

**Rejetée** : pollue le corpus de référence avec des notes non-validées par usage. Conservatisme préféré.

---

## 9. Drawbacks et open questions

### 9.1 Drawbacks acceptés

- **Coût stockage** : reuse_log peut grossir. Compaction post-6 mois prévue v2.
- **Complexité accrue du curator** : passe d'un statut binaire à 3 tiers + comptage. Acceptée.
- **Asymétrie promotion/démotion** : promotion auto, démotion mixte. Acceptée.

### 9.2 Open questions

- **Decay temporel** : note canonical sans réutilisation pendant 12 mois → démotion auto ? À étudier post-Phase 3.
- **Score ranking optimal** : tier_boost = 1.20 pour Canonical est un choix initial, à ajuster par observation.
- **Visualisation du ladder côté UI** : badge `Pending`, `Confirmed`, `Canonical` à côté des notes ?

---

## 10. Conformité constitutionnelle (libskills:RFC-0001)

RFC-0007 **transpose** le pattern Quarantaine. Conformité par construction :

- **Iron Law** : le ladder **prévient** Iron Law indirectement — moins de notes erronées polluent les recherches.
- **Quarantaine** : les notes circulant dans Gradatum **vivent dans un système quarantine** par construction (le ladder lui-même).

---

## 11. Migration

### 11.1 Étapes de migration (ordonnées)

**Phase 3.0** — Préparation :

1. RFC mergée et taggée `accepted` après revue.
2. Test de migration `0002_add_confidence_ladder.sql` sur dump production de référence.

**Phase 3.1** — Implémentation core :

3. PR `gradatum-core` : extension `enum NoteStatus`.
4. PR `gradatum-storage` : migration SQL + fonctions reuse_log.
5. PR `gradatum-curator` : module `ladder.rs`.

**Phase 3.2** — Intégration server :

6. PR `gradatum-server` : endpoint search avec `?tier=`, endpoint config locus, métriques Prometheus.

**Phase 3.3** — Validation :

7. Tests intégration end-to-end.
8. Tests perf : ajout reuse_log ne dégrade pas latence search > 5%.

### 11.2 Rollback

```sql
DROP TABLE IF EXISTS reuse_log;
DROP TABLE IF EXISTS locus_config;
ALTER TABLE notes DROP COLUMN status_v2;
ALTER TABLE notes DROP COLUMN reuse_count;
ALTER TABLE notes DROP COLUMN tier_changed_at;
```

---

## 12. Acceptance criteria

| # | Criterion | Method | Expected |
|---|---|---|---|
| C1 | enum NoteStatus extendu sans breaking API | Tests existants | passing |
| C2 | Migration 0002 applicable et reversible | Test up/down | OK |
| C3 | Promotion Pending → Confirmed à reuse_count = 3 | Test integration | tier change |
| C4 | Promotion Confirmed → Canonical à reuse_count = 10 | Test integration | tier change |
| C5 | Démotion sur 3 flags outdated | Test integration | tier change |
| C6 | Filtrage `?tier=canonical` retourne uniquement Canonical | Test endpoint | conforme |
| C7 | Locus sans ladder n'a pas de promotions | Test config | aucune transition |
| C8 | reuse_log déduplique sur (note_id, source_signature) | Test concurrence | UNIQUE respecté |
| C9 | Boost tier appliqué dans ranking par défaut | Test perf | scores ordonnés |
| C10 | Métriques Prometheus exposées | Test endpoint /metrics | présentes |

---

## 13. References

- **libskills:RFC-0001 §4.2** — Quarantaine (pattern source).
- **gradatum:RFC-0001** — Versioning Gradatum.
- **gradatum:RFC-0002** — Cross-platform (compatibilité ALTER TABLE SQLite).
- **gradatum:RFC-0003** — HTTP API (extension endpoints search).
- **vault-mem v2** : tier hot/warm/cold (mécanisme similaire mais sur dimension temporelle).

---

## Changelog

| Date | Author | Change |
|---|---|---|
| 2026-05-09 | opérateur | Création initiale, status: Draft, version 1, target Phase 3 |
| 2026-05-10 | opérateur | Migration NAS → gradatum-skills public repo, renumérotation RFC-SKILL-GRADATUM-0010 → RFC-0007, refs mises à jour (`libskills:RFC-0001`, `gradatum:RFC-0001/0002/0003`) |

---

## License

Cette RFC est publiée sous licence Apache-2.0, alignée sur le projet Gradatum. Elle s'inspire intellectuellement du projet gstack (garrytan/gstack, MIT) sans en reprendre le code source.

---

*End RFC-0007.*
