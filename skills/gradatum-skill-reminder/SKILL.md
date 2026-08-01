---
name: gradatum-skill-reminder
description: >
  Recall pré-action métamémoire — sur prompt utilisateur (question, recherche, brainstorming,
  diagnostic, amorce de tâche substantielle, décision, planification), détermine si une
  recherche vault gradatum est pertinente et invoque /gradatum-vault-search avec les mots-clés
  extraits — ou /gradatum-vault-timeline à la place si besoin temporel PUR (fenêtre de
  dates ou chronologie sans sujet métier identifiable).
  SKIP si validation/négation seule ("oui", "go", "ok"), exécution commande directe,
  slash-command, salutation, ou prompt trivial (<10 caractères utiles).
  Après le vault-search, tire la surface proactive F-46 (vault_proactive_recall sans context,
  limit 3, non bloquant) et poste le feedback d'apprentissage dès la sélection des résultats
  (vault_proactive_recall_feedback, liste vide valide). Logique de décision + 2 appels MCP
  bornés côté CHERCHE ; le chemin SKIP reste zéro vault call. Sur doute de surface (question de
  code plutôt que de mémoire) ou de section, renvoie vers /gradatum-knowledge-base-usage — ce
  renvoi est le seul chemin d'accès à ce dernier, le signal étant consommé ici.
type: gradatum
compatibility: claude-code (>= 2.1.0)
---

# /gradatum-skill-reminder

