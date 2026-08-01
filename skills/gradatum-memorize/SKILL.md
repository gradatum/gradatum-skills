---
name: gradatum-memorize
description: >
  Décide si un événement mérite persistance durable dans le vault gradatum, oriente vers la section
  canonique, et porte les deux temps de la mémorisation : CAPTURE (une ligne par événement dans un
  checkpoint de session, coût minimal, aucune écriture vault) puis SYNTHÈSE (checkpoint → notes
  vault, avec anti-doublon). Après décision actée, leçon, post-mortem, résultat d'expérience.
  Porte un événement à la fois : ne couvre ni le dépôt (commit, push, tag), ni les documents
  locaux, ni aucune synchronisation d'ensemble — pour cela, l'installation a ses propres skills.
  SKIP si éphémère ou déjà dans code/git.
type: gradatum
compatibility: claude-code (>= 2.1.0)
allowed-tools: mcp__gradatum__vault_search mcp__gradatum__vault_read mcp__gradatum__vault_write mcp__gradatum__job_status
---

# /gradatum-memorize

> **ROUTEUR — lire ceci d'abord, aller directement au temps désigné.**
> **Un événement vient d'être acté, session en cours** → **CAPTURE** (§Temps 1) : *une ligne* dans
> le checkpoint, **et s'arrêter là** — aucune écriture vault.
> **Fin de session, un checkpoint du jour existe** → **SYNTHÈSE** (§Temps 2).
> **Événement isolé, hors session longue** → **Voie directe** (§Voie directe) : une note, tout de suite.
> **Rien d'acté, ou l'information vit déjà dans le code / l'historique git** → **SKIP**, ne rien lire de plus.

Déclencheur de mémorisation : décide si un événement mérite une note durable, oriente vers la
bonne section, puis persiste. Pure logique + outils MCP — pas de script, pas d'appel HTTP à la main.

**Ne couvre pas** : un événement à la fois. Ni le dépôt (commit, push, tag), ni les documents
locaux, ni aucune synchronisation d'ensemble — ce sont d'autres skills, propres à l'installation.

## Positionnement dans la famille L1

Ce skill décide d'**ÉCRIRE** dans le vault. Symétrique mais distinct de /gradatum-skill-reminder qui
décide de **CHERCHER**.

| Situation | Skill |
|---|---|
| On vient de prendre une décision / tirer une leçon → la persister | `/gradatum-memorize` (écrire) |
| On s'apprête à agir et on veut vérifier si on a déjà traité ça | `/gradatum-skill-reminder` (chercher) |

Ne pas substituer l'un à l'autre. Les deux sont stateless et peuvent s'enchaîner.

## Les deux temps de la mémorisation

Écrire une note coûte : recherche anti-doublon, composition du corps, écriture, confirmation du job.
Le faire au milieu d'une session, à chaud, pour chaque événement, est hors de prix. D'où deux temps
séparés — et une voie directe pour l'événement isolé.

| Temps | Quand | Ce qu'il produit | Coût |
|---|---|---|---|
| **CAPTURE** | immédiatement après l'événement | **1 ligne** dans le checkpoint de session | minimal — **aucune écriture vault** |
| **SYNTHÈSE** | fin de session (ou sur demande) | N notes vault depuis les lignes capturées | 1 cycle d'écriture par ligne retenue |
| **Voie directe** | événement isolé, hors session longue | 1 note vault immédiate | 1 cycle d'écriture |

Le **test de mémorisation** ci-dessous s'applique aux trois : il décide *si* l'on garde trace, avant
même de choisir le temps.

## Test de mémorisation (binaire — DEUX conditions cumulatives)

Persister SI ET SEULEMENT SI **les deux** sont OUI :

1. « Une session future, sans le contexte d'aujourd'hui, bénéficierait-elle de ceci ? »
2. **Réutilisable** : ça concerne une **classe de situations**, pas un détail ponctuel non reproductible.

Un seul NON → SKIP.

