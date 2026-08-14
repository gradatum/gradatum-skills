---
name: gradatum-code-map
description: >
  Carte de code dérivée d'un projet (vault logique `code-<projet>`) — signatures et corps de
  symboles (fonctions, structs, traits…) extraits par tree-sitter, sans LLM. Deux moitiés :
  GARANTIR LA FRAÎCHEUR de l'index (ingestion et rafraîchissement, opération d'administration en
  ligne de commande sur l'hôte gradatum — PAS une opération MCP) puis INTERROGER via
  `mcp__gradatum__code_scope`. Invoquer pour COMPRENDRE/NAVIGUER du code sans lire des fichiers
  entiers : « où est défini X ? », « quelle est la signature de Y ? », « quels symboles matchent
  Z ? », « qui appelle X ? ». Invoquer AUSSI pour la moitié fraîcheur : « rafraîchis / réindexe /
  ré-ingère la carte de code », « indexe ce projet », « la carte de code est périmée », « l'index
  ne connaît pas ce symbole », ou après un commit qui change des signatures. Économise des tokens
  vs la lecture brute. Composable par /gradatum-skill-reminder.
compatibility: claude-code (>= 2.1.0)
allowed-tools: mcp__gradatum__code_scope
---

# /gradatum-code-map

Carte de code à la demande : interroger un index dérivé (tree-sitter, zéro-LLM, régénérable)
plutôt que relire des fichiers entiers.

**Principe** : *le dépôt git est la vérité, l'index en est intégralement dérivé.* Un index périmé
coûte PLUS cher que pas d'index (une signature fausse produit un raisonnement faux) →
**exactitude > couverture** : au moindre doute, rafraîchir, ou retomber sur la lecture du **code
source**. Jamais raisonner sur du périmé.

Le skill a deux moitiés, à ne pas confondre :

| Moitié | Par quoi | Qui peut |
|---|---|---|
| **ENSURE-FRESH** — ingérer / rafraîchir l'index | CLI d'administration sur l'hôte gradatum | seulement un accès shell privilégié |
| **QUERY** — interroger l'index | outil MCP `code_scope` | tout agent |

## Quand invoquer

- « Où est défini `X` ? Quelle est sa signature ? » → recherche par nom de symbole.
- « Quels symboles concernent `Z` ? » → recherche par mots-clés.
- « Que contient `src/auth.rs` ? » → recherche par chemin de fichier.
- « Qui appelle `X` ? » → dépendance inverse (voir §Corps et appelants).
- Comprendre une implémentation sans charger le fichier entier (économie de tokens).

**NE PAS invoquer** : lecture d'un fichier unique déjà ciblé (lecture directe) · question hors-code
· projet qu'on n'a pas l'intention d'indexer.

---

# Moitié 1 — ENSURE-FRESH (administration, hors MCP)

## Prérequis

- Un **accès shell privilégié à l'hôte gradatum**. L'ingestion et le rafraîchissement ne passent
  **pas** par MCP : aucun outil MCP ne les expose, c'est une opération d'administration en ligne
  de commande.
- La **CLI d'administration** gradatum (`gradatum-admin`) disponible sur cet hôte.
- Les **valeurs concrètes de l'installation** — emplacement du miroir indexé, compte système
  propriétaire des données, répertoire racine de données s'il n'est pas au défaut — ne sont **pas**
  dans ce fichier : elles sont propres à chaque installation et vivent dans une note du vault en
  `section=architecture`. Les y chercher plutôt que les deviner. Sur une installation neuve, cette
  note n'existe pas encore : ces valeurs sont alors un **choix d'installation** à poser une fois,
  puis à consigner dans cette note pour les cycles suivants.

**Sans accès privilégié** : ne JAMAIS servir une analyse sur un index absent ou périmé. Signaler
l'état (« index `code-<projet>` absent / périmé »), demander le rafraîchissement à qui a l'accès,
et retomber entre-temps sur la lecture du **dépôt source**, qui est frais par construction.