Déclencheur métamémoire — détermine si le prompt courant nécessite une recherche vault,
délègue à /gradatum-vault-search et tire la surface proactive F-46 (recall pré-calculé +
feedback d'apprentissage, best-effort assumé). Logique de décision + 2 appels MCP bornés
côté CHERCHE ; le chemin SKIP reste zéro vault call ; le `recall_id` ne vit que le tour courant.

## Règles de décision (évaluées sur le prompt utilisateur courant)

### CHERCHE — invoquer /gradatum-vault-search si le prompt est :

- **Question** ("comment", "pourquoi", "que fait", "qu'est-ce que", "on a déjà", "c'est quoi")
- **Recherche / exploration** ("on creuse", "analyse", "étudie", "compare", "cherche")
- **Brainstorming** ("réfléchis", "propose", "imagine", "design", "idées", "options")
- **Diagnostic** ("ça plante", "erreur", "comprends pas", "pourquoi ça fail", "debug")
- **Décision / planification** ("on va", "je veux", "plan", "on commence", "étape", "roadmap")
- **Amorce de tâche substantielle** (≥ 1 verbe métier + objet concret identifiable)
- **Mots-clés mémoire / gradatum** ("vault_search", "écrire note", "récupérer décision",
  "architecture", "décisions", "council", "retrospective", "lessons-learned", "memo")

### SKIP — ne rien invoquer, traiter normalement si le prompt est :

- **Validation / négation seule** ("oui", "go", "valide", "non", "stop", "ok", "c'est ça",
  "continue", "parfait", "bien", "merci")
- **Exécution commande directe** ("lance X", "exécute Y", "run Z", "fais X")
- **Slash command** — toute invocation directe d'un skill par son nom (/gradatum-vault-search, et
  de même pour tout autre skill présent dans l'environnement)
- **Salutation / social** ("bonjour", "merci", "à plus", "bonne journée")
- **Trivial** (< 10 caractères utiles dans le prompt)

## Renvoi obligatoire — doute de surface ou de section

Ce skill est invoqué **en premier** sur le prompt courant et tranche le routage en interne : le
signal qui aurait sélectionné `/gradatum-knowledge-base-usage` est consommé ici. Ce renvoi est donc
son **seul** chemin d'accès — ne pas compter sur une sélection concurrente, elle n'aura pas lieu.

Avant l'étape 1, si **l'une** de ces conditions tient :

- la question porte sur du **code** (signature d'un symbole, définition, structure d'un module,
  appelants) plutôt que sur une décision ou un incident → la bonne surface est l'**index de code**,
  pas le vault de mémoire ; un keyword-search vault ne rendra rien d'utile ;
- la **section** cible d'une écriture à venir est incertaine ;
- on hésite entre **chercher** et **écrire** ;

→ invoquer **`/gradatum-knowledge-base-usage`** et suivre son routage. C'est un skill
d'orientation : aucun appel, aucun coût vault. Il rend la surface et la section ; les étapes
ci-dessous s'appliquent ensuite, ou sont remplacées par la surface qu'il désigne.

Aucun doute → poursuivre directement.

## Action si CHERCHE

0. **Test temporel** (2 questions, zéro vault call, avant l'étape 1) :
   **Q1 — signal temporel pur ?** Fenêtre bornée (« entre le X et le Y », « ces N derniers
   jours »), chronologie exhaustive d'une période, ou snapshot SANS sujet (« l'état des
   décisions au <date> »). NON ou doute → étapes 1-2 (défaut keyword-search).
   **Q2 — bornes retirées, reste-t-il un terme métier identifiable ?**
   - **NON** (temps sans sujet) → appeler directement l'outil **`mcp__gradatum__vault_timeline`**
     avec `from_ms`/`to_ms` (et `doc_kind: Static|Event` si le filtre s'applique) — ceci
     REMPLACE les étapes 1-2 ; étapes 3-5 inchangées (les « deux sorties » de l'étape 5 =
     timeline + surface proactive). Bornes epoch ms TOUJOURS via commande — ex.
     `TZ="Europe/Paris" date -d "2026-07-10 00:00:00" +%s%3N` (fin de fenêtre = dernier
     jour 23:59:59.999) — jamais de calcul mental. NB : as-of via ce skill = fenêtre
     d'ancres, pas validité as_of_ms.
   - **OUI** (sujet+temps : « décisions sur le reranker cette semaine », « historique de
     la migration X ») → étapes 1-2 normales ; bornage éventuel via l'outil MCP
     `vault_search` (`from_ms`/`to_ms`, non exposés par le skill search). Ne PAS doubler
     d'un appel timeline.

1. Extraire 3 à 7 mots-clés sémantiques du prompt courant
   (verbes métier + objets concrets ; exclure les mots-vides)
2. Invoquer `/gradatum-vault-search "<keywords concaténés>"`
3. **Dans le même bloc d'actions**, appeler `mcp__gradatum__vault_proactive_recall` avec
   `limit: 3` et **SANS `context`** — surface proactive PRÉ-CALCULÉE côté serveur (F-46),
   complément orthogonal au keyword-search de l'étape 2 (ne pas re-passer les mots-clés :
   `context` présent re-exécuterait le même RRF = redondance). **Non bloquant** :
   échec/timeout → continuer sans (log 1 ligne), ne jamais bloquer la réponse ;
   retenir le `recall_id` retourné.
4. **Dès la sélection des résultats** (avant de rédiger la réponse), juger la pertinence des
   notes du vault-search ET de la surface proactive — puis, si l'étape 3 a renvoyé un
   `recall_id`, appeler AUSSITÔT `mcp__gradatum__vault_proactive_recall_feedback` avec
   exactement `{recall_id, accepted_ulids}` (payload strict, `deny_unknown_fields` côté
   serveur) où `accepted_ulids` = les ULIDs de la surface proactive jugés pertinents et
   retenus pour informer la réponse. **Liste vide = feedback valide et attendu** (« rien de
   pertinent » est le signal d'apprentissage le plus fréquent, pas une anomalie). Feedback =
   MÊME tour, jamais différé ; **non bloquant** (échec du POST → continuer, log 1 ligne).
   Si l'étape 3 a échoué (pas de `recall_id`), aucun feedback à poster.
   *Best-effort assumé* : aucun vérificateur mécanique n'existe (dette enforcement tracée) —
   l'anti-pattern d'omission ci-dessous est le levier de discipline.
5. L'agent reçoit les deux sorties et décide selon la doctrine portée par /gradatum-vault-search.
   La boucle F-46 est une **métrique d'usage** (quels items proactifs sont réellement
   actionnés), pas un auto-tuning — ne pas en attendre une convergence rapide (source unique,
   faible volume).

## Action si SKIP

Ne rien faire. Pas d'output. Traiter le prompt normalement.

## Sections canoniques gradatum

Liste et sémantique des sections : **autorité unique `/gradatum-vault-write`** (reflet
opérationnel de `Section::ALL`, code serveur). La gouvernance de cette taxonomie relève de
l'installation, pas de ce fichier. Ne pas la recopier ici et ne graver aucun compte —
un nombre dupliqué dérive : ce fichier a annoncé « 11 » pendant deux extensions de la
taxonomie.


## Convention titre vault (anti-doublon)

Format strict : `[CATÉGORIE][PROJET] Verbe objet — date`

Exemples valides :
- `[DECISIONS][gradatum] Choix reranker BGE-v2-m3 — 2026-05-10`
- `[COUNCIL][my-project] Révision archi skills — 2026-05-10`
- `[RETRO][my-project] Release v1.2 LIVRÉE — 2026-03-07`

## Anti-patterns

- Ne pas se substituer à /gradatum-vault-search pour la recherche effective
- Ne pas interpréter les résultats de /gradatum-vault-search (délégué à l'agent appelant)
- Ne pas mémoriser d'état entre invocations (le `recall_id` vit uniquement le temps du tour courant)
- **Ne jamais clore un tour où `vault_proactive_recall` a renvoyé un `recall_id` sans avoir
  posté `vault_proactive_recall_feedback`** : la dette de feedback est une obligation du même
  tour. Liste vide autorisée ; c'est l'OMISSION — pas la liste vide — qui casse la boucle F-46.
- Ne pas différer le feedback à un tour ultérieur, ni passer `context` au recall (redondance
  RRF avec l'étape 2), ni gonfler `limit` au-delà de 3 sans révision (le skill fire à chaque
  réponse substantielle — l'injection est multipliée par la fréquence).