### MÉMORISER — router vers la section :
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
  changent tout : la section est **hint-only** (sans section suggérée explicite la note part
  ailleurs *sans erreur*) et une carte y est **insupprimable**. Elle a un **writer dédié** côté
  installation, réservé à l'agent orchestrateur — si l'agent courant n'est pas celui-là →
  **escalader**, ne jamais écrire directement dans `project-map` depuis ce skill.

> La liste des sections dans `/gradatum-vault-write` est un **reflet opérationnel** de
> `Section::ALL` (le code serveur fait foi).
> `identity` n'y est pas une cible : elle porte le runtime des âmes, pas des événements.

### SKIP — ne rien persister si :
- État de travail transitoire, contenu de session, TODO jetable.
- Détail de debug non récurrent et sans leçon.
- Échange trivial, reformulation, accord conversationnel.
- L'information vit déjà dans le code / l'historique git (ne pas dupliquer).

---

## Temps 1 — CAPTURE : une ligne dans le checkpoint de session

**But** : figer la trace minimale d'un événement structurel **au moment où il est acté**, sans payer
la machinerie d'écriture. Le contexte se perd vite ; la ligne le retient jusqu'à la synthèse.

### Capturer sur

- livraison poussée (commit + push abouti) ;
- validation explicite de l'opérateur sur un choix structurel ;
- verdict d'une revue multi-experts ;
- tag / release ;
- anomalie constatée sur un composant en production ;
- amorçage d'un nouveau projet ;
- demande explicite de trace.

### NE PAS capturer

- événement encore en discussion, non validé — la capture suit l'acte, pas l'intention ;
- correction triviale (typo, doc sans impact) ;
- échantillonnage temporel (« toutes les N minutes ») ;
- déclenchement sur chaque message, sur chaque lecture de fichier, ou sur une erreur de commande
  transitoire.

### Où : le chemin se DÉRIVE, il ne s'écrit jamais en dur

Le checkpoint vit dans le **répertoire de session** que le harnais alloue à la session courante —
pour Claude Code, le répertoire qui porte le transcript de la session :

```
<répertoire de session>/checkpoints/<YYYY-MM-DD>.md
```

- `<YYYY-MM-DD>` = date locale du jour → **un fichier par jour et par session-projet**.
- **INTERDIT** : coder un chemin absolu d'installation dans un raisonnement, un exemple ou une
  commande. Un chemin en dur transforme une valeur d'installation en règle produit et casse toute
  autre installation.
- Si le répertoire de session n'est pas résoluble → **le dire et s'arrêter**. Ne jamais inventer un
  emplacement de repli : une ligne écrite au mauvais endroit est une ligne perdue silencieusement.
- Une installation qui souhaite figer cet emplacement le consigne dans une note vault
  `section=architecture` qui lui est propre — pas ici.

Créer le fichier s'il n'existe pas, avec cet en-tête :

```markdown
# Checkpoint de session — <YYYY-MM-DD>

> Écrit par /gradatum-memorize (temps CAPTURE), consommé par le temps SYNTHÈSE.
> 1 ligne par événement structurel. Pas de blob, pas de recopie d'un autre document.
```

### Format de ligne (strict)

```
HH:MM | section=<section> | title="<titre ≤ 120 car.>" | refs=<commits|fichiers|notes> | tags=[<t1>,<t2>,<t3>] | trigger=<id> | mode=<auto|manual>
```

| Champ | Règle |
|---|---|
| `HH:MM` | heure locale |
| `section` | une des sections de l'arbre ci-dessus, en minuscules |
| `title` | ≤ 120 caractères, factuel, spécifique (règle §Titre) |
| `refs` | `<repo>:<sha12>`, chemins de fichiers clés, ou chemins de notes vault existantes |
| `tags` | 3 à 5 tags `[minuscules-avec-tirets]` |
| `trigger` | identifiant court de la cause (`commit-push`, `validation-operateur`, `revue`, `anomalie`, `manuel`…) |
| `mode` | `auto` (déclenché par un événement outillé) ou `manual` (demandé) |

Exemple :

```
17:42 | section=decisions | title="bascule du cache de recherche sur clé composite actée" | refs=vault-core:a9cb827 | tags=[search,cache,perf] | trigger=validation-operateur | mode=manual
```

### Anti-doublon de capture