## Pourquoi un miroir, et pas le dépôt de travail

Le serveur relit le dépôt en continu (détection de dérive fichier par fichier) sous son propre
compte système. Il ne peut donc pas indexer un dépôt de travail situé dans un répertoire personnel
qui lui est fermé. L'index pointe sur un **miroir** du dépôt, possédé par le compte de service, que
l'on fait avancer depuis le dépôt de travail à chaque rafraîchissement.

Conséquence utile : le rafraîchissement récupère les commits **locaux non poussés** (il tire depuis
le dépôt de travail, pas depuis un remote).

## Séquence

### Étape 0 — valider le nom de projet

Le nom de projet partage le jeu de caractères du vault (`[a-z0-9-]`). **Le valider avant toute
interpolation** dans un chemin ou une commande — le rejet côté serveur ne protège ni les chemins ni
les commandes construits localement. Le vault cible est `code-<projet>`.

### Étape 1 — l'index existe-t-il ?

Appeler `code_scope` sur le vault, avec un critère trivial et un budget minimal.

- **Erreur explicite « vault inconnu / jamais ingéré »** ⇒ jamais ingéré → Étape 3a.
  ⚠️ Ne pas confondre avec une réponse **vide** (`total_matched: 0`) : celle-ci prouve que le vault
  **existe** et que le critère n'a rien trouvé.
- **Réponse normale** ⇒ ingéré → Étape 2.
- **Toute autre erreur** (authentification, stockage, indisponibilité) ⇒ erreur explicite. Ne
  JAMAIS en déduire « ingéré » et enchaîner : signaler et retomber sur la lecture source.

### Étape 2 — l'index est-il à jour ?

Comparer deux HEAD git et vérifier l'absence de sentinelle :

1. `HEAD` du **dépôt source** ;
2. `HEAD` du **miroir** (absent = miroir jamais créé) ;
3. présence d'un **fichier sentinelle** à la racine du miroir (voir Étape 3b).

- HEAD source == HEAD miroir **ET** sentinelle absente → **aligné** → Moitié 2 (query).
- Sinon (HEAD différents, miroir absent, **ou sentinelle présente**) → **périmé** → Étape 3b.

> **Ce que cette comparaison garantit — et ce qu'elle ne garantit pas.** Elle compare deux HEAD
> git ; elle ne lit pas le commit réellement indexé. La garantie est : miroir == source ⇒ le
> *contenu* du miroir reflète le commit source. Toute dérive résiduelle (modification non commitée
> dans le miroir) est rattrapée par le drapeau `stale` **au grain du fichier**, exposé sur chaque
> entrée à la query. Et cet alignement n'est fiable **que parce que l'Étape 3b échoue bruyamment** :
> le miroir n'est jamais avancé sans un `update` réussi.

### Étape 3a — ingestion initiale

1. Créer le miroir : cloner le dépôt source vers l'emplacement de miroir, puis en donner la
   propriété au compte de service.
   ⚠️ Un utilisateur privilégié opérant sur un dépôt possédé par un autre compte doit lever la
   garde git de propriété douteuse (`-c safe.directory=…`), sinon git refuse.
2. Ingérer : `gradatum-admin code ingest <miroir> --vault code-<projet> --visibility <pub|all>`
   (+ l'option de racine de données si l'installation n'est pas au défaut).

L'ingestion est **idempotente** : un fichier inchangé est sauté. `--rebuild` force une
reconstruction totale (suppression puis ré-ingestion) — c'est la voie pour **changer le mode de
visibilité** d'un vault existant.

### Étape 3b — rafraîchissement incrémental

**L'ordre des étapes EST la correction.** Deux invariants la portent :

- **la sentinelle de cycle est posée AVANT d'avancer le miroir** — une interruption externe (arrêt
  brutal, OOM, gel) la laisse en place, et le cycle suivant traite le miroir comme périmé même si
  les deux HEAD coïncident. Sans elle, un miroir avancé mais non indexé serait servi comme frais ;
