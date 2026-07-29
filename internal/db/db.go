// Package db gère la base SQLite locale : schéma, catalogue et journal des ventes.
//
// Tous les montants sont stockés en centimes (entiers). Aucun flottant n'entre
// jamais dans un calcul de prix : 0.1 + 0.2 != 0.3 en virgule flottante, et une
// caisse qui se trompe d'un centime est une caisse cassée.
package db

import (
	"database/sql"
	"fmt"

	_ "modernc.org/sqlite"
)

type DB struct {
	*sql.DB
}

// Category est un onglet de l'écran principal.
type Category struct {
	ID       int64     `json:"id"`
	Name     string    `json:"name"`
	Color    string    `json:"color"`
	Position int       `json:"position"`
	Products []Product `json:"products"`
}

// Product est une tuile de la grille.
type Product struct {
	ID         int64  `json:"id"`
	CategoryID int64  `json:"categoryId"`
	Name       string `json:"name"`
	PriceCents int    `json:"priceCents"`
	Position   int    `json:"position"`

	// Slug est le nom de fichier attendu pour l'image du produit :
	// « Éclair chocolat » → « eclair-chocolat ». Calculé, jamais stocké.
	Slug string `json:"slug"`
	// Image est l'URL de l'illustration si un fichier correspondant existe sur
	// le disque, sinon vide. Renseignée par la couche API, qui seule connaît le
	// dossier d'images.
	Image string `json:"image"`
}

// SaleLine est une ligne du ticket au moment de la vente. Le nom et le prix
// sont recopiés (et non référencés) pour que le journal reste exact même si le
// produit est renommé ou son prix changé plus tard.
type SaleLine struct {
	ProductID      int64  `json:"productId"`
	Name           string `json:"name"`
	UnitPriceCents int    `json:"unitPriceCents"`
	Quantity       int    `json:"quantity"`
}

// Sale est une vente clôturée.
type Sale struct {
	ID            int64      `json:"id"`
	CreatedAt     string     `json:"createdAt"`
	TotalCents    int        `json:"totalCents"`
	PaymentMethod string     `json:"paymentMethod"` // "cash" ou "card"
	GivenCents    *int       `json:"givenCents"`    // nul si non saisi
	ChangeCents   *int       `json:"changeCents"`   // nul si non saisi
	Lines         []SaleLine `json:"lines"`
}

const schema = `
CREATE TABLE IF NOT EXISTS categories (
	id       INTEGER PRIMARY KEY AUTOINCREMENT,
	name     TEXT    NOT NULL,
	color    TEXT    NOT NULL DEFAULT '',
	position INTEGER NOT NULL DEFAULT 0,
	archived INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS products (
	id          INTEGER PRIMARY KEY AUTOINCREMENT,
	category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
	name        TEXT    NOT NULL,
	price_cents INTEGER NOT NULL CHECK (price_cents >= 0),
	position    INTEGER NOT NULL DEFAULT 0,
	archived    INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS sales (
	id             INTEGER PRIMARY KEY AUTOINCREMENT,
	created_at     TEXT    NOT NULL,
	total_cents    INTEGER NOT NULL,
	payment_method TEXT    NOT NULL CHECK (payment_method IN ('cash','card')),
	given_cents    INTEGER,
	change_cents   INTEGER
);

CREATE TABLE IF NOT EXISTS sale_lines (
	id               INTEGER PRIMARY KEY AUTOINCREMENT,
	sale_id          INTEGER NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
	product_id       INTEGER,
	name             TEXT    NOT NULL,
	unit_price_cents INTEGER NOT NULL,
	quantity         INTEGER NOT NULL CHECK (quantity > 0)
);

CREATE INDEX IF NOT EXISTS idx_products_category ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_sale_lines_sale   ON sale_lines(sale_id);
CREATE INDEX IF NOT EXISTS idx_sales_created     ON sales(created_at);
`

// Open ouvre la base et applique le schéma.
//
// WAL + synchronous=NORMAL : sur le disque lent de la caisse, le mode journal
// par défaut ferait attendre l'interface à chaque vente. WAL rend l'écriture
// non bloquante pour les lectures, et NORMAL évite un fsync par transaction
// sans risque de corruption (au pire, la toute dernière vente est perdue en cas
// de coupure de courant franche).
func Open(path string) (*DB, error) {
	sqlDB, err := sql.Open("sqlite", path+"?_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)&_pragma=synchronous(NORMAL)&_pragma=foreign_keys(ON)")
	if err != nil {
		return nil, fmt.Errorf("ouverture de la base : %w", err)
	}
	// Un seul écrivain : SQLite ne gère pas les écritures concurrentes, et une
	// caisse n'a de toute façon qu'un seul utilisateur.
	sqlDB.SetMaxOpenConns(1)

	if _, err := sqlDB.Exec(schema); err != nil {
		sqlDB.Close()
		return nil, fmt.Errorf("création du schéma : %w", err)
	}
	return &DB{sqlDB}, nil
}

