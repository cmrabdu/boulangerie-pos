# Caisse boulangerie — raccourcis de développement et de déploiement.

BIN     := boulangerie-pos
DIST    := dist
ADDR    ?= 127.0.0.1:8099
DB      ?= caisse.db
CSV     ?= catalogue.csv

.PHONY: dev run build linux lan kit test fmt clean

## dev : lance la caisse en lisant web/ depuis le disque.
## Une retouche du CSS ou du JS ne demande qu'un rechargement de page.
dev:
	go run . -dev -addr $(ADDR) -db $(DB) -catalogue $(CSV)

## lan : idem, mais joignable depuis un iPad ou un téléphone du même réseau,
## pour tester le vrai tactile avant d'avoir accès à la caisse.
lan:
	go run . -dev -lan -addr $(ADDR) -db $(DB) -catalogue $(CSV)

## build : binaire pour cette machine (front embarqué).
build:
	go build -o $(DIST)/$(BIN) .

## run : compile puis lance, comme en production.
run: build
	./$(DIST)/$(BIN) -addr $(ADDR) -db $(DB) -catalogue $(CSV)

## linux : LE binaire à copier sur la caisse.
## Pas de cgo grâce à modernc.org/sqlite : la compilation croisée depuis un Mac
## ARM vers un Celeron 64 bits ne demande aucun outillage supplémentaire.
linux:
	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o $(DIST)/$(BIN)-linux-amd64 .
	@ls -lh $(DIST)/$(BIN)-linux-amd64

## kit : le dossier à copier sur une clé USB pour installer la caisse.
## Contient tout ce dont l'installeur a besoin, et rien d'autre.
kit: linux
	rm -rf $(DIST)/kit
	mkdir -p $(DIST)/kit
	cp $(DIST)/$(BIN)-linux-amd64 $(DIST)/kit/
	cp deploy/installer.sh $(DIST)/kit/
	cp deploy/README.md     $(DIST)/kit/
	cp deploy/preseed.cfg   $(DIST)/kit/
	cp -a img               $(DIST)/kit/
	@[ -f $(CSV) ] && cp $(CSV) $(DIST)/kit/ && echo "  catalogue inclus" || echo "  (pas de $(CSV) : le catalogue de démonstration servira)"
	@[ -f $$HOME/.ssh/id_ed25519.pub ] && cp $$HOME/.ssh/id_ed25519.pub $(DIST)/kit/cle-publique.pub && echo "  clé SSH incluse" || echo "  (pas de clé SSH trouvée)"
	@chmod +x $(DIST)/kit/installer.sh
	@echo
	@du -sh $(DIST)/kit
	@echo "  → copier $(DIST)/kit/ sur une clé USB"

test:
	go test ./...

fmt:
	gofmt -w .
	go vet ./...

clean:
	rm -rf $(DIST)