- **le HEAD du miroir est capturé AVANT le fetch** — c'est le point de rollback, et sans lui un
  échec d'indexation laisse un miroir avancé sans index correspondant.

Séquence, dans cet ordre exact :

1. **Capturer** le `HEAD` courant du miroir → `prev` (point de rollback).
2. **Tirer** depuis le dépôt source vers le miroir. Échec ⇒ abandonner immédiatement, rien n'a
   bougé.
3. **Vérifier** que le commit ramené est bien le `HEAD` du dépôt source **de ce cycle** — cela
   neutralise un pointeur de fetch resté d'un cycle antérieur. Divergence ⇒ abandonner.
4. **Poser la sentinelle** à la racine du miroir (fichier vide, nom stable, ex.
   `.refresh-incomplete`), sous le compte de service. Elle doit rester **non suivie par git** :
   c'est ce qui la fait survivre à la réinitialisation dure de l'étape suivante, et donc ce qui la
   rend fiable.
5. **Avancer** le miroir sur le commit ramené (réinitialisation dure), puis restaurer la propriété
   du compte de service.
6. **Indexer** : `gradatum-admin code update <miroir> --vault code-<projet>`.
7. **Selon l'issue** :
   - succès ⇒ **retirer la sentinelle** — le cycle est complet, l'invariant est rétabli ;
   - échec ⇒ **rollback** : ramener le miroir sur `prev`, retirer la sentinelle, restaurer la
     propriété, **sortir en erreur explicite**. Ne pas servir d'analyse : retomber sur la lecture
     du dépôt source.

`code update` travaille en **O(diff)** depuis la dernière ingestion (ré-ingère les fichiers ajoutés
ou modifiés, supprime les effacés, enregistre le nouveau HEAD) — **cible < 3 s**. S'il n'existe
aucune ingestion antérieure, il **retombe de lui-même sur une ingestion complète**.

> **Concurrence.** L'index est une base partagée avec le serveur en fonctionnement (accès
> concurrent). Une erreur de verrou ou un dépassement de délai n'est pas une corruption :
> **relancer l'Étape 3b**, que la sentinelle et le rollback rendent idempotente.

## Visibilité — `pub` (défaut) ou `all`

Le critère est l'**intention**, pas la nature du projet :

- **`pub`** (défaut, léger) — naviguer l'**interface** : ce qu'un consommateur voit, y compris sur
  son propre projet. À préférer pour cartographier une API.
- **`all`** — analyser l'**implémentation interne** (refactoring, débogage, impact sur du privé) :
  indexe **aussi** les items privés. Coût : volume nettement supérieur, et les items privés peuvent
  noyer les publics en recherche plein-texte (aucune hiérarchie public > privé au classement) tout
  en consommant le budget de réponse.

Le mode est **persisté par vault** à l'ingestion et réutilisé par les rafraîchissements suivants
sans avoir à le redonner. Un override posé sur un `update` ne retraite que les fichiers du diff :
pour **changer le mode d'un vault existant**, passer par `ingest --rebuild --visibility <mode>`.

---

# Moitié 2 — QUERY (outil MCP)

## Usage

Appeler directement l'outil **`mcp__gradatum__code_scope`** — requis : le vault cible et un
critère de recherche. Le vault cible doit désigner un projet indexé (préfixe `code-`) — un vault
qui ne le porte pas est rejeté, c'est un invariant de sécurité, pas une option. Les autres
paramètres (forme du critère, budget de réponse, inclusion du corps exact, inclusion des
appelants…), leurs défauts et leurs règles de validation sont documentés par l'inputSchema de
l'outil — ne pas les recopier ici.

**Trois formes de critère**, à choisir selon la question :

| Forme | Usage | Classement |
|---|---|---|
| **symbole** | signature + dépendances d'un symbole nommé | par pertinence — plusieurs homonymes possibles |
| **mots-clés** | découverte par sujet (plein-texte) | par pertinence — prévoir un budget large |
| **chemin** | tous les symboles d'un fichier ou d'un répertoire | déterministe, aucun classement |

