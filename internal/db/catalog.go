package db

import (
	"encoding/csv"
	"fmt"
	"io"
	"strconv"
	"strings"
)

// ReplaceCatalog remplace intégralement le catalogue, dans une transaction.
//
// Les anciennes lignes sont archivées plutôt que supprimées : les ventes déjà
// enregistrées gardent ainsi une référence valide, et un import raté n'efface
// jamais d'historique.
func (d *DB) ReplaceCatalog(cats []Category) error {
	tx, err := d.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	if _, err := tx.Exec(`UPDATE categories SET archived = 1`); err != nil {
		return err
	}
	if _, err := tx.Exec(`UPDATE products SET archived = 1`); err != nil {
		return err
	}

	for ci, c := range cats {
		res, err := tx.Exec(
			`INSERT INTO categories (name, color, position, archived) VALUES (?, ?, ?, 0)`,
			c.Name, c.Color, ci)
		if err != nil {
			return err
		}
		catID, err := res.LastInsertId()
		if err != nil {
			return err
		}
		for pi, p := range c.Products {
			if _, err := tx.Exec(
				`INSERT INTO products (category_id, name, price_cents, position, archived)
				 VALUES (?, ?, ?, ?, 0)`,
				catID, p.Name, p.PriceCents, pi); err != nil {
				return err
			}
		}
	}
	return tx.Commit()
}

// ParseCatalogCSV lit un catalogue au format « catégorie, produit, prix ».
//
// Le séparateur est détecté automatiquement (`;` ou `,`) car les exports belges
// depuis Excel utilisent le point-virgule — ce qui est heureux, puisque les prix
// y sont écrits avec une virgule décimale (« 1,30 »).
// Une éventuelle ligne d'en-tête est ignorée.
func ParseCatalogCSV(r io.Reader) ([]Category, error) {
	raw, err := io.ReadAll(r)
	if err != nil {
		return nil, err
	}
	text := strings.TrimPrefix(string(raw), "\uFEFF") // BOM des exports Excel

	sep := ','
	if firstLine, _, _ := strings.Cut(text, "\n"); strings.Contains(firstLine, ";") {
		sep = ';'
	}

	cr := csv.NewReader(strings.NewReader(text))
	cr.Comma = sep
	cr.FieldsPerRecord = -1 // tolère les colonnes surnuméraires
	cr.TrimLeadingSpace = true

	records, err := cr.ReadAll()
	if err != nil {
		return nil, fmt.Errorf("lecture du CSV : %w", err)
	}

	var cats []Category
	byName := map[string]int{}

	for i, rec := range records {
		if len(rec) < 3 {
			continue
		}
		catName := strings.TrimSpace(rec[0])
		prodName := strings.TrimSpace(rec[1])
		priceRaw := strings.TrimSpace(rec[2])
		if catName == "" || prodName == "" {
			continue
		}

		cents, err := parsePriceCents(priceRaw)
		if err != nil {
			// La première ligne illisible est presque toujours l'en-tête.
			if i == 0 {
				continue
			}
			return nil, fmt.Errorf("ligne %d : prix illisible %q", i+1, priceRaw)
		}

		idx, ok := byName[catName]
		if !ok {
			idx = len(cats)
			byName[catName] = idx
			cats = append(cats, Category{Name: catName, Products: []Product{}})
		}
		cats[idx].Products = append(cats[idx].Products, Product{
			Name:       prodName,
			PriceCents: cents,
		})
	}

	if len(cats) == 0 {
		return nil, fmt.Errorf("aucun produit trouvé — format attendu : catégorie%cproduit%cprix", sep, sep)
	}
	return cats, nil
}

