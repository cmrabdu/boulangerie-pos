package db

import "testing"

func TestSlugify(t *testing.T) {
	cas := map[string]string{
		"Éclair chocolat":     "eclair-chocolat",
		"Tarte au riz (part)": "tarte-au-riz-part",
		"Œufs (6)":            "oeufs-6",
		"Mitraillettes ×5":    "mitraillettes-5",
		// Un supplément et le produit du même nom ne doivent jamais tomber sur
		// le même fichier d'image : c'est tout l'intérêt du « + ».
		"+ Fromage": "supplement-fromage",
		"Fromage":   "fromage",
	}
	for nom, attendu := range cas {
		if got := Slugify(nom); got != attendu {
			t.Errorf("Slugify(%q) = %q, attendu %q", nom, got, attendu)
		}
	}
}
