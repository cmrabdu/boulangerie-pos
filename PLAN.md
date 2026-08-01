# Plan

Colonne vertébrale du projet. **Ce fichier porte l'état réel du travail** :
une session qui démarre le lit et reprend à la première case non cochée.

Statuts : ⬜ à faire · 🟡 en cours · ✅ terminé et vérifié

> **Une case cochée est une promesse.** On ne coche jamais sans avoir vu la
> chose fonctionner dans l'application qui tourne. Un test qui passe ne suffit
> pas à cocher une case d'interface ; il faut l'avoir regardée.

---

## Sur le Mac — ne nécessite pas d'accès à la boulangerie

### Phase 0 — Fondations ✅

- [x] 0.1 Dépôt, structure, `.gitignore`, licence
- [x] 0.2 `CLAUDE.md` (conventions) et `PLAN.md` (ce fichier)
- [x] 0.3 `README.md`
- [x] 0.4 `Makefile` : `dev`, `lan`, `build`, `linux`, `test`

### Phase 1 — Squelette technique ✅

- [x] 1.1 Binaire Go unique, front embarqué par `go:embed`
- [x] 1.2 SQLite en Go pur (`modernc.org/sqlite`) — permet la compilation
      croisée Mac → Linux sans cgo
- [x] 1.3 Serveur HTTP, arrêt propre sur SIGTERM
- [x] 1.4 Mode `-dev` (front lu depuis le disque) et mode `-lan` (test depuis
      un iPad ou un téléphone)

### Phase 2 — Catalogue et données ✅

- [x] 2.1 Schéma SQLite — **tous les montants en centimes, jamais de flottant**
- [x] 2.2 Catalogue de démonstration (6 catégories, 57 produits)
- [x] 2.3 `GET /api/catalog`
- [x] 2.4 Import CSV `-import` : séparateur `;` ou `,` détecté, prix « 1,30 »
      ou « 1.30 », BOM Excel, espaces insécables
- [x] 2.5 Tests unitaires : analyse des prix, import, total recalculé, archivage

### Phase 3 — Écran principal ✅

- [x] 3.1 Jeton de design : échelle en `rem` indexée sur la hauteur d'écran,
      donc une seule interface pour 1366×768 comme pour 1920×1080
- [x] 3.2 Onglets de catégories
- [x] 3.3 Grille de produits
- [x] 3.4 Ticket, lignes, quantités
- [x] 3.5 Total, gros et toujours au même endroit
- [x] 3.6 Vérifié en 1366×768 : aucun débordement, tuiles 221×123 px,
      boutons de paiement 176×90 px, total en 50 px

### Phase 4 — Tactile et animations ✅

- [x] 4.1 Enfoncement déclenché sur `pointerdown` (pas `click`)
- [x] 4.2 Courbe `ease-out` iOS, durées 140–260 ms
- [x] 4.3 Animations interruptibles (la précédente est annulée, jamais empilée)
- [x] 4.4 `transform`/`opacity` uniquement
- [x] 4.5 Anti-zoom, anti-sélection, anti-double-tap, `touch-action`
- [x] 4.6 Total qui défile de l'ancienne à la nouvelle valeur
- [x] 4.7 **Validé sur un vrai écran tactile** — essayé sur tablette par le
      user le 29/07 : rendu et animations validés.

### Phase 5 — Encaissement ✅

- [x] 5.1 Écran de paiement en surimpression
- [x] 5.2 Cash : propositions de coupures, saisie de ce que donne le client
- [x] 5.3 Calcul et affichage du rendu de monnaie
- [x] 5.4 Bancontact : affichage du montant, encodage manuel sur le terminal
- [x] 5.5 Arrondi belge aux 5 centimes sur les espèces, **affiché explicitement**
      (constante `ARRONDI_CASH_5_CENTIMES` — voir §Questions ouvertes)
- [x] 5.6 Confirmation animée puis retour à zéro — la feuille de paiement se
      retire pendant que la coche monte, avec un léger dépassement d'échelle
- [x] 5.9 Coupures proposées jusqu'au billet de 100 €
- [x] 5.7 Une vente qui échoue à s'enregistrer conserve le ticket à l'écran
- [x] 5.8 Vérifié de bout en bout : 5,00 € sur 4,40 € dus → 0,60 € rendus,
      vente écrite en base et retrouvée dans l'export CSV

