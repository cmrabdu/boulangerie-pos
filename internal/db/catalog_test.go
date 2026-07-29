package db

import (
	"strings"
	"testing"
)

func TestParsePriceCents(t *testing.T) {
	ok := []struct {
		in   string
		want int
	}{
		{"1,30", 130},
		{"1.30", 130},
		{"1.3", 130}, // une seule décimale vaut des dizaines de centimes
		{"1,5", 150},
		{"2", 200},
		{"0,55", 55},
		{"0,05", 5},
		{"18,00", 1800},
		{"€ 1,30", 130},
		{"1,30 €", 130},
		{"1,30 EUR", 130},
		{"1 250,00", 125000}, // séparateur de milliers par espace
		{"1,309", 130},       // on tronque, on n'arrondit pas
		{",50", 50},
	}
	for _, c := range ok {
		got, err := parsePriceCents(c.in)
		if err != nil {
			t.Errorf("parsePriceCents(%q) : erreur inattendue %v", c.in, err)
			continue
		}
		if got != c.want {
			t.Errorf("parsePriceCents(%q) = %d, attendu %d", c.in, got, c.want)
		}
	}

	bad := []string{"", "gratuit", "-1,50", "abc"}
	for _, in := range bad {
		if _, err := parsePriceCents(in); err == nil {
			t.Errorf("parsePriceCents(%q) : erreur attendue, aucune reçue", in)
		}
	}
}

func TestParseCatalogCSVPointVirgule(t *testing.T) {
	// Le cas réel : export Excel belge, point-virgule et virgule décimale.
	csv := "categorie;produit;prix\n" +
		"Pains;Baguette;1,30\n" +
		"Pains;Pistolet;0,55\n" +
		"Viennoiseries;Croissant;1,30\n"

	cats, err := ParseCatalogCSV(strings.NewReader(csv))
	if err != nil {
		t.Fatalf("erreur inattendue : %v", err)
	}
	if len(cats) != 2 {
		t.Fatalf("%d catégories, 2 attendues", len(cats))
	}
	if cats[0].Name != "Pains" || len(cats[0].Products) != 2 {
		t.Errorf("première catégorie incorrecte : %+v", cats[0])
	}
	if cats[0].Products[0].PriceCents != 130 {
		t.Errorf("Baguette à %d centimes, 130 attendus", cats[0].Products[0].PriceCents)
	}
	// L'ordre des catégories doit suivre le fichier, pas l'ordre d'une map.
	if cats[1].Name != "Viennoiseries" {
		t.Errorf("ordre des catégories non conservé : %q en seconde position", cats[1].Name)
	}
}

func TestParseCatalogCSVVirgule(t *testing.T) {
	csv := "Pains,Baguette,1.30\nPains,Ciabatta,1.80\n"
	cats, err := ParseCatalogCSV(strings.NewReader(csv))
	if err != nil {
		t.Fatalf("erreur inattendue : %v", err)
	}
	if len(cats) != 1 || len(cats[0].Products) != 2 {
		t.Fatalf("résultat inattendu : %+v", cats)
	}
	if cats[0].Products[1].PriceCents != 180 {
		t.Errorf("Ciabatta à %d centimes, 180 attendus", cats[0].Products[1].PriceCents)
	}
}

func TestParseCatalogCSVVide(t *testing.T) {
	if _, err := ParseCatalogCSV(strings.NewReader("")); err == nil {
		t.Error("un CSV vide doit produire une erreur explicite")
	}
}

func TestRecordSaleRecalculeLeTotal(t *testing.T) {
	d := openTestDB(t)

	sale := &Sale{
		CreatedAt:     "2026-07-29T10:00:00Z",
		PaymentMethod: "cash",
		Lines: []SaleLine{
			{Name: "Baguette", UnitPriceCents: 130, Quantity: 2},
			{Name: "Croissant", UnitPriceCents: 130, Quantity: 3},
		},
	}
	if err := d.RecordSale(sale); err != nil {
		t.Fatalf("enregistrement : %v", err)
	}

	// 2×1,30 + 3×1,30 = 6,50 €. Le total vient du serveur, jamais du client.
	if sale.TotalCents != 650 {
		t.Errorf("total = %d centimes, 650 attendus", sale.TotalCents)
	}
	if sale.ID == 0 {
		t.Error("l'identifiant de la vente n'a pas été renseigné")
	}
}

func TestRecordSaleRefuseVenteVide(t *testing.T) {
	d := openTestDB(t)
	err := d.RecordSale(&Sale{CreatedAt: "2026-07-29T10:00:00Z", PaymentMethod: "cash"})
	if err == nil {
		t.Error("une vente sans ligne doit être refusée")
	}
}

func TestCatalogRespecteLOrdre(t *testing.T) {
	d := openTestDB(t)
	if err := d.ReplaceCatalog(DemoCatalog()); err != nil {
		t.Fatalf("chargement du catalogue : %v", err)
	}

	cats, err := d.Catalog()
	if err != nil {
		t.Fatalf("lecture : %v", err)
	}
	if len(cats) != len(DemoCatalog()) {
		t.Fatalf("%d catégories relues, %d attendues", len(cats), len(DemoCatalog()))
	}
	if cats[0].Name != "Pains" || cats[0].Products[0].Name != "Baguette" {
		t.Errorf("ordre non conservé : %q / %q", cats[0].Name, cats[0].Products[0].Name)
	}
}

func TestReplaceCatalogArchiveLAncien(t *testing.T) {
	d := openTestDB(t)
	if err := d.ReplaceCatalog(DemoCatalog()); err != nil {
		t.Fatal(err)
	}
	if err := d.ReplaceCatalog([]Category{
		{Name: "Pains", Products: []Product{{Name: "Baguette", PriceCents: 140}}},
	}); err != nil {
		t.Fatal(err)
	}

	cats, err := d.Catalog()
	if err != nil {
		t.Fatal(err)
	}
	if len(cats) != 1 || len(cats[0].Products) != 1 {
		t.Fatalf("le catalogue actif doit être remplacé, obtenu : %+v", cats)
	}

	// Les anciennes lignes sont archivées, pas supprimées : l'historique des
	// ventes doit rester exploitable.
	var n int
	if err := d.QueryRow(`SELECT COUNT(*) FROM products WHERE archived = 1`).Scan(&n); err != nil {
		t.Fatal(err)
	}
	if n == 0 {
		t.Error("les anciens produits devraient être archivés, pas supprimés")
	}
}

func openTestDB(t *testing.T) *DB {
	t.Helper()
	d, err := Open(t.TempDir() + "/test.db")
	if err != nil {
		t.Fatalf("ouverture de la base : %v", err)
	}
	t.Cleanup(func() { d.Close() })
	return d
}