## Comment décider (interprétation)

1. **Signatures d'abord** (sans le corps exact) : trier les symboles pertinents à coût minimal.
2. **Corps ensuite**, sur les symboles **retenus** uniquement — pattern deux passes obligatoire :
   activer le corps exact sur une requête large annule le gain de tokens que l'index apporte.
   Passe 1 large sans corps → passe 2 ciblée avec corps sur les seuls symboles sélectionnés.
3. Une entrée marquée **périmée** (le fichier source a changé depuis le dernier index) ne doit
   jamais être utilisée comme vérité — ne pas te fier à son corps, relire le fichier source, ou
   déclencher un rafraîchissement (Moitié 1) si l'accès le permet.
4. Si la réponse signale que des entrées ou des corps ont été omis par dépassement du budget de
   réponse, resserrer le critère de recherche plutôt que d'élargir aveuglément le budget.

## Calibration mesurée — SÉLECTIF vs EXHAUSTIF-IN-SCOPE

Le bon mode dépend de l'**intention**. Chiffres issus de 4 runs comparatifs sur un audit réel, à
périmètre de fichiers identique (même sous-système, mêmes 8 fichiers) — provenance à garder avec le
chiffre, ce ne sont pas des ordres de grandeur devinés :

| Intention | Mode | Procédure | Gain tokens | Couverture |
|---|---|---|---|---|
| **EXPLORER** (« comprends X », « où est Y », question ciblée) | **SÉLECTIF** (2 passes) | Passe 1 sans corps → trier les N symboles pertinents ; Passe 2 avec corps **sur les retenus uniquement** | **−15 % mesuré**, jusqu'à ~−40 % extrapolé selon le ratio retenus/total | partielle (ce qu'on a choisi de charger) — OK pour explorer, **INTERDIT pour un audit** |
| **AUDITER** (revue exhaustive, « tous les défauts de ce sous-système ») | **EXHAUSTIF-IN-SCOPE** (zéro triage) | critère `chemin` + corps pour les petits fichiers (tous les corps en un appel), critère `symbole` + corps pour les fonctions ciblées d'un gros fichier. **Charger TOUS les corps du périmètre, n'en sauter aucun.** | **−5 % mesuré** vs lecture brute | **maximale, supérieure à la lecture brute** |

