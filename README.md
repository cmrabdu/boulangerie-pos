# Caisse boulangerie

Une caisse tactile pour boulangerie, tenant dans **un seul binaire**.

Elle fait une seule chose : composer un panier vite, afficher un total lisible
de loin, encaisser, repartir à zéro. Pas de stock, pas de comptabilité, pas de
fidélité. Le critère de réussite est qu'une baguette et deux croissants
s'encaissent en moins de quatre secondes, sans avoir à lire l'écran.

Elle remplace une caisse enregistreuse générique des années 2000 qui ne servait
que de grosse calculatrice, sur un PC tactile à Celeron J1900.

## Ce qu'elle fait

- Catégories en onglets, produits en grandes tuiles
- Ticket en direct avec quantités ajustables
- Total permanent, en gros, toujours au même endroit
- Encaissement **espèces** avec propositions de coupures et **calcul du rendu**
- Encaissement **Bancontact** (le montant est encodé sur le terminal)
- Arrondi belge aux 5 centimes sur les espèces, toujours affiché explicitement
- Journal des ventes en SQLite, exportable en CSV ouvrable dans Excel
- Illustrations des produits et icônes de catégories, sans agrandir les cartes
- Catalogue mis à jour en déposant un fichier CSV : ni bouton, ni redémarrage

## Démarrage

```bash
make dev
```

Puis ouvrir <http://localhost:8099>. Au premier lancement, un catalogue de
démonstration est chargé pour que l'écran ne soit jamais vide.

Pour essayer le vrai tactile depuis un iPad ou un téléphone du même réseau :

```bash
make lan
```

## Importer un catalogue

Format attendu — séparateur `;` ou `,`, détecté automatiquement :

```csv
categorie;produit;prix
Pains;Baguette;1,30
Pains;Pistolet;0,55
Viennoiseries;Croissant;1,30
```

Les prix acceptent `1,30`, `1.30`, `1.3`, `€ 1,30`, les espaces insécables et
le BOM des exports Excel. L'ancien catalogue est **archivé**, pas supprimé :
les ventes déjà enregistrées gardent une référence valide.

### Mise à jour depuis un autre poste

La caisse **surveille** le fichier `catalogue.csv` posé à côté d'elle. Il suffit
de le déposer, par SSH depuis n'importe quelle machine :

```bash
scp catalogue.csv caisse:/opt/caisse/catalogue.csv
```

Le catalogue est réimporté en quelques secondes et l'écran se met à jour tout
seul — sans redémarrage, sans rechargement de page, et **sans bouton
« paramètres » à l'écran**. C'est délibéré : tout ce qui ne sert pas à encaisser
n'a rien à faire devant quelqu'un qui sert des clients.

Le rafraîchissement n'a jamais lieu au milieu d'une vente : il attend que le
panier soit vide et qu'aucun écran de paiement ne soit ouvert. Un CSV mal formé
est refusé, et l'ancien catalogue reste en place.

Import ponctuel en ligne de commande, si besoin :

```bash
./dist/boulangerie-pos -import catalogue.csv
```

## Images des produits

Chaque produit cherche une image nommée d'après son nom, sans accents :

| Produit | Fichier attendu |
|---|---|
| Baguette | `img/products/baguette.png` |
| Éclair chocolat | `img/products/eclair-chocolat.png` |
| Pain gris 500g | `img/products/pain-gris-500g.png` |

Extensions acceptées, par ordre de préférence : `.png`, `.webp`, `.jpg`,
`.svg`. **Un produit sans image s'affiche normalement**, sans trou ni cadre
vide — rien n'oblige à toutes les fournir.

L'image se loge dans la carte existante, qui ne grandit pas : elle occupe la
moitié droite en débordant légèrement, pendant qu'un dégradé de la couleur de
la carte passe au-dessus côté texte. Le nom et le prix restent donc lisibles
quelle que soit l'image.

Le dépôt contient quelques illustrations SVG de démonstration. Pour générer des
images à la place, avec votre propre clé OpenAI :

```bash
mkdir -p ~/.config/boulangerie-pos
chmod 700 ~/.config/boulangerie-pos
printf 'export OPENAI_API_KEY=%s\n' 'votre-clé' > ~/.config/boulangerie-pos/openai.env
chmod 600 ~/.config/boulangerie-pos/openai.env
```

```bash
source ~/.config/boulangerie-pos/openai.env && ./scripts/generer-images.sh
```

La clé reste dans votre environnement : le script la lit, ne l'affiche jamais et
ne l'écrit nulle part. Le fichier vit **hors du dépôt**, qui est public.

## Déployer sur la caisse

```bash
make linux
```

Produit `dist/boulangerie-pos-linux-amd64` : un fichier, à copier sur la
machine. Aucun runtime à installer, aucune dépendance — SQLite est compilé en
Go pur, donc la compilation croisée depuis un Mac ARM ne demande rien de plus.

Sur la caisse, l'exécutable tourne en service `systemd` et Chromium l'affiche
en mode kiosk au démarrage. Sauvegarder, c'est copier `caisse.db`.

## Choix techniques

| Décision | Raison |
|---|---|
| Un binaire Go, front embarqué | Rien à installer sur la machine des parents, rien à maintenir dans deux ans |
| `modernc.org/sqlite` (Go pur) | Compilation croisée Mac → Linux sans cgo ni compilateur C |
| Pas de framework, pas de build | Le plus rapide possible sur un GPU de 2013, et réparable longtemps |
| Montants en centimes entiers | Une caisse qui se trompe d'un centime est une caisse cassée |
| Total recalculé côté serveur | Le client n'est pas une source de vérité |
| `rem` indexé sur la hauteur d'écran | Une seule interface pour 1366×768 et 1920×1080 |
| `transform`/`opacity` uniquement | Les seules propriétés que le Celeron compose sans recalculer la mise en page |

## Animations

Le but n'est pas de décorer : **une animation masque la latence**. Sans elle,
l'écran saute et l'œil doit re-localiser ce qui a changé — c'est ça qui coûte
du temps, pas les 200 ms.

- L'enfoncement d'une tuile part de `pointerdown` : visible avant même que le
  doigt se relève
- Durées 140–260 ms, courbe `ease-out` prononcée
- Toutes interruptibles : trois produits tapés en une seconde donnent trois
  réactions immédiates, pas une file d'attente
- `prefers-reduced-motion` est respecté

## Sécurité

Le serveur écoute sur `127.0.0.1` par défaut et n'a **aucune authentification** :
il n'est pas prévu pour être exposé à un réseau. Le drapeau `-lan` n'existe que
pour tester depuis un appareil du réseau local pendant le développement.

## État

Voir [PLAN.md](PLAN.md). L'application est fonctionnelle de bout en bout ;
restent l'édition du catalogue depuis l'interface, la validation sur un vrai
écran tactile, et le déploiement sur la machine cible.

## Licence

MIT
