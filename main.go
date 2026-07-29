// Commande boulangerie-pos : la caisse tient dans un seul binaire.
//
// Le front (HTML/CSS/JS) est embarqué dans l'exécutable via go:embed, et les
// données vivent dans un unique fichier SQLite à côté. Déployer, c'est copier
// un fichier ; sauvegarder, c'est en copier un autre.
package main

import (
	"context"
	"embed"
	"errors"
	"flag"
	"io/fs"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/cmrabdu/boulangerie-pos/internal/api"
	"github.com/cmrabdu/boulangerie-pos/internal/db"
)

//go:embed all:web
var webFS embed.FS

func main() {
	log.SetFlags(log.Ltime)

	var (
		addr    = flag.String("addr", "127.0.0.1:8080", "adresse d'écoute")
		lan     = flag.Bool("lan", false, "écouter sur tout le réseau local (pour tester depuis un iPad ou un téléphone)")
		dbPath  = flag.String("db", "caisse.db", "chemin du fichier de base de données")
		csvPath = flag.String("import", "", "importer un catalogue CSV (catégorie;produit;prix) puis quitter")
		dev     = flag.Bool("dev", false, "servir web/ depuis le disque : une retouche du CSS ne demande qu'un rechargement de page")
		imgDir  = flag.String("img", "img", "dossier des illustrations de produits (img/products/<slug>.png)")
		watch   = flag.String("catalogue", "", "fichier CSV surveillé : la caisse se met à jour dès qu'il change, sans redémarrage")
	)
	flag.Parse()

	if *lan {
		_, port, err := net.SplitHostPort(*addr)
		if err != nil {
			log.Fatalf("adresse invalide : %v", err)
		}
		*addr = ":" + port
	}

	database, err := db.Open(*dbPath)
	if err != nil {
		log.Fatalf("base de données : %v", err)
	}
	defer database.Close()

	if *csvPath != "" {
		if err := importCSV(database, *csvPath); err != nil {
			log.Fatalf("import : %v", err)
		}
		return
	}

	if err := seedIfEmpty(database, *watch); err != nil {
		log.Fatalf("catalogue initial : %v", err)
	}

	if err := serve(database, *addr, *lan, *dev, *imgDir, *watch); err != nil {
		log.Fatalf("serveur : %v", err)
	}
}

func importCSV(database *db.DB, path string) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()

	cats, err := db.ParseCatalogCSV(f)
	if err != nil {
		return err
	}
	if err := database.ReplaceCatalog(cats); err != nil {
		return err
	}

	n := 0
	for _, c := range cats {
		n += len(c.Products)
	}
	log.Printf("catalogue importé : %d catégories, %d produits", len(cats), n)
	return nil
}

// surveillerCatalogue réimporte le CSV dès qu'il change sur le disque.
//
// C'est la façon dont la boulangerie met son catalogue à jour : on dépose le
// fichier par SSH, la caisse le prend en compte en quelques secondes. Aucun
// bouton « paramètres » n'apparaît donc à l'écran — tout ce qui ne sert pas à
// encaisser n'a rien à y faire.
//
// Un sondage toutes les trois secondes plutôt qu'une surveillance du système de
// fichiers : c'est trois appels stat par minute, et cela fonctionne aussi bien
// avec un fichier remplacé par scp qu'avec un fichier modifié sur place.
func surveillerCatalogue(database *db.DB, srv *api.Server, path string) {
	var derniere time.Time
	var taille int64

	if fi, err := os.Stat(path); err == nil {
		derniere, taille = fi.ModTime(), fi.Size()
		log.Printf("catalogue surveillé : %s", path)
	} else {
		log.Printf("catalogue surveillé : %s (absent pour l'instant)", path)
	}

	for range time.Tick(3 * time.Second) {
		fi, err := os.Stat(path)
		if err != nil {
			continue
		}
		if fi.ModTime().Equal(derniere) && fi.Size() == taille {
			continue
		}
		derniere, taille = fi.ModTime(), fi.Size()

		if err := importCSV(database, path); err != nil {
			// Un CSV mal formé ne doit pas casser la caisse : on garde le
			// catalogue précédent et on le signale dans le journal.
			log.Printf("catalogue ignoré (%v) — l'ancien reste en place", err)
			continue
		}
		srv.BumpGeneration()
	}
}

