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

### Phase 4 — Tactile et animations 🟡

- [x] 4.1 Enfoncement déclenché sur `pointerdown` (pas `click`)
- [x] 4.2 Courbe `ease-out` iOS, durées 140–260 ms
- [x] 4.3 Animations interruptibles (la précédente est annulée, jamais empilée)
- [x] 4.4 `transform`/`opacity` uniquement
- [x] 4.5 Anti-zoom, anti-sélection, anti-double-tap, `touch-action`
- [x] 4.6 Total qui défile de l'ancienne à la nouvelle valeur
- [ ] 4.7 **Validé sur un vrai écran tactile** — impossible depuis le Mac.
      À faire avec `make lan` depuis un iPad ou un téléphone.

### Phase 5 — Encaissement ✅

- [x] 5.1 Écran de paiement en surimpression
- [x] 5.2 Cash : propositions de coupures, saisie de ce que donne le client
- [x] 5.3 Calcul et affichage du rendu de monnaie
- [x] 5.4 Bancontact : affichage du montant, encodage manuel sur le terminal
- [x] 5.5 Arrondi belge aux 5 centimes sur les espèces, **affiché explicitement**
      (constante `ARRONDI_CASH_5_CENTIMES` — voir §Questions ouvertes)
- [x] 5.6 Confirmation animée puis retour à zéro
- [x] 5.7 Une vente qui échoue à s'enregistrer conserve le ticket à l'écran
- [x] 5.8 Vérifié de bout en bout : 5,00 € sur 4,40 € dus → 0,60 € rendus,
      vente écrite en base et retrouvée dans l'export CSV

### Phase 6 — Journal des ventes ✅

- [x] 6.1 Tables `sales` / `sale_lines`, nom et prix recopiés pour figer
      l'historique
- [x] 6.2 `POST /api/sales` — le total est recalculé côté serveur
- [x] 6.3 `GET /api/sales/export.csv` — point-virgule, virgule décimale, BOM,
      donc ouvrable directement dans Excel

### Phase 7 — Édition du catalogue ⬜

- [ ] 7.1 Accès caché : appui long dans un coin + code à 4 chiffres
- [ ] 7.2 Créer / renommer / changer le prix / archiver un produit
- [ ] 7.3 Réordonner produits et catégories
- [ ] 7.4 Import CSV depuis l'interface, sans ligne de commande

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

## Journal

- **2026-07-29** — Phases 0 à 3, 5 et 6 terminées. Interface complète et
  fonctionnelle avec le catalogue de démonstration : composition du panier,
  encaissement cash avec rendu de monnaie, encaissement Bancontact,
  enregistrement en base, export CSV. Vérifié en 1366×768, sans débordement.
  Reste : validation sur écran tactile (4.7), édition du catalogue (phase 7).
- **2026-07-29** — Première échelle typographique trop petite en 768p (onglets
  53 px, boutons de paiement 61 px). Base portée de `1.32vh` à `1.75vh` et
  hauteurs minimales revues : onglets 73 px, paiement 90 px, tuiles 221×123 px.