Avant d'ajouter, vérifier qu'aucune ligne du checkpoint du jour ne porte **le même `title` et les
mêmes `refs`**. Si trouvée → **skip silencieux** (journaliser « ligne déjà présente »).

### Garde-fous du temps CAPTURE

- **Aucune écriture vault** ici — elle est différée à la synthèse. Une capture qui écrit dans le
  vault a manqué son but (le coût).
- Aucune modification d'un autre document.
- Checkpoint illisible ou corrompu → le recréer avec l'en-tête puis ajouter la ligne. Ne jamais
  perdre la ligne courante pour cause de fichier abîmé.

---

## Temps 2 — SYNTHÈSE : checkpoint → notes vault

### Pré-requis — état du checkpoint du jour

| État observé | Action |
|---|---|
| présent, ≥ 1 ligne valide (hors en-tête) | continuer |
| **absent** | STOP — rien à synthétiser. Ne PAS reconstituer les événements depuis le transcript. |
| présent, en-tête seul | STOP — session sans événement structurel. |
| illisible / parse en échec sur > 50 % des lignes | STOP + signaler. Pas de reconstitution. |

Reconstituer depuis le transcript reviendrait à refaire le travail de classification sans l'ancrage
du moment — avec un risque d'erreur supérieur à la perte assumée.

### 1. Parser

Ignorer l'en-tête (lignes `#` et `>`). Pour chaque ligne valide, extraire :

| Champ | Devient |
|---|---|
| `section` | section suggérée de la note |
| `title` | titre de la note |
| `refs` | wikilinks + champ `Refs` du corps |
| `tags` | tags de la note |
| `HH:MM` | horodatage dans le corps |
| `trigger` + `mode` | une ligne de contexte dans le corps |

Ligne malformée → **skip**, et la citer telle quelle dans le journal final. Ne pas tenter de la
reconstituer.

Traiter les événements dans l'ordre chronologique.

### 2. Anti-doublon par titre (avant chaque écriture)

`mcp__gradatum__vault_search` sur le titre extrait (limite 3). Puis, **indépendamment du score de
pertinence** :

0. Titre vide après trim → continuer l'écriture (prudence : pas de skip).
1. Normaliser les deux titres : minuscules, espaces multiples réduits à un seul.
2. Sur le **premier résultat** :
   - **match exact normalisé** → **skip** (la note existe déjà) ;
   - **OU** les **trois** conditions cumulatives suivantes toutes vraies → **skip** :
     (a) titre **complet** identique normalisé — **pas** un préfixe commun ;
     (b) **ET** même section ;
     (c) **ET** date ISO `YYYY-MM-DD` explicitement présente **et identique** dans les deux titres.
     Si l'une des deux extractions de date rend « absente » → (c) est **FAUSSE** → **pas de skip**.
3. Sinon → écrire.

Deux pièges que ces règles ferment :

- *Préfixe commun* — `"lot B complet — 0 hit sur le motif"` vs `"lot B COMPLET — tous les gates
  passent"` : (a) fausse → écriture autorisée. Un skip sur préfixe perd une note distincte.
- *Date absente des deux côtés* — comparer « absent » à « absent » ne prouve rien. (c) est fausse,
  pas vraie.

**Règle de doute** : en cas d'incertitude, **écrire**. Deux notes quasi-identiques valent mieux que
zéro note. Le curateur peut par ailleurs avoir reformulé un titre à l'écriture — le match exact
échouera alors, et c'est sans gravité.

Journaliser chaque skip avec sa raison : `skip doublon (titre exact | titre+section+date) : <titre>`.

### 3. Composer le corps