// seedIfEmpty remplit le catalogue au tout premier lancement, pour que l'écran
// ne soit jamais vide au démarrage.
//
// Le CSV surveillé l'emporte s'il est déjà là : sur une caisse fraîchement
// installée, on copie le catalogue de la boulangerie puis on démarre, et il
// serait absurde d'afficher d'abord des produits inventés.
func seedIfEmpty(database *db.DB, watchPath string) error {
	empty, err := database.IsEmpty()
	if err != nil || !empty {
		return err
	}

	if watchPath != "" {
		if _, err := os.Stat(watchPath); err == nil {
			log.Printf("base vide : import de %s", watchPath)
			if err := importCSV(database, watchPath); err == nil {
				return nil
			}
			log.Print("ce catalogue est illisible, chargement du catalogue de démonstration")
		}
	}

	log.Print("base vide : chargement du catalogue de démonstration")
	return database.ReplaceCatalog(db.DemoCatalog())
}

func serve(database *db.DB, addr string, lan, dev bool, imgDir, watchPath string) error {
	var static fs.FS
	if dev {
		log.Print("mode développement : le front est lu depuis ./web")
		static = os.DirFS("web")
	} else {
		sub, err := fs.Sub(webFS, "web")
		if err != nil {
			return err
		}
		static = sub
	}

	mux := http.NewServeMux()
	srv := &api.Server{DB: database, ImgDir: imgDir}
	srv.Routes(mux)

	// Les illustrations viennent du disque, jamais de l'exécutable : en ajouter
	// une sur la caisse doit se résumer à copier un fichier par SSH.
	//
	// `no-cache` ne veut pas dire « ne pas garder » mais « toujours revérifier » :
	// le navigateur conserve l'image et demande simplement si elle a changé, ce
	// à quoi le serveur répond 304 sans rien renvoyer. On garde donc le bénéfice
	// du cache sans jamais afficher une image périmée après un dépôt par SSH.
	mux.Handle("GET /img/", http.StripPrefix("/img/",
		revalider(http.FileServer(http.Dir(imgDir)))))

	mux.Handle("GET /", noCache(http.FileServer(http.FS(static))))

	if watchPath != "" {
		go surveillerCatalogue(database, srv, watchPath)
	}

	httpSrv := &http.Server{
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return err
	}

	log.Printf("caisse prête → http://localhost:%s", port(ln))
	if lan {
		if ip := localIP(); ip != "" {
			log.Printf("depuis un autre appareil du réseau → http://%s:%s", ip, port(ln))
		}
	}

	// Arrêt propre : sur la caisse, l'extinction ne doit pas laisser la base
	// dans un état incertain au milieu d'une vente.
	errc := make(chan error, 1)
	go func() { errc <- httpSrv.Serve(ln) }()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	select {
	case err := <-errc:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	case <-stop:
		log.Print("arrêt…")
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		return httpSrv.Shutdown(ctx)
	}
}

// noCache empêche le navigateur de garder une ancienne version du front après
// une mise à jour du binaire. La caisse sert des fichiers depuis la mémoire :
// le cache n'apporte rien et ne fait que créer des surprises.
func noCache(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		h.ServeHTTP(w, r)
	})
}

// revalider demande au navigateur de revérifier avant de réutiliser un fichier
// gardé en cache. http.FileServer pose déjà Last-Modified et sait répondre 304.
func revalider(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-cache")
		h.ServeHTTP(w, r)
	})
}

func port(ln net.Listener) string {
	if a, ok := ln.Addr().(*net.TCPAddr); ok {
		return itoa(a.Port)
	}
	return "8080"
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b [8]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	return string(b[i:])
}

// localIP renvoie l'adresse IPv4 de la machine sur le réseau local, pour
// afficher une URL utilisable depuis un téléphone.
func localIP() string {
	conn, err := net.Dial("udp", "192.0.2.1:80") // adresse de test, aucun paquet n'est émis
	if err != nil {
		return ""
	}
	defer conn.Close()
	if a, ok := conn.LocalAddr().(*net.UDPAddr); ok {
		return a.IP.String()
	}
	return ""
}