### Phase 6 — Journal des ventes ✅

- [x] 6.1 Tables `sales` / `sale_lines`, nom et prix recopiés pour figer
      l'historique
- [x] 6.2 `POST /api/sales` — le total est recalculé côté serveur
- [x] 6.3 `GET /api/sales/export.csv` — point-virgule, virgule décimale, BOM,
      donc ouvrable directement dans Excel

### Phase 7 — Mise à jour du catalogue ✅

> **Décision du 29/07** : pas d'écran de paramètres, pas de bouton caché, pas de
> code à 4 chiffres. Le catalogue se met à jour en déposant un CSV par SSH.
> Tout ce qui ne sert pas à encaisser n'a rien à faire devant quelqu'un qui
> sert des clients.

- [x] 7.1 Surveillance de `catalogue.csv`, réimport automatique en ~3 s
- [x] 7.2 Endpoint `/api/catalog/version` et rafraîchissement silencieux
- [x] 7.3 Jamais de rafraîchissement pendant une vente (panier non vide ou
      écran de paiement ouvert)
- [x] 7.4 Un CSV illisible est refusé, l'ancien catalogue reste en place
- [x] 7.5 Au premier démarrage, un CSV déjà présent l'emporte sur le catalogue
      de démonstration
- [x] 7.6 Vérifié : dépôt d'un CSV → prix passés de 1,30 à 1,35 et catégories
      de 6 à 3 à l'écran, sans redémarrage, en restant sur l'onglet ouvert

### Phase 7 bis — Images et icônes ✅

- [x] 7b.1 Slug calculé côté serveur : « Éclair chocolat » → `eclair-chocolat`
- [x] 7b.2 Dossier `img/` servi depuis le disque, hors de l'exécutable :
      ajouter une image ne demande aucune recompilation
- [x] 7b.3 Image dans la carte **sans l'agrandir** : moitié droite, débordement
      léger, dégradé de la couleur de la carte au-dessus côté texte
- [x] 7b.4 Un produit sans image s'affiche exactement comme avant
- [x] 7b.5 Icônes de catégories dessinées au trait, en ligne dans la page,
      déduites du nom de la catégorie par mots-clés — le texte reste affiché
- [x] 7b.6 Script de génération lisant la clé depuis l'environnement
- [x] 7b.7 Trois styles comparés dans la vraie tuile (`/essai.html`) :
      gouache retenue, photo et plat conservés en option
- [x] 7b.8 Icônes générées par IA testées contre le tracé vectoriel :
      **écartées** — monochromes donc sans couleur de catégorie, illisibles sur
      l'onglet actif sombre, graisses de trait incohérentes entre elles
- [x] 7b.9 Icônes de paiement dessinées, remplaçant les caractères « € » et « ▭ »
- [x] 7b.10 Réduction à 384 px puis WebP : 1,4 Mo → 260 Ko pour neuf produits,
      transparence conservée

### Phase 7 ter — Montant libre ✅

- [x] 7t.1 Tuile « Montant libre » dans la catégorie fourre-tout (`Divers`, ou
      la dernière si aucune ne correspond)
- [x] 7t.2 Pavé qui glisse par-dessus la grille, ticket toujours visible à
      droite pour voir le total bouger pendant la saisie
- [x] 7t.3 Saisie en centimes qui défilent, comme un terminal de paiement :
      3 puis 5 puis 0 donne 3,50 €. Aucune virgule à placer, donc aucune
      confusion possible entre 3,50 et 35,0
- [x] 7t.4 Chaque montant libre est une ligne distincte, jamais fusionnée
- [x] 7t.5 Vérifié de bout en bout : 3,75 € + 2,00 € = 5,75 €, 10 € donnés,
      4,25 € rendus, vente retrouvée dans l'export CSV

### Phase 9 — Kit de déploiement ✅

Écrit et **testé de bout en bout** dans une Debian 12 amd64 vierge (OrbStack,
même architecture que le J1900).

- [x] 9.1 `deploy/installer.sh` — utilisateur dédié sans droits, logiciel dans
      `/opt`, données dans `/var/lib`, idempotent
- [x] 9.2 Deux services séparés : le serveur et l'écran. Chromium peut planter
      sans toucher à la base
- [x] 9.3 Les **deux** piles d'affichage installées — Wayland/cage par défaut,
      X11 en secours, bascule sur place sans téléchargement
