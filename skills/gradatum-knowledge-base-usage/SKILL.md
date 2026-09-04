---
name: gradatum-knowledge-base-usage
description: >
  Guide de routage entre les bases de connaissance : le vault gradatum (mémoire de travail —
  décisions, council, architecture, debug) et l'index de code dérivé `code-<projet>`. Donne la
  règle search-before-write, le triage signal → section, les conventions d'écriture et la formule
  d'acceptation du curateur. Se déclenche **par renvoi de /gradatum-skill-reminder** (chemin
  nominal — ce dernier est invoqué en premier et consomme le signal), ou directement sur un doute
  de surface (« question de code ou question de mémoire ? ») ou de section (« où ranger cette
  note ? »), et avant toute proposition technique. N'appelle rien : il désigne, puis rend la main.
compatibility: claude-code (>= 2.1.0)
---

# /gradatum-knowledge-base-usage

Skill d'orientation : il ne fait aucun appel lui-même. Il dit **où** chercher, **quand** écrire, et
**dans quelle section**, puis renvoie vers les skills atomiques qui exécutent.

## Déclencheur

Ce skill se **déclenche par renvoi**, pas par sélection concurrente. `/gradatum-skill-reminder`
est invoqué en premier sur le prompt et consomme le signal « recherche ou écriture de mémoire
envisagée » : attendre d'être sélectionné sur ce signal-là revient à ne jamais l'être.

Invoquer sur :

- **renvoi de `/gradatum-skill-reminder`** — doute de surface ou de section (chemin nominal) ;
- **doute de surface** : la question porte-t-elle sur la **mémoire** (décision, incident, leçon) ou
  sur le **code** (signature, définition, appelants) ? Les deux ne vivent pas au même endroit ;
- **doute de section** : où ranger une note qu'on s'apprête à écrire ;
- **avant toute proposition technique** — vérifier qu'un arbitrage n'existe pas déjà.

**Ne s'active pas** pour : une conversation sans recherche, une note strictement personnelle, ou
l'exécution d'une commande directe. Ne cherche ni n'écrit lui-même — il désigne, puis rend la main.

## Deux surfaces distinctes, ne pas les confondre

| Besoin | Surface | Skill |
|---|---|---|
| Décisions, verdicts de revue, incidents, leçons, architecture, issues d'agents | vault de mémoire (`main`) | `/gradatum-vault-search` → `/gradatum-vault-read` |
| **Analyse de code** : signature d'un symbole, définition, structure d'un module, appelants | index de code dérivé `code-<projet>` | `/gradatum-code-map` (`code_scope`) |
| Chronologie, « qu'a-t-on changé entre telle et telle date » | vault de mémoire, axe temporel | `/gradatum-vault-timeline` |
| Leçons d'une classe à risque avant un geste risqué | vault de mémoire, recall ciblé | `/gradatum-lessons-recall` |

> Le vault de mémoire et l'index `code-<projet>` sont **deux vaults logiques séparés**. Une
> question de code posée au vault de mémoire ne renvoie rien d'utile, et réciproquement. Le
> tableau ci-dessus **est** l'arbitrage : ne pas le renvoyer à `/gradatum-skill-reminder`, qui
> délègue précisément ici sur ce doute.

**Hors gradatum** : la documentation technique sourcée (RFC, docs officielles, contenu web) ne vit
pas dans le vault. Si l'environnement expose une bibliothèque documentaire dédiée, elle est la
bonne cible — ce skill ne la nomme pas et ne prescrit aucun outil pour elle. Règle de tri d'une
source avant de la conserver : documentation officielle, RFC et spécifications toujours ; blog
reconnu ou conférence si pertinent ; forum avec prudence ; contenu non vérifié jamais.

## Chercher — avant de proposer, avant d'écrire

Règle **search-before-write** : `/gradatum-vault-search` **avant** toute écriture. Elle évite le
doublon et connecte la nouvelle note aux notes existantes. Si une note couvre déjà le sujet →
mise à jour in-place, pas de seconde note.

Recherches réflexes, par intention :

| Avant de… | Chercher dans |
|---|---|
| planifier | `section=reasoning` — un plan comparable a-t-il déjà marché ? |
| diagnostiquer | `section=debug` — ce symptôme a-t-il déjà été vu ? |
| modifier une architecture | `section=architecture` — quelle décision passée s'y applique ? |
| reprendre un sujet déjà traité | `section=lessons-learned` |
| ouvrir une nouvelle phase | `section=retrospectives` — bilan de la précédente |

⚠️ Une recherche qui rend 0 résultat prouve **l'absence dans la surface interrogée**, pas
l'absence tout court. Avant de conclure « ça n'existe pas », vérifier la section, la fenêtre
temporelle et la clé de réponse — les résultats arrivent sous `items`.

