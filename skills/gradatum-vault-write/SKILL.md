---
name: gradatum-vault-write
description: >
  Écrit une note dans le vault gradatum — CRÉATION ou MISE À JOUR in-place (RMW).
  RÈGLE OBLIGATOIRE : avant toute création, invoquer /gradatum-vault-search d'abord — si une note
  couvre déjà le sujet, faire un UPDATE (identifiant + hash attendu) plutôt que de créer un
  doublon. Usage : persister durablement une décision, une leçon, une analyse, un compte-rendu.
  L'écriture est ASYNCHRONE (accusé immédiat + identifiant de job) — la confirmation se fait en
  interrogeant l'état du job jusqu'à un état terminal, jamais par supposition.
compatibility: claude-code (>= 2.1.0)
allowed-tools: mcp__gradatum__vault_write mcp__gradatum__job_status
---

# /gradatum-vault-write

Outil atomique d'écriture dans le vault gradatum. Deux modes : **create** (note neuve) et
**update** (MAJ in-place d'une note existante, via son identifiant + un hash attendu).

## Avant d'écrire : anti-doublon (OBLIGATOIRE)

Avant une CRÉATION, chercher d'abord avec /gradatum-vault-search sur le sujet. Si une note couvre
déjà le sujet → **METTRE À JOUR** cette note (mode update), ne PAS créer un doublon. Le vault doit
rester une source unique par sujet, pas une accumulation de variantes.

## Usage

Appeler directement l'outil **`mcp__gradatum__vault_write`** — requis : titre + corps. Les autres
paramètres (section suggérée, tags, auteur, identifiant de note pour une MAJ, hash attendu,
tenant…), leurs défauts et leurs règles de validation sont documentés par l'inputSchema de
l'outil — ne pas les recopier ici. Le corps est transmis intégralement en paramètre (il n'y a pas
de flux stdin en MCP natif).

## Mode CREATE

Fournir titre + corps (+ éventuellement section suggérée, tags, auteur). Sans identifiant de note
fourni, le serveur alloue une note neuve.

## Mode UPDATE (in-place)

> ⚠️ **Le corps fourni REMPLACE le corps ENTIER** de la note. Envoyer la version complète et
> finale — pas un diff, pas un extrait. Un corps partiel **détruit silencieusement** les sections
> non transmises (l'appel n'échoue pas pour autant).

Pour modifier une note existante SANS créer de doublon :

1. Lire la note d'abord avec `mcp__gradatum__vault_read` → récupérer le hash courant et le corps
   actuel complet (pour composer la version de remplacement intégrale).
2. Écrire avec l'identifiant de la note + le hash lu à l'étape 1 + le titre + le corps complet
   remanié.

## Le verrou optimiste — comportement réel

Sur une note **vivante**, fournir le hash attendu déclenche une comparaison réelle contre le
contenu courant côté serveur :

- hash attendu **absent** sur une note vivante → l'appel est refusé immédiatement (écrasement non
  déclaré) — rien n'est écrit.
- hash attendu **fourni et à jour** → la note est réécrite normalement.
- hash attendu **fourni mais périmé** (une écriture concurrente a eu lieu entre ta lecture et ton
  écriture) → l'écriture est **rejetée** et la note reste **inchangée**. Le job correspondant
  atteint un état terminal de conflit — ce n'est pas une erreur serveur, c'est le verrou qui a
  fait son travail.

Conduite à tenir sur un conflit, sans exception : **relire la note, re-fusionner ta modification
sur le corps frais, ré-écrire avec le nouveau hash.** Ne jamais rapporter « écrit » sur un job en
conflit.

## Comportement asynchrone — confirmer par le job, jamais par supposition

`vault_write` répond immédiatement avec un accusé de mise en file (identifiant de job) — **ça ne
signifie pas que la note est écrite**. Le job n'a pas forcément encore tourné.

### Poller `job_status` jusqu'à un état terminal

Interroger `mcp__gradatum__job_status` avec l'identifiant de job rendu par `vault_write`, en
boucle bornée côté agent (l'outil ne fait **aucune attente serveur** — c'est un instantané à
l'instant T ; c'est l'appelant qui re-sollicite, jamais une boucle non bornée).

> ⚠️ Contrairement à un wrapper shell qui pollait à l'intérieur d'un seul appel (un `sleep`
> gratuit et invisible), **chaque poll `job_status` est ici un tour d'agent complet** (raisonnement
> + appel MCP + payload). Sur-poller coûte cher. Le dimensionnement ci-dessous n'est pas indicatif.