// Catalog renvoie les catégories actives, chacune avec ses produits actifs,
// dans l'ordre d'affichage.
func (d *DB) Catalog() ([]Category, error) {
	rows, err := d.Query(`
		SELECT id, name, color, position
		FROM categories WHERE archived = 0
		ORDER BY position, id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var cats []Category
	byID := map[int64]int{} // id de catégorie -> index dans cats
	for rows.Next() {
		var c Category
		if err := rows.Scan(&c.ID, &c.Name, &c.Color, &c.Position); err != nil {
			return nil, err
		}
		c.Products = []Product{}
		byID[c.ID] = len(cats)
		cats = append(cats, c)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	prodRows, err := d.Query(`
		SELECT id, category_id, name, price_cents, position
		FROM products WHERE archived = 0
		ORDER BY position, id`)
	if err != nil {
		return nil, err
	}
	defer prodRows.Close()

	for prodRows.Next() {
		var p Product
		if err := prodRows.Scan(&p.ID, &p.CategoryID, &p.Name, &p.PriceCents, &p.Position); err != nil {
			return nil, err
		}
		p.Slug = Slugify(p.Name)
		if idx, ok := byID[p.CategoryID]; ok {
			cats[idx].Products = append(cats[idx].Products, p)
		}
	}
	return cats, prodRows.Err()
}

// RecordSale écrit une vente et ses lignes dans une seule transaction, puis
// renseigne s.ID. Le total est recalculé côté serveur à partir des lignes : on
// ne fait jamais confiance à un total envoyé par le client.
func (d *DB) RecordSale(s *Sale) error {
	if len(s.Lines) == 0 {
		return fmt.Errorf("vente sans ligne")
	}
	total := 0
	for _, l := range s.Lines {
		if l.Quantity <= 0 {
			return fmt.Errorf("quantité invalide pour %q", l.Name)
		}
		total += l.UnitPriceCents * l.Quantity
	}
	s.TotalCents = total

	tx, err := d.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback() // sans effet si le Commit a réussi

	res, err := tx.Exec(
		`INSERT INTO sales (created_at, total_cents, payment_method, given_cents, change_cents)
		 VALUES (?, ?, ?, ?, ?)`,
		s.CreatedAt, s.TotalCents, s.PaymentMethod, s.GivenCents, s.ChangeCents)
	if err != nil {
		return err
	}
	s.ID, err = res.LastInsertId()
	if err != nil {
		return err
	}

	stmt, err := tx.Prepare(
		`INSERT INTO sale_lines (sale_id, product_id, name, unit_price_cents, quantity)
		 VALUES (?, ?, ?, ?, ?)`)
	if err != nil {
		return err
	}
	defer stmt.Close()

	for _, l := range s.Lines {
		if _, err := stmt.Exec(s.ID, l.ProductID, l.Name, l.UnitPriceCents, l.Quantity); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// SalesBetween renvoie les ventes dont created_at est dans [from, to], bornes
// comprises, au format ISO 8601. Utilisé par l'export CSV.
func (d *DB) SalesBetween(from, to string) ([]Sale, error) {
	rows, err := d.Query(`
		SELECT id, created_at, total_cents, payment_method, given_cents, change_cents
		FROM sales
		WHERE created_at >= ? AND created_at <= ?
		ORDER BY created_at, id`, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var sales []Sale
	for rows.Next() {
		var s Sale
		if err := rows.Scan(&s.ID, &s.CreatedAt, &s.TotalCents, &s.PaymentMethod, &s.GivenCents, &s.ChangeCents); err != nil {
			return nil, err
		}
		sales = append(sales, s)
	}
	return sales, rows.Err()
}

// IsEmpty indique si le catalogue n'a jamais été rempli, ce qui déclenche le
// chargement du catalogue de démonstration au premier lancement.
func (d *DB) IsEmpty() (bool, error) {
	var n int
	err := d.QueryRow(`SELECT COUNT(*) FROM categories`).Scan(&n)
	return n == 0, err
}