- [x] 9.4 Démarrage silencieux : GRUB sans menu, sans journal, sans curseur
- [x] 9.5 Sauvegarde quotidienne par `VACUUM INTO`, caisse allumée, 30 jours
- [x] 9.6 Confinement au SSD : `GRUB_DISABLE_OS_PROBER=true`, rapport des
      disques touchés et non touchés, contrôle de `/etc/fstab`
- [x] 9.7 `make kit` produit le dossier à copier sur clé USB (20 Mo)
- [x] 9.8 `deploy/preseed.cfg` pour une installation Debian sans question
- [x] 9.9 **Vérifié sur machine vierge** : les 4 unités systemd valides, service
      actif, catalogue et images servis, sauvegarde produite, écoute limitée à
      `127.0.0.1`

**Bug trouvé par le test, pas par la relecture** : `StartLimitIntervalSec` était
dans `[Service]` au lieu de `[Unit]`. systemd l'ignorait silencieusement, donc
la limite de cinq redémarrages restait active — au sixième plantage, la
boulangerie se retrouvait sans caisse. C'est exactement ce que la ligne devait
empêcher.

### Phase 8 — Durcissement ⬜

- [ ] 8.1 Sauvegarde automatique de la base (clé USB ou second emplacement)
- [ ] 8.2 Comportement quand le serveur ne répond plus
- [ ] 8.3 `/simplify` puis `/code-review` — une seule fois, ici
- [ ] 8.4 Test de charge grossier : 500 ventes en base, l'interface reste vive

---

## À la boulangerie — nécessite d'être sur place

### Phase 9 — Déploiement ⬜

- [x] 9.1 Relever la résolution réelle de l'écran (`window.innerWidth/Height`)
      → **1360×768 @ 59 Hz**, tactile « HID-compliant touch screen » confirmé,
      Celeron J1900 4 cœurs 2 GHz, 8 Go, Intel HD Graphics (Bay Trail 2013),
      UEFI/GPT, BitLocker désactivé, Ethernet 1 Gbps.
- [ ] 9.2 Photo de l'intérieur du boîtier : format du disque (2,5" SATA ?
      mSATA ? M.2 ? eMMC soudé ?) avant d'acheter le SSD
      → déjà connu côté logique : **SSD SATA 60 Go en GPT** (Recovery + ESP
      100 Mo + MSR + C: 59 Go dont 29,5 Go libres). Reste à voir le format
      physique de visu.
- [ ] 9.3 SSD neuf comme disque Linux ; **le disque Windows sort et va dans un
      tiroir** — le retour arrière est un tournevis
- [ ] 9.4 Debian minimal, démarrage automatique, Chromium en mode kiosk
- [ ] 9.5 Service `systemd` avec `Restart=always`
- [ ] 9.6 Mesure de performance réelle sur le Celeron J1900
- [ ] 9.7 Ajustement des animations si le J1900 peine

### Phase 10 — Mise en service ⬜

- [ ] 10.1 Import du vrai catalogue (CSV du terminal)
- [ ] 10.2 Faire manipuler la caisse par les parents, noter les blocages
- [ ] 10.3 Deux semaines en parallèle de l'ancienne caisse
- [ ] 10.4 Débranchement de l'ancienne caisse — **seulement quand ils le
      demandent eux-mêmes**

---

## Questions ouvertes

1. **Arrondi belge aux 5 centimes sur les espèces** — implémenté et affiché,
   mais à faire confirmer par le comptable avant la mise en service.
   Désactivation : `ARRONDI_CASH_5_CENTIMES = false` dans `web/js/app.js`.
2. **Obligations légales** (journal de caisse, ticket, caisse certifiée) — à
   vérifier avec le comptable **avant** de débrancher l'ancienne caisse. Ne
   bloque pas le développement.
3. **Taille du vrai catalogue** — le nombre de produits par catégorie décidera
   du nombre de colonnes de la grille. Réglage à revoir à l'arrivée du CSV
   plutôt que sur des données fictives.
4. ~~**Résolution de l'écran** — inconnue.~~ Réglée le 01/08 : **1360×768**.
   C'est la largeur qui sert désormais de référence pour la barre d'onglets.

---

## Ce qui manque encore

- **Annuler une vente déjà encaissée.** « Tout effacer » vide le panier *avant*
  paiement ; une fois la vente enregistrée, rien ne permet de revenir dessus.
