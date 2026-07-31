---
name: gradatum-memorize
description: >
  Décide si un événement mérite persistance durable dans le vault gradatum + oriente vers la section canonique, puis délègue l'écriture. Après décision actée, leçon, post-mortem, résultat d'expérience. SKIP si éphémère ou déjà dans code/git.
type: gradatum
compatibility: claude-code (>= 2.1.0)
---

# /gradatum-memorize

Déclencheur de mémorisation : décide si un événement mérite une note durable et oriente vers la
bonne section, puis délègue l'écriture. Pure logique — pas de script (comme /gradatum-skill-reminder).

## Positionnement dans la famille L1

Ce skill décide d'**ÉCRIRE** dans le vault. Symétrique mais distinct de /gradatum-skill-reminder qui
décide de **CHERCHER**.

| Situation | Skill |
|---|---|
| On vient de prendre une décision / tirer une leçon → la persister | `/gradatum-memorize` (écrire) |
| On s'apprête à agir et on veut vérifier si on a déjà traité ça | `/gradatum-skill-reminder` (chercher) |

Ne pas substituer l'un à l'autre. Les deux sont stateless et peuvent s'enchaîner.

## Test de mémorisation (binaire — DEUX conditions cumulatives)

Persister SI ET SEULEMENT SI **les deux** sont OUI :

1. « Une session future, sans le contexte d'aujourd'hui, bénéficierait-elle de ceci ? »
2. **Réutilisable** : ça concerne une **classe de situations**, pas un détail ponctuel non reproductible.

Un seul NON → SKIP.

### MÉMORISER — déléguer à l'écriture si :
- **Décision actée** (choix d'architecture, d'orientation, arbitrage tranché) → section `decisions`.
- **Leçon** : cause **reproductible** porteuse d'une RÈGLE (« avant X faire Y ») → section `lessons-learned`.
- **Bug spécifique + fix** : incident **isolé non récurrent** mais à **valeur de référence** (réutile en debug futur) → section `debug`.
  *(Frontière debug ↔ lessons-learned : récurrent/règle → lessons-learned ; ponctuel-mais-référençable → debug ; ni l'un ni l'autre → SKIP.)*
- **Analyse vérifiée** / pattern structurel → section `architecture`.
- **Post-mortem** de fin de phase / livraison → section `retrospectives`.
- **Hypothèse testée + résultat** (positif ou négatif) → section `experiments`.
- **Verdict de revue** multi-experts → section `council`.
- **Retour utilisateur ancré** (validation, correction) → section `feedback`.
- **Pointeur externe** (doc, ticket, dashboard) → section `reference`.
- **Plan / pattern de raisonnement réutilisable** → section `reasoning`.
- **Issue d'agent** (skill défaillant, comportement anormal, dérive) → section `agent-issues`.
- **Unité de travail à cycle de vie** — statut qui progresse jusqu'à `DONE`, destinée à une
  version → section `project-map`. C'est une **carte**, pas un événement. Deux différences qui
  changent tout : la section est **hint-only** (sans `section_hint` explicite la note part
  ailleurs *sans erreur*) et une carte y est **insupprimable**. Writer dédié : **`/gov-todo`**
  (verbes `project-map`, NOMENCLATURE §10e), **réservé au Général en Chef** — les sous-agents en
  sont interdits. Si l'agent courant n'est pas le Général → **escalader au Général**, ne jamais
  écrire directement dans `project-map`.

> La liste des sections dans `/gradatum-vault-write` est un **reflet opérationnel** de
> `Section::ALL` (le code serveur fait foi) ; le gel de gouvernance de la taxonomie vit dans
> NOMENCLATURE §10a.
> `identity` n'y est pas une cible : elle porte le runtime des âmes, pas des événements.

### SKIP — ne rien persister si :
- État de travail transitoire, contenu de session, TODO jetable.
- Détail de debug non récurrent et sans leçon.
- Échange trivial, reformulation, accord conversationnel.
- L'information vit déjà dans le code / l'historique git (ne pas dupliquer).

## Action si MÉMORISER

1. **Anti-doublon d'abord** : `/gradatum-vault-search "<sujet>"`.
2. **Si une note couvre déjà le sujet** → la METTRE À JOUR (pas de doublon) : `/gradatum-vault-read
   "<section>/<ulid>"` pour obtenir le `note_id` + `sha256`, puis `/gradatum-vault-write update
   --note-id <ulid> --sha <sha256> …`. **Sinon** → create.
3. **Choisir la section** via l'arbre ci-dessus (la section = dimension de routage des recherches futures).
4. **Écrire** : `/gradatum-vault-write create --section <section> --title "<titre>"` (corps sur stdin),
   OU `update` (étape 2). La chaîne complète d'une MAJ = search → read → write.

## Titre — règle

Format : `[CATÉGORIE][PROJET] Verbe au passé + objet concret + résultat/impact — date`. Spécifique,
jamais générique.
- ❌ « Note sur l'auth »
- ✅ « [DECISIONS][gradatum] Choisi JWT 24h + refresh-token httpOnly pour l'auth studio — 2026-06-14 »

## Anti-patterns

- Ne pas mémoriser sans avoir cherché d'abord (doublon).
- Ne pas deviner la section — un mauvais classement casse le recall futur.
- Ne pas persister de l'éphémère : le vault est durable, pas un brouillon.
- Ne pas reporter la mémorisation « plus tard » : capturer au moment de l'acte (le contexte se perd).