Gabarit par défaut (événement issu d'une ligne de checkpoint), **cap 300 mots** :

```markdown
## Événement
[Verbe + objet concret — 1-2 lignes factuelles tirées du titre et des refs]

## Contexte
[Ce qui a motivé l'action ou la décision — 2-3 lignes]

## Résultat
[État final, métriques clés, tag si applicable — 2-4 lignes]

## Refs
[Wikilinks [[titre-note]] vers les notes liées]
[Commits : `<repo>:<sha12>`]

## Horodatage
[YYYY-MM-DD HH:MM — trigger: <id> mode: <auto|manual>]
```

Les sections ci-dessous ont un gabarit propre, plus riche que l'événement générique :

<details><summary><code>reasoning</code> — plan réutilisable ayant réussi</summary>

```markdown
## Contexte
[Problème, contrainte, objectif — 2-3 lignes]

## Plan utilisé
[Étapes numérotées telles qu'exécutées — pas le plan initial s'il a changé en route]

## Résultat
[SUCCESS/PARTIAL — durée, défauts constatés après coup, métriques]

## Leçons
[Ce qui a marché / ce qu'il faudrait faire autrement — 2-4 puces]

## Réutilisation
[Dans quelles situations ce pattern s'applique — 1-2 lignes]
```
</details>

<details><summary><code>retrospectives</code> — fin de phase / livraison</summary>

```markdown
## Phase
[Nom de la phase ou du milestone]

## Livrables
[Ce qui a été produit — version, tag, fonctionnalités, métriques]

## Ce qui a tenu
[2-4 puces — décisions, patterns, choix validés par les faits]

## Ce qui n'a pas tenu
[2-4 puces — dettes, retards, défauts, dérapages]

## Phase suivante
[Attendus, dette à solder, priorités]
```
</details>

<details><summary><code>experiments</code> — hypothèse testée</summary>

```markdown
## Hypothèse
[Ce qu'on supposait — 1-2 lignes]

## Protocole
[Comment testé — outil, durée, métrique]

## Résultat
[Données observées — chiffres concrets]

## Conclusion
[Confirmée / réfutée / partielle + implications]

## Suite
[Adopter, abandonner, investiguer plus]
```
</details>

### 4. Écrire — une note par appel, confirmée par son job

Déléguer à **`/gradatum-vault-write`** (mode create, ou update si l'anti-doublon a trouvé une note à
enrichir : search → read → write, avec le hash lu).

- **UNE note par appel.** Ne jamais passer un tableau de notes : le paramètre n'est pas un lot, et
  une tentative groupée échoue en silence — la file n'accuse rien, et N notes disparaissent sans
  message d'erreur. N événements ⇒ N appels successifs.
- **Aucun appel HTTP à la main.** Les écritures passent exclusivement par les outils MCP : une
  requête montée à la main masque les erreurs que l'outil, lui, remonte.
- La section suggérée est **explicite** — la fournir court-circuite la re-classification par le
  curateur et préserve le routage décidé à la capture.
- L'écriture est **asynchrone** : conclure uniquement sur `terminal: true` du job, jamais sur
  l'accusé de mise en file. Détail du poll (plafond, états, conflit de verrou) :
  `/gradatum-vault-write`.

### 5. Échec d'écriture — journal d'attente, puis escalade

Une seule tentative, **zéro retry silencieux**. Si le job n'aboutit pas (erreur serveur, plafond de
poll atteint, vault injoignable) :

1. **Appender** la note dans un **journal d'attente append-only**, une ligne JSON par note. Son
   emplacement est une **valeur d'installation**, pas une règle produit : si l'installation en
   déclare un (chemin fixé par la configuration ou surveillé par sa supervision), c'est **celui-là
   et aucun autre** — une note déposée ailleurs n'est reprise par personne, ce qui reproduit
   exactement la perte que ce journal existe pour empêcher. À défaut d'emplacement déclaré, se
   replier sur le voisinage du checkpoint (`pending-vault-writes.jsonl`, chemin dérivé de la même
   façon), et **le signaler** dans l'escalade de l'étape 2.

```
{"ts":"<ISO8601>","skill":"gradatum-memorize","title":"…","section":"…","tags":[…],"body":"…","reason":"<vault-injoignable|job-non-terminal|erreur-serveur>"}
```

2. **Escalader** explicitement : citer le chemin du journal et les titres non persistés.
3. Ne **jamais** laisser une note vivre seulement dans le contexte de la session : le contexte
   disparaît à la fermeture, le journal non.

### Journal de synthèse (obligatoire)

```
## Synthèse — <YYYY-MM-DD>
- Lignes lues : N (dont M malformées, citées)
- Notes écrites : N (par section)
- Skips doublon : N — titres + raison
- Échecs : N → journal d'attente + escalade
```

