package db

import (
	"strings"
	"unicode"
)

// Slugify transforme un nom de produit en nom de fichier d'image.
//
//	« Éclair chocolat »       → « eclair-chocolat »
//	« Pain gris 500g »        → « pain-gris-500g »
//	« Tarte au riz (part) »   → « tarte-au-riz-part »
//	« Œufs (6) »              → « oeufs-6 »
//	« + Fromage »             → « supplement-fromage »
//
// Le résultat ne contient que des minuscules non accentuées, des chiffres et
// des tirets : il doit rester tapable au clavier pour que déposer une image se
// résume à choisir le bon nom de fichier.
func Slugify(name string) string {
	var b strings.Builder
	b.Grow(len(name))

	lastWasDash := true // évite un tiret en tête
	for _, r := range strings.ToLower(name) {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			b.WriteRune(r)
			lastWasDash = false
		default:
			if repl, ok := translit[r]; ok {
				b.WriteString(repl)
				lastWasDash = false
				continue
			}
			// Toute autre lettre accentuée est ramenée à sa base quand c'est
			// possible ; sinon elle devient un séparateur.
			if base, ok := deaccent[r]; ok {
				b.WriteRune(base)
				lastWasDash = false
				continue
			}
			if !lastWasDash && (unicode.IsSpace(r) || unicode.IsPunct(r) || unicode.IsSymbol(r)) {
				b.WriteByte('-')
				lastWasDash = true
			}
		}
	}
	return strings.Trim(b.String(), "-")
}

// Ligatures et caractères qui se rendent par plusieurs lettres.
//
// Le « + » qui ouvre le nom d'un supplément fait partie du nom : sans lui,
// « + Fromage » et « Fromage » désignent le même fichier d'image, et l'un des
// deux se retrouve illustré par l'autre — une tranche là où il fallait un
// sandwich, ou l'inverse.
var translit = map[rune]string{
	'œ': "oe", 'æ': "ae", 'ß': "ss",
	'+': "supplement",
}

// Lettres accentuées du français et de ses voisins, ramenées à leur base.
var deaccent = map[rune]rune{
	'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
	'ç': 'c',
	'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
	'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
	'ñ': 'n',
	'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
	'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
	'ý': 'y', 'ÿ': 'y',
}