## Écrire — triage signal → section

| Signal dans la situation | Section | Tags type |
|---|---|---|
| « on a tranché que X » | `decisions` | `[projet, decision]` |
| verdict d'une revue multi-experts | `council` | `[projet, council, verdict]` |
| choix structurel, pattern d'architecture | `architecture` | `[projet, architecture, domaine]` |
| bug précis + correctif, première occurrence | `debug` | `[projet, debug, symptôme]` |
| plan réutilisable qui a fonctionné | `reasoning` | `[projet, reasoning-pattern, success]` |
| retour utilisateur ancré (validation, correction) | `feedback` | `[projet, feedback, process-discipline]` |
| « la prochaine fois, faire Y » — récurrence constatée (2 fois ou plus) | `lessons-learned` | `[projet, lesson, domaine]` |
| bilan de fin de phase | `retrospectives` | `[projet, retrospective, phase]` |
| hypothèse testée → résultat, positif ou négatif | `experiments` | `[projet, experiment, outcome]` |
| comportement anormal ou récurrent d'un agent | `agent-issues` | `[agent, issue, sévérité]` |
| pointeur vers un système externe (ticket, tableau de bord, doc) | `reference` | `[reference, système-externe]` |
| unité de travail à cycle de vie, jusqu'à `DONE` | `project-map` | voir la mise en garde ci-dessous |

**Frontières qui se ratent souvent** :
- `debug` = incident ponctuel mais référençable · `lessons-learned` = récurrence porteuse d'une
  règle. Ni l'un ni l'autre → ne rien écrire.
- `decisions` = un arbitrage · `retrospectives` = un bilan multi-tâches.
- Un anti-pattern n'a pas de section dédiée : `reasoning` ou `lessons-learned`, avec le tag.
- Une métrique isolée est un tag dans `reasoning`, pas une section.
- `identity` n'est pas une cible d'écriture : elle porte le runtime des personnalités d'agents.
- `project-map` est **hint-only** : sans section suggérée explicite, la note part ailleurs **sans
  erreur**, et une carte y est **insupprimable**. Ne pas y écrire à la légère.

La liste des sections du serveur fait foi (`Section::ALL`). Certaines sont protégées contre la
suppression définitive — voir `/gradatum-vault-write`.

## Conventions d'écriture

- **Titre** : `[CATÉGORIE][PROJET] Verbe au passé + objet concret + résultat — date ISO`.
  Spécifique, jamais générique.
  ❌ « Note sur l'auth » · ✅ « [DECISIONS][monprojet] Retenu JWT 24 h + refresh httpOnly — 2026-08-01 »
  - **Survivance au contenant** : tester avant d'écrire — si le contenant nommé
    (slot/port/machine/phase/version/branche) disparaît, le sujet reste-t-il retrouvable seul ? Si
    non → sujet en tête, jamais le contenant en tête ou seul. Détail + exemples : `/gradatum-memorize`
    §Titre.
- **Corps atomique** : constat factuel, condition de réapplication, référence (commit, date,
  événement). Viser 500 mots ; au-delà, découper.
- **Tags structurés** : `[projet, portée, résultat]`.
- **Dates absolues** (ISO 8601), jamais relatives — « jeudi dernier » devient illisible en trois
  semaines.
- **Liens** `[[note]]` vers les notes voisines : c'est ce qui rend le graphe navigable.
- **Portée** : globale pour un fait transverse, sinon rattachée au projet courant.

## Faire accepter une note par le curateur

Les notes **purement prescriptives** — une directive de comportement sans ancrage concret — sont
rejetées par le curateur du serveur. Trois critères cumulatifs pour passer :

1. **Un composant nommé** (projet, service, module) — l'ancre concrète.
2. **Un constat daté**, avec sa référence (commit, événement, incident).
3. **Un tag de processus** (`process-discipline`, `lesson`, ou un tag de domaine).

❌ Rejeté : *« Les agents doivent toujours tester avant de valider »*
✅ Accepté : *« [FEEDBACK][monprojet] Validation absente le 2026-08-01 après le commit `7537bc3` —
un succès annoncé sans preuve d'exécution → règle : capturer la sortie avant d'annoncer »*

## Anti-patterns

- Écrire sans avoir cherché d'abord → doublon garanti.
- Deviner la section : un mauvais classement casse le recall pour tous les appels suivants.
- Poser une question de code au vault de mémoire, ou une question de décision à l'index de code.
- Persister de l'éphémère : état de travail transitoire, TODO jetable, accord conversationnel.
- Dupliquer ce qui vit déjà dans le code ou l'historique git.
- Conclure « ça n'existe pas » après une seule recherche non concluante.
- Reporter la mémorisation à plus tard : le contexte se perd, la note devient vague.