---

## Voie directe — un événement isolé

Hors session longue, pour un seul événement, on écrit sans passer par le checkpoint :

1. **Anti-doublon d'abord** : `/gradatum-vault-search "<sujet>"`.
2. **Si une note couvre déjà le sujet** → la METTRE À JOUR (pas de doublon) :
   `/gradatum-vault-read "<section>/<ulid>"` pour obtenir l'identifiant + le hash, puis
   `/gradatum-vault-write` en update. **Sinon** → create.
3. **Choisir la section** via l'arbre ci-dessus (la section = dimension de routage des recherches futures).
4. **Écrire** via `/gradatum-vault-write`, cap **500 mots** de corps, puis confirmer par le job.

---

## Titre — règle

Format : `[CATÉGORIE][PROJET] Verbe au passé + objet concret + résultat/impact — date`. Spécifique,
jamais générique.
- ❌ « Note sur l'auth »
- ✅ « [DECISIONS][gradatum] Choisi JWT 24h + refresh-token httpOnly pour l'auth studio — 2026-06-14 »

**Test anti-générique** : si le titre s'applique tel quel à un autre projet, il est trop vague.

## Règles de corps

- **Cap** : 300 mots en synthèse, 500 mots en voie directe. Au-delà : couper après le constat
  factuel et pointer vers le document qui porte le détail.
- **Dates absolues** ISO 8601 — jamais « hier », « la semaine dernière ».
- **Aucune identité humaine** dans le corps. Utiliser les rôles : « l'opérateur », « le
  mainteneur », « l'agent orchestrateur », ou un identifiant d'agent. Vérifier **avant chaque
  écriture**, pas après : une note est durable, et le vault peut être lu bien au-delà de son
  contexte d'origine.
- **Wikilinks** `[[titre-note]]` vers les notes et composants nommés.
- **Tags** structurés `[projet, portée, résultat]`.
- **Ne pas écrire** : contenu éphémère, détail de debug jetable, information déjà portée par le code
  ou l'historique git.

## Checklist anti-rejet du curateur (sections `feedback`, `lessons-learned`, `agent-issues`)

Le curateur rejette les notes **prescriptives non ancrées** — une règle sans contexte ne se relit
pas. Avant d'écrire dans les sections listées ci-dessus, cocher chaque case :

```
[ ] 1. Un composant concret est-il NOMMÉ dans le corps ?
       NON → réécrire : ancrer le contexte AVANT d'énoncer la règle.
[ ] 2. Date ISO + référence concrète (commit, événement, identifiant de test) ?
       NON → ajouter : sans ancre temporelle, la note est classée « directif pur » → rejet.
[ ] 3. Un tag de processus dans les tags ?
       NON → ajouter : sans signal de catégorie → rejet.
```

**Toutes** OUI → écrire. **Une seule** NON → reformuler d'abord.

- ❌ *« Les agents doivent toujours valider avant de déclarer OK »* — aucun composant, aucune date,
  aucun tag de processus.
- ✅ Titre `[FEEDBACK][gradatum] Validation absente 2026-04-23 post-commit 7537bc3` · corps : agent
  déclarant « faux positif » sans preuve → règle : validation obligatoire avant acceptation ·
  tags `[gradatum, process-discipline, validation]`.

## Anti-patterns

- Ne pas mémoriser sans avoir cherché d'abord (doublon).
- Ne pas deviner la section — un mauvais classement casse le recall futur.
- Ne pas persister de l'éphémère : le vault est durable, pas un brouillon.
- Ne pas reporter la mémorisation « plus tard » : **capturer** au moment de l'acte — c'est
  précisément ce que le temps CAPTURE rend bon marché.
- Ne pas écrire dans le vault pendant la capture (le coût est le but de la séparation).
- Ne pas coder en dur le chemin du checkpoint.
- Ne pas grouper N notes en un appel d'écriture.
- Ne pas conclure « écrit » sur l'accusé de mise en file — attendre `terminal: true`.
- Ne pas reconstituer un checkpoint absent depuis le transcript.