**Cadence concrète.** Le worker draine la file en continu, à un rythme de l'ordre de la fraction
de seconde entre deux prises de tâche. Conséquence pratique : le **premier** `job_status`, émis
juste après l'accusé de mise en file, trouve **déjà** un état terminal dans la quasi-totalité des
cas ; un **second** poll couvre l'écrasante majorité du reste. Ne PAS intercaler d'attente
artificielle avant le premier poll — l'écriture est déjà probablement passée. En régime nominal :
**1 à 2 polls suffisent**.

**Plafond dur : 5 polls.** Au-delà de **5** interrogations `job_status` sans avoir observé
`terminal: true`, INTERDIT de conclure « écrit » et INTERDIT de continuer à poller en silence :
**sortir en erreur explicite** — remonter que le job est resté non terminal après le plafond, en
citant l'identifiant de job + le dernier état brut observé, et escalader l'incertitude. Une attente
qui expire sans bruit est un anti-pattern acté : le job peut être coincé, et un « écrit » supposé
serait un faux positif silencieux. Le plafond borne le **nombre de tours**, pas une durée murale —
il n'y a jamais d'attente non bornée ni de sortie muette.

La réponse porte un champ **`terminal`** (booléen) — c'est le champ à lire, **jamais** une liste
d'états codée en dur côté agent : le serveur en est l'unique source de vérité, et cette liste peut
évoluer.

- **`terminal: true`** ⇒ conclure. Recouvre plusieurs états distincts, à distinguer par le champ
  d'état brut renvoyé à côté :
  - écriture aboutie → la note (création ou MAJ) est en place.
  - conflit de verrou optimiste (voir §ci-dessus) → note inchangée, reprendre le cycle
    lire-fusionner-écrire.
  - échec définitif après épuisement des tentatives → l'écriture n'a pas abouti ; le message
    d'erreur porté par la réponse explique pourquoi.
  - job annulé → l'écriture n'a pas abouti.
- **`terminal: false`** ⇒ continuer à poller. **Piège** : un état d'échec *transitoire* apparaît
  aussi ici — une tentative peut échouer puis être reprise automatiquement (retry en attente) ; ce
  n'est PAS un état final, l'agent ne doit pas conclure dessus. Seul `terminal: true` autorise à
  arrêter le poll.

### Anti-pattern spécifique au poll

- Ne jamais interpréter un état d'échec comme final avant d'avoir vérifié `terminal: true` —
  un échec avec retry en attente ressemble à un échec définitif mais ne l'est pas.
- Ne jamais transformer le poll en boucle sans plafond — borner à **5 tentatives** et, au-delà,
  **sortir en erreur explicite** (identifiant de job + dernier état brut) plutôt que de boucler
  indéfiniment ou de conclure en silence.
- Ne jamais intercaler d'attente artificielle avant le premier poll ni sur-poller « par sécurité » :
  chaque poll est un tour d'agent complet, 1 à 2 suffisent en régime nominal.

## Sections

Une section suggérée oriente le classement de la note ; elle n'est jamais devinée au hasard —
c'est la dimension de routage principale des recherches futures. Une décision rangée dans une
section de debug, ou un fait d'architecture rangé dans les décisions, casse le recall pour tout
le monde ensuite.

Une section porte le nom `identity` dans le vocabulaire du serveur : elle est réservée aux âmes
d'agents (chargées au démarrage d'un agent) et n'est pas une cible pour un événement, une décision
ou une leçon ordinaire — ne jamais la choisir pour ce skill.

Certaines sections sont protégées contre la suppression définitive (gouvernance, traçabilité) —
ce n'est pas un choix à faire soi-même, c'est une propriété du serveur ; ne pas s'appuyer sur la
possibilité de "nettoyer" une note mal classée par suppression, corriger plutôt par une MAJ
in-place vers la bonne section.

## Anti-patterns

- Ne JAMAIS créer une note sans chercher d'abord (→ doublon, voir §Avant d'écrire).
- Ne JAMAIS conclure qu'une écriture a réussi sur le seul accusé de mise en file — toujours
  poller `job_status` jusqu'à `terminal: true`.
- Ne pas envoyer un corps partiel en update — il remplace l'intégralité.
- Ne pas coder en dur une liste d'états terminaux côté agent — se fier exclusivement au champ
  `terminal` de `job_status`.
- Sur un conflit de verrou optimiste, ne jamais réessayer l'écriture avec le même hash — toujours
  relire la note fraîche d'abord.
- Ne pas écrire de contenu éphémère (détails de debug jetables, état de session) — le vault est
  durable.
- Le titre doit être spécifique : « Note sur X » est un mauvais titre.
- Ne JAMAIS deviner la section — voir §Sections.