> **Pourquoi l'exhaustif bat la lecture brute sur les deux axes** : en ne chargeant que les corps du
> périmètre (et pas les milliers de lignes hors périmètre d'un gros fichier), le rapport
> signal/bruit est meilleur → analyse plus profonde → plus de défauts trouvés, pour MOINS de
> tokens. Mesuré : le run exhaustif a été le seul à trouver les trois défauts cibles, à −4,6 % de
> tokens vs lecture brute.
> **Piège du sélectif sur un audit** : trier, c'est sauter des corps, donc créer des angles morts —
> le run sélectif a raté les trois. La couverture partielle est une *fonctionnalité* pour explorer,
> un *défaut* pour un audit.

**Budget de corps par intention** (le défaut du serveur vise l'exploration, pas l'audit) : explorer
→ de l'ordre de 8 000 à 12 000 ; auditer un sous-système de plus de 3 fichiers → de l'ordre de
16 000 à 24 000 (compter ~150 tokens par corps × nombre de symboles du périmètre). Au-delà, le
plafond est imposé par le serveur.

**Règle** : `intention = explorer → SÉLECTIF` · `intention = auditer → EXHAUSTIF-IN-SCOPE`. **Le
critère est l'OBJECTIF, pas le verbe employé** : si une omission de corps peut cacher un défaut,
c'est un audit → EXHAUSTIF. **Un audit en sélectif est incorrect. Dans le doute → EXHAUSTIF.**

## Corps et appelants — deux capacités additives, off par défaut

- **Corps exact** : le corps d'un symbole n'est jamais renvoyé silencieusement s'il est périmé —
  une entrée périmée n'a jamais de corps, même si demandé. Un corps absent signifie donc : entrée
  périmée, **ou** span indisponible, **ou** budget de corps épuisé.
- **Appelants** (dépendance inverse) : liste les symboles qui dépendent du symbole ciblé — répond
  directement à « qui appelle X ? » sans grep manuel. La liste peut être tronquée pour un symbole
  massivement utilisé (ex. une fonction utilitaire commune) ; un signal dédié l'indique quand c'est
  le cas — ne pas présenter une liste tronquée comme exhaustive.

Ces deux capacités sont indépendantes l'une de l'autre et du budget de signatures — les activer
n'affecte pas le nombre de symboles retournés en tête.

## Règles de lecture du résultat (BLOQUANTES)

- **Entrée périmée** → signature potentiellement fausse. **Préférer** un rafraîchissement (Étape
  3b) ; si impossible, lire le fichier source réel pour CE symbole. **Jamais raisonner sur une
  signature périmée.**
- **Réponse tronquée** → des entrées ont été omises faute de budget. Élargir le budget OU resserrer
  le critère (chemin d'un sous-répertoire). Ne pas en conclure « le fichier est petit ».
- **Aucun résultat sur un critère `symbole`** → le symbole est absent, **OU** il vit dans un fichier
  que l'analyseur ne parse pas (macros opaques, code généré, scripts de build), **OU** c'est un item
  **privé sur un vault ingéré en `pub`**. **Vérifier dans la source avant de conclure à
  l'inexistence** (exactitude > couverture).
- **Plusieurs résultats sur un critère `symbole`** → des homonymes, classés par pertinence : le
  symbole voulu peut être noyé. **Affiner** avec le nom qualifié complet OU basculer sur un critère
  de chemin (déterministe). **Ne pas traiter la première entrée comme la bonne.** N.B. sur un
  critère de chemin, N entrées est le comportement **nominal** (tous les symboles du fichier) — la
  règle ne s'y applique pas.
- **Les dépendances listées sont SORTANTES uniquement** (ce que le symbole appelle). Pour l'inverse,
  utiliser la capacité **appelants** — ne pas confondre une mention plein-texte avec un appel prouvé.

## Anti-patterns

- Ne pas interroger un vault qui ne porte pas le préfixe réservé aux projets de code — rejeté.
- Ne pas activer le corps exact sur une requête large (mots-clés non ciblés) — trier par signature
  d'abord, corps ensuite sur la sélection.
- Ne pas se fier au corps d'une entrée périmée — le corps est de toute façon absent dans ce cas.
- Ne pas présenter une liste d'appelants tronquée comme exhaustive sans vérifier le signal de
  troncature.
- Ne pas confondre « erreur : vault jamais ingéré » et « zéro résultat » — la première appelle une
  ingestion, la seconde un autre critère.
- Ne jamais avancer le miroir sans avoir capturé son HEAD et posé la sentinelle d'abord — c'est
  exactement la fenêtre qui produit un index faussement frais.
- Ne jamais servir une analyse sur un index périmé faute d'accès au rafraîchissement — signaler et
  lire la source.
- Pour de la cohérence inter-fichiers étroite (trait ↔ impl éparpillés, câblage manquant entre une
  déclaration et ses implémentations) ou un très petit nombre de fichiers concernés, lire le source
  directement reste parfois plus simple que cet outil.

## Limites connues

- **Fraîcheur = tirée à l'invocation** : entre deux rafraîchissements, l'index fige. Automatiser via
  un hook de commit côté source, ou une synchronisation périodique, pour un projet à garder toujours
  frais.
- Le commit réellement indexé n'est pas exposé : la détection de péremption est un **proxy** par
  comparaison de HEAD, fiable grâce au caractère bruyant de l'échec au rafraîchissement.
- **Langages** : analyse **Rust** uniquement — les autres langages ne sont pas indexés.
- Les corps servis sont **isolés** : l'index ne voit pas l'absence d'un câblage entre deux fichiers.
