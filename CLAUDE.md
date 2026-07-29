# Conventions du projet

Caisse tactile pour une boulangerie belge. Remplace une caisse enregistreuse
générique des années 2000 utilisée uniquement comme grosse calculatrice.

## Au démarrage d'une session

1. Lire `PLAN.md` et reprendre à la première case non cochée.
2. À la fin de chaque étape : cocher la case **et** ajouter une ligne au journal.
3. **Ne jamais cocher une case sans avoir vu la chose fonctionner.** Un test
   unitaire vert ne suffit pas à cocher une case d'interface.

## Matériel cible

Celeron J1900 (2013, 4 cœurs, GPU faible), 8 Go, écran tactile ~24",
résolution inconnue — probablement 1366×768, peut-être 1920×1080.
Aucun clavier ni souris : **tout doit être atteignable au doigt**.

## Règles non négociables

- **Montants en centimes, entiers, partout.** Aucun prix ne passe par un
  flottant. `0.1 + 0.2 !== 0.3` : une caisse ne peut pas se le permettre.
- **Le total d'une vente est recalculé côté serveur.** Le client ne l'envoie
  jamais.
- **On n'anime que `transform` et `opacity`.** Le GPU de la cible date de 2013.
  Pas d'animation de couleur, d'ombre, de taille ou de flou.
- **Le retour au doigt part de `pointerdown`, pas de `click`.** Ce qui répond
  au doigt est instantané ; ce qui bouge ensuite est animé (140–260 ms).
- **Les animations sont interruptibles**, jamais empilées.
- **Tout est en `rem`, et `rem` suit la hauteur d'écran** (`clamp` sur `vh`).
  Aucune dimension en pixels fixes, aucune média-query de résolution.
- **Pas de geste caché pour une action courante.** Les boutons `−`/`+` sont
  visibles ; on ne demande pas à quelqu'un de découvrir un swipe.
- **Une action destructrice se confirme.** « Tout effacer » s'arme d'abord.
- **Une vente qui échoue à s'enregistrer n'efface jamais le ticket.**
- **Aucun écran de réglages, aucun bouton « paramètres ».** Le catalogue se met
  à jour en déposant un CSV par SSH. Tout ce qui ne sert pas à encaisser n'a
  rien à faire devant quelqu'un qui sert des clients.
- **Une image manquante n'est jamais un trou.** Un produit sans illustration
  s'affiche exactement comme si la fonctionnalité n'existait pas.
- **Jamais de clé d'API dans le dépôt ni dans le code.** Les scripts la lisent
  depuis l'environnement.

## Simplicité

Pas de framework front, pas d'étape de build, pas de `node_modules`.
Du HTML/CSS/JS lu directement par Chromium, embarqué dans le binaire Go.
Ce projet doit rester réparable dans deux ans par quelqu'un qui l'a oublié.

## Commandes

```
make dev      # développement, front lu depuis le disque
make lan      # idem, joignable depuis un iPad/téléphone du réseau
make test     # tests unitaires
make fmt      # gofmt + go vet
make linux    # LE binaire à copier sur la caisse (croisé, sans cgo)
```

## Structure

```
main.go              serveur, go:embed, drapeaux
internal/db/         schéma, catalogue, ventes, import CSV
internal/api/        points d'entrée JSON et export CSV
web/                 index.html, css/app.css, js/app.js
```

## Langue

Code, commentaires, documentation et interface en français.
Les commentaires expliquent **pourquoi**, pas **quoi**.

## Git

Commits en français, à l'identité du dépôt. **Ne pas ajouter de co-auteur.**
