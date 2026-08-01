// Package api expose le catalogue et le journal des ventes en JSON.
//
// Le serveur n'écoute que sur la boucle locale : il n'y a pas d'authentification
// parce qu'il n'y a pas de réseau. Voir README.md, section « Sécurité ».
package api

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync/atomic"
	"time"

	"github.com/cmrabdu/boulangerie-pos/internal/db"
)

type Server struct {
	DB *db.DB
	// ImgDir est le dossier d'illustrations, sur le disque et non embarqué :
	// ajouter une image à la caisse doit se résumer à y déposer un fichier,
	// sans recompiler quoi que ce soit.
	ImgDir string

	// generation change à chaque réimport du catalogue. Le front l'interroge
	// pour se rafraîchir tout seul après un dépôt de CSV par SSH.
	generation atomic.Int64
}

// BumpGeneration signale que le catalogue a changé.
func (s *Server) BumpGeneration() { s.generation.Add(1) }

// Routes enregistre les points d'entrée de l'API sur un mux.
func (s *Server) Routes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/catalog", s.getCatalog)
	mux.HandleFunc("GET /api/catalog/version", s.getCatalogVersion)
	mux.HandleFunc("POST /api/sales", s.postSale)
	mux.HandleFunc("GET /api/sales/export.csv", s.exportSales)
}

// extensionsImage est l'ordre de préférence quand plusieurs fichiers portent le
// même slug. Le PNG passe en premier : c'est ce que produit le script de
// génération. Le SVG ferme la marche, si bien qu'une vraie image déposée par la
// boulangerie remplace d'elle-même l'illustration de démonstration.
var extensionsImage = []string{".png", ".webp", ".jpg", ".jpeg", ".svg"}

// imagesDisponibles indexe le dossier d'illustrations par slug.
//
// Le dossier est relu à chaque appel du catalogue plutôt que mis en cache :
// il contient quelques dizaines de fichiers, l'appel est rare, et cela évite
// d'avoir à redémarrer la caisse après avoir copié une image.
func (s *Server) imagesDisponibles() map[string]string {
	found := map[string]string{}
	if s.ImgDir == "" {
		return found
	}
	entries, err := os.ReadDir(filepath.Join(s.ImgDir, "products"))
	if err != nil {
		return found // dossier absent : aucune image, ce n'est pas une erreur
	}
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		name := e.Name()
		ext := strings.ToLower(filepath.Ext(name))
		slug := strings.TrimSuffix(name, filepath.Ext(name))

		rank := slices.Index(extensionsImage, ext)
		if rank < 0 {
			continue
		}
		// À slug égal, on garde l'extension la mieux classée.
		if prev, ok := found[slug]; ok {
			if slices.Index(extensionsImage, strings.ToLower(filepath.Ext(prev))) <= rank {
				continue
			}
		}
		found[slug] = name
	}
	return found
}

func (s *Server) getCatalogVersion(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]int64{"version": s.generation.Load()})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("écriture JSON : %v", err)
	}
}