- **Sauvegarde de la base.** Si le disque lâche, tout l'historique part avec.
- **Produits au poids** — le modèle ne connaît que le prix fixe par article.
  À trancher quand le vrai catalogue arrivera.

## Direction visuelle — arrêtée le 29/07

**Gouache peinte** pour toutes les illustrations de produits : touches de
pinceau visibles, couleurs terreuses, esprit artisanal. Validée par le user
après comparaison des trois styles dans la tuile réelle. À réappliquer telle
quelle quand le vrai catalogue arrivera — `./scripts/generer-images.sh` sans
argument.

**Icônes de catégories : des gouaches**, taillées dans les illustrations de
produits et normalisées. Une seule langue visuelle pour tout l'écran. Les
icônes de **paiement** restent dessinées à la main en SVG, parce qu'elles
doivent virer au blanc sur un fond saturé.

Quatre directions ont été comparées dans la barre d'onglets réelle
(`/essai-icones.html`) : trait généré, gouache, silhouette pleine, aucune
icône. Le trait généré a été écarté — chaque icône générée séparément a sa
propre graisse, l'ensemble fait clipart.

## Journal

- **2026-08-01** — Matériel de la caisse relevé sur place : **1360×768 @ 59 Hz**,
  J1900, 8 Go, UEFI/GPT, SSD SATA 60 Go, tactile confirmé. La grande inconnue du
  projet est levée, et elle expliquait le clipping de la barre d'onglets.
- **2026-08-01** — Vrai catalogue intégré depuis l'ancienne caisse CareSine.
  146 produits bruts → **102 produits en 8 catégories** (Pains, Viennoiseries,
  Boissons chaudes, Boissons froides, Pâtisseries, Sandwichs, Salés, Divers).
  Règle de coupe : moins de 50 ventes sur tout l'historique. Les doublons de
  l'ancienne base ont été fusionnés en cumulant leurs ventes, l'ordre d'affichage
  suit `ventes_total` décroissant. Les suppléments restent à la fin de l'onglet
  Sandwichs, préfixés `+` : on les ajoute pendant la préparation, un onglet à
  part imposait un aller-retour par commande.
- **2026-08-01** — La catégorie « Divers » n'était pas décorative : `renderCats`
  y cherche la catégorie fourre-tout pour y poser la tuile **Montant libre**.
  Sans elle, la tuile atterrissait en dernière ligne de la dernière catégorie,
  invisible. Les anciens boutons « Divers » à 4,50 € et « Divers kg » à 3,00 €
  n'ont pas été repris pour autant : c'est le montant libre qui fait ce travail,
  avec le bon prix.
- **2026-08-01** — Onglets remis dans l'ordre d'une boulangerie — pains,
  viennoiseries, pâtisseries, salés, sandwichs, boissons chaudes, boissons
  froides, divers — au lieu de l'ordre par volume de ventes. Six tiennent à
  l'écran, dont les boissons chaudes : le café reste atteignable sans glisser.
- **2026-08-01** — Les illustrations étaient amputées à droite. La tuile faisait
  déborder l'image de 0,7 rem puis la coupait, pour un effet de photo posée : sur
  les dessins de démonstration, allongés et diagonaux, ça ne se voyait pas ; sur
  le vrai catalogue ça tranchait net tout ce qui est rond — simit, pistolet,
  miche de campagne. L'image tient désormais entièrement dans sa carte.
- **2026-08-01** — Fondu au bord de la barre d'onglets. Avec huit catégories, deux
  sortent du cadre, dont « Divers » qui porte le montant libre — et l'ordre
  logique faisait tomber la découpe pile entre deux onglets, si bien que rien ne
  disait qu'il y avait une suite. Masque statique, jamais animé.
- **2026-08-01** — Catalogue réel entièrement illustré : **102/102 produits** en
  gouache, et un jeu de **huit icônes de catégories** tiré d'une planche 4×2.
  Coût total de la génération : environ 0,95 $.