// parsePriceCents convertit « 1,30 », « 1.30 », « 1.3 », « 2 » ou « € 1,30 » en
// centimes. On passe par une chaîne plutôt que par un float64 pour éviter toute
// erreur d'arrondi.
func parsePriceCents(s string) (int, error) {
	s = strings.TrimSpace(strings.NewReplacer(
		"€", "", "EUR", "",
		" ", "", // espace ordinaire
		" ", "", // espace insécable, courante dans les exports Excel
		" ", "", // espace fine insécable
	).Replace(s))
	s = strings.Replace(s, ",", ".", 1)
	if s == "" {
		return 0, fmt.Errorf("prix vide")
	}

	whole, frac, hasFrac := strings.Cut(s, ".")
	if whole == "" {
		whole = "0"
	}
	euros, err := strconv.Atoi(whole)
	if err != nil || euros < 0 {
		return 0, fmt.Errorf("prix invalide")
	}

	cents := 0
	if hasFrac {
		switch len(frac) {
		case 0:
		case 1:
			frac += "0" // « 1.5 » vaut 1,50 €
			fallthrough
		default:
			if len(frac) > 2 {
				frac = frac[:2] // on tronque, on n'arrondit pas
			}
			cents, err = strconv.Atoi(frac)
			if err != nil {
				return 0, fmt.Errorf("centimes invalides")
			}
		}
	}
	return euros*100 + cents, nil
}

// DemoCatalog est le catalogue de démonstration chargé au tout premier
// lancement, quand la base est vide. Prix indicatifs de boulangerie belge : ils
// servent à voir l'interface avec des données crédibles, pas à être exacts.
func DemoCatalog() []Category {
	type p struct {
		name  string
		cents int
	}
	build := func(name, color string, items []p) Category {
		c := Category{Name: name, Color: color, Products: make([]Product, 0, len(items))}
		for _, it := range items {
			c.Products = append(c.Products, Product{Name: it.name, PriceCents: it.cents})
		}
		return c
	}

	return []Category{
		build("Pains", "wheat", []p{
			{"Baguette", 130}, {"Pistolet", 55}, {"Sandwich", 60},
			{"Pain gris 500g", 260}, {"Pain blanc 500g", 250}, {"Pain complet", 280},
			{"Pain multicéréales", 310}, {"Pain aux noix", 340}, {"Ciabatta", 180},
			{"Baguette tradition", 175}, {"Pain d'épeautre", 330}, {"Demi-gris", 145},
		}),
		build("Viennoiseries", "butter", []p{
			{"Croissant", 130}, {"Couque au beurre", 140}, {"Couque au chocolat", 150},
			{"Couque suisse", 180}, {"Pain aux raisins", 160}, {"Chausson aux pommes", 190},
			{"Croissant amandes", 200}, {"Donut", 180}, {"Cramique", 320},
			{"Craquelin", 320},
		}),
		build("Pâtisseries", "berry", []p{
			{"Éclair chocolat", 280}, {"Éclair vanille", 280}, {"Merveilleux", 320},
			{"Tarte au riz (part)", 260}, {"Tarte aux pommes (part)", 290},
			{"Tarte au sucre (part)", 250}, {"Millefeuille", 330}, {"Tiramisu", 350},
			{"Moelleux chocolat", 300}, {"Gâteau 6 pers.", 1800}, {"Gâteau 8 pers.", 2400},
		}),
		build("Sandwichs", "herb", []p{
			{"Fromage", 350}, {"Jambon", 350}, {"Jambon-fromage", 400},
			{"Thon", 420}, {"Poulet curry", 450}, {"Américain", 450},
			{"Crabe", 420}, {"Club sandwich", 520}, {"Panini", 480},
		}),
		build("Boissons", "water", []p{
			{"Eau 50cl", 120}, {"Eau pétillante 50cl", 130}, {"Coca 33cl", 180},
			{"Ice tea 33cl", 180}, {"Jus d'orange", 220}, {"Café", 150},
			{"Cappuccino", 220}, {"Chocolat chaud", 200}, {"Thé", 150},
		}),
		build("Divers", "stone", []p{
			{"Sac", 10}, {"Grand sac", 25}, {"Bougies", 100},
			{"Œufs (6)", 280}, {"Chocolats 250g", 750}, {"Confiture", 480},
		}),
	}
}