func writeErr(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func (s *Server) getCatalog(w http.ResponseWriter, r *http.Request) {
	cats, err := s.DB.Catalog()
	if err != nil {
		log.Printf("lecture du catalogue : %v", err)
		writeErr(w, http.StatusInternalServerError, "catalogue illisible")
		return
	}
	if cats == nil {
		cats = []db.Category{}
	}

	// Un même mot ne désigne pas la même chose selon l'onglet : « Fromage » est
	// un sandwich chez les sandwichs et une tranche chez les suppléments, et les
	// deux tomberaient sur « fromage.webp ». On cherche donc d'abord un fichier
	// préfixé par la catégorie, et on retombe sur le slug nu — ce qui laisse
	// intactes toutes les images déjà déposées.
	images := s.imagesDisponibles()
	for ci := range cats {
		prefixe := db.Slugify(cats[ci].Name) + "-"
		for pi := range cats[ci].Products {
			slug := cats[ci].Products[pi].Slug
			file, ok := images[prefixe+slug]
			if !ok {
				file, ok = images[slug]
			}
			if ok {
				cats[ci].Products[pi].Image = "/img/products/" + file
			}
		}
	}

	writeJSON(w, http.StatusOK, cats)
}

// saleRequest est ce que le client envoie. Le total en est volontairement
// absent : il est recalculé côté serveur à partir des lignes.
type saleRequest struct {
	PaymentMethod string        `json:"paymentMethod"`
	GivenCents    *int          `json:"givenCents"`
	Lines         []db.SaleLine `json:"lines"`
}

func (s *Server) postSale(w http.ResponseWriter, r *http.Request) {
	var req saleRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, "requête illisible")
		return
	}
	if req.PaymentMethod != "cash" && req.PaymentMethod != "card" {
		writeErr(w, http.StatusBadRequest, "mode de paiement inconnu")
		return
	}
	if len(req.Lines) == 0 {
		writeErr(w, http.StatusBadRequest, "vente vide")
		return
	}

	sale := &db.Sale{
		// L'horodatage vient du serveur : l'heure du navigateur n'engage
		// personne, et le journal doit rester cohérent.
		CreatedAt:     time.Now().Format(time.RFC3339),
		PaymentMethod: req.PaymentMethod,
		GivenCents:    req.GivenCents,
		Lines:         req.Lines,
	}

	if err := s.DB.RecordSale(sale); err != nil {
		log.Printf("enregistrement de la vente : %v", err)
		writeErr(w, http.StatusInternalServerError, "vente non enregistrée")
		return
	}

	// Le rendu de monnaie n'est calculé qu'une fois le total connu, et
	// seulement s'il est cohérent (le client peut donner moins que le total
	// quand la caissière tape juste « payé »).
	if sale.GivenCents != nil && *sale.GivenCents >= sale.TotalCents {
		change := *sale.GivenCents - sale.TotalCents
		sale.ChangeCents = &change
		if _, err := s.DB.Exec(`UPDATE sales SET change_cents = ? WHERE id = ?`, change, sale.ID); err != nil {
			log.Printf("mise à jour du rendu : %v", err)
		}
	}

	writeJSON(w, http.StatusCreated, sale)
}

// exportSales renvoie le journal des ventes en CSV, séparateur point-virgule et
// virgule décimale : c'est ce qu'Excel en version belge ouvre sans rien demander.
func (s *Server) exportSales(w http.ResponseWriter, r *http.Request) {
	from := r.URL.Query().Get("from")
	to := r.URL.Query().Get("to")
	if from == "" {
		from = "0000"
	}
	if to == "" {
		to = "9999"
	}

	sales, err := s.DB.SalesBetween(from, to)
	if err != nil {
		log.Printf("export des ventes : %v", err)
		writeErr(w, http.StatusInternalServerError, "export impossible")
		return
	}

	w.Header().Set("Content-Type", "text/csv; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="ventes.csv"`)
	w.Write([]byte("\xEF\xBB\xBF")) // BOM : sans lui, Excel massacre les accents

	cw := csv.NewWriter(w)
	cw.Comma = ';'
	defer cw.Flush()

	cw.Write([]string{"id", "date", "heure", "total", "paiement", "reçu", "rendu"})
	for _, sale := range sales {
		date, heure := sale.CreatedAt, ""
		if t, err := time.Parse(time.RFC3339, sale.CreatedAt); err == nil {
			date, heure = t.Format("02/01/2006"), t.Format("15:04:05")
		}
		paiement := "Cash"
		if sale.PaymentMethod == "card" {
			paiement = "Bancontact"
		}
		cw.Write([]string{
			strconv.FormatInt(sale.ID, 10),
			date, heure,
			euros(sale.TotalCents),
			paiement,
			eurosPtr(sale.GivenCents),
			eurosPtr(sale.ChangeCents),
		})
	}
}

func euros(cents int) string {
	return fmt.Sprintf("%d,%02d", cents/100, cents%100)
}

func eurosPtr(cents *int) string {
	if cents == nil {
		return ""
	}
	return euros(*cents)
}