- **2026-08-01** — Deux défauts trouvés en regardant les images de près, tous
  deux invisibles sur macOS :
  1. Le découpage de la planche emportait une lamelle de la case voisine — un
     bout de baguette collé au croissant. `decouper-planche.py` retire désormais
     les résidus : petit **et** plaqué contre un bord, c'est un voisin ; petit
     et flottant au milieu, c'est la vapeur d'une tasse, on garde.
  2. La réduction à 384 px passait par `sips`, **qui n'existe que sur macOS** :
     sur Linux la ligne était sautée sans bruit et les images sortaient en
     1024×1024, 250 Ko pièce au lieu de 30. Remplacé par `cwebp -resize 384 0`,
     portable et en une seule compression. 4,3 Mo au total au lieu de ~25.
- **2026-08-01** — `generer-images.sh` avait gardé `STYLE="plat"` en défaut,
  celui de la phase de comparaison, alors que `CLAUDE.md` promet la gouache
  « sans argument ». Corrigé avant le lot : sinon, 88 images dans le mauvais
  style, à repayer.
- **2026-08-01** — Deux garde-fous sur les noms d'images, après avoir vu le
  supplément « + Fromage » illustré par un hamburger : le `+` se traduit par
  `supplement-` dans le slug, et la caisse essaie `<catégorie>-<produit>` avant
  le nom nu. Les illustrations de démonstration `fromage.webp` et `jambon.webp`
  ont été retirées, fausses aux deux endroits où elles apparaissaient.
- **2026-08-01** — Barre d'onglets resserrée (padding 1,6 → 1,05 rem, icône
  2,5 → 2,2 rem). Huit onglets ne tiennent pas dans la colonne de gauche en
  1360 px : la barre défile, sur décision du user, plutôt que de passer sur deux
  rangées. C'est le seul écart assumé à « pas de geste caché » ; il est compensé
  en plaçant les catégories les plus tapées à gauche, et l'onglet actif est
  désormais ramené dans le champ au chargement.
- **2026-07-29** — Icônes de catégories reprises : la taille CSS n'était que
  la moitié du problème, le dessin n'occupait que 53 à 76 % de son image selon
  l'icône. D'où `scripts/normaliser-icones.py`, qui recadre sur un seuil
  d'opacité et égalise l'**aire** du dessin plutôt que son plus grand côté.
  Catalogue de démonstration illustré à 57/57 en gouache, 1,7 Mo.
- **2026-07-29** — Montant libre en place. Deux bugs corrigés, même cause : le
  total affiché et la fermeture du pavé dépendaient d'une animation pour
  aboutir. **Rien de ce qui porte un état ne doit dépendre d'une animation.**
- **2026-07-29** — Gouache confirmée comme direction. Quatre icônes reprises sur
  retour du user : cash et Bancontact étaient trop petites et trop détaillées
  (portées à 2,4 rem, blanc franc, deux formes chacune) ; croissant et
  pâtisserie simplifiés, leur feuilletage et leur glaçage ne tenaient pas à
  23 px. Tactile validé sur tablette.
- **2026-07-29** — Illustrations générées (gpt-image-1.5, fond transparent) et
  comparées dans la tuile réelle. Gouache retenue. Icônes IA testées puis
  écartées au profit du tracé vectoriel, pour des raisons de fonction et non de
  goût. Images en WebP : 1,4 Mo → 260 Ko. Vérifié en 1366×768, tuile toujours
  221×123 px, aucun débordement.

- **2026-07-29** — Écran validé par le user sur tablette. Ajouts : images des
  produits en fond de carte sans agrandir les cartes, icônes de catégories,
  billet de 100 €, enchaînement revu de l'encaissement, mise à jour du
  catalogue par dépôt de CSV.
- **2026-07-29** — Trois bugs corrigés à la relecture : un bouton restait
  enfoncé si le doigt glissait hors de la cible avant de se lever ; le fondu de
  sortie de la confirmation clignotait faute de `fill: 'forwards'` ; les tuiles
  n'avaient pas de nom accessible.

- **2026-07-29** — Phases 0 à 3, 5 et 6 terminées. Interface complète et
  fonctionnelle avec le catalogue de démonstration : composition du panier,
  encaissement cash avec rendu de monnaie, encaissement Bancontact,
  enregistrement en base, export CSV. Vérifié en 1366×768, sans débordement.
  Reste : validation sur écran tactile (4.7), édition du catalogue (phase 7).
- **2026-07-29** — Première échelle typographique trop petite en 768p (onglets
  53 px, boutons de paiement 61 px). Base portée de `1.32vh` à `1.75vh` et
  hauteurs minimales revues : onglets 73 px, paiement 90 px, tuiles 221×123 px.
