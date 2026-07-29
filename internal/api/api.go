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
	"strconv"
	"time"

	"github.com/cmrabdu/boulangerie-pos/internal/db"
)

type Server struct {
	DB *db.DB
}

// Routes enregistre les points d'entrée de l'API sur un mux.
func (s *Server) Routes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/catalog", s.getCatalog)
	mux.HandleFunc("POST /api/sales", s.postSale)
	mux.HandleFunc("GET /api/sales/export.csv", s.exportSales)
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
