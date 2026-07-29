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

### Phase 8 — Durcissement ⬜

- [ ] 8.1 Sauvegarde automatique de la base (clé USB ou second emplacement)
- [ ] 8.2 Comportement quand le serveur ne répond plus
- [ ] 8.3 `/simplify` puis `/code-review` — une seule fois, ici
- [ ] 8.4 Test de charge grossier : 500 ventes en base, l'interface reste vive

---

## À la boulangerie — nécessite d'être sur place

### Phase 9 — Déploiement ⬜

- [ ] 9.1 Relever la résolution réelle de l'écran (`window.innerWidth/Height`)
- [ ] 9.2 Photo de l'intérieur du boîtier : format du disque (2,5" SATA ?
      mSATA ? M.2 ? eMMC soudé ?) avant d'acheter le SSD
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
4. **Résolution de l'écran** — inconnue. L'interface s'adapte, mais la
   vérifier reste utile.

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

**Icônes dessinées au trait**, jamais générées, et réduites à deux formes
maximum. Elles sont vues à un mètre, du coin de l'œil.

## Journal

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
