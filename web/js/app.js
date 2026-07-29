/* ==========================================================================
   Caisse boulangerie — logique d'interface.

   Trois règles tenues d'un bout à l'autre du fichier :

   1. TOUS LES MONTANTS SONT DES ENTIERS EN CENTIMES.
      Aucun prix ne passe jamais par un nombre à virgule. En JavaScript,
      0.1 + 0.2 vaut 0.30000000000000004 ; une caisse ne peut pas se le
      permettre. La conversion en euros n'a lieu qu'à l'affichage.

   2. LE RETOUR AU DOIGT EST IMMÉDIAT, LE MOUVEMENT EST ANIMÉ.
      L'enfoncement d'une tuile se déclenche sur `pointerdown`, pas sur
      `click` : l'utilisatrice voit sa pression avant même d'avoir relâché.
      Ce qui suit — apparition de la ligne, total qui roule — est animé.

   3. AUCUNE ANIMATION NE BLOQUE UNE ACTION.
      Toutes sont interruptibles. Trois produits tapés en une seconde donnent
      trois réactions immédiates, pas une file d'attente.
   ========================================================================== */

'use strict';

/* --------------------------------------------------------------------------
   Réglages
   -------------------------------------------------------------------------- */

/* En Belgique, les paiements EN ESPÈCES sont arrondis au multiple de 5 centimes
   le plus proche ; les paiements par carte ne le sont pas. L'interface affiche
   toujours l'arrondi explicitement pour qu'il ne soit jamais une surprise.

   ⚠ À faire confirmer par le comptable avant la mise en service réelle.
   Pour désactiver : passer cette constante à false. */
const ARRONDI_CASH_5_CENTIMES = true;

const DUREE_TOTAL = 260;   // durée du défilement du total, en ms
const DUREE_DONE  = 1100;  // durée de l'écran de confirmation, en ms

/* --------------------------------------------------------------------------
   État
   -------------------------------------------------------------------------- */

const state = {
	catalog: [],
	activeCatId: null,
	/** Map<productId, {id, name, priceCents, qty}> — l'ordre d'insertion est
	 *  celui du ticket, ce que Map garantit. */
	cart: new Map(),
	method: null,        // 'cash' | 'card' pendant le paiement
	givenCents: null,    // ce que le client a donné, en cash
	busy: false,         // une vente est en cours d'enregistrement
};

const el = (id) => document.getElementById(id);
const dom = {
	cats: el('cats'), grid: el('grid'),
	lines: el('lines'), empty: el('empty'), clear: el('clear'),
	total: el('total'),
	payCash: el('pay-cash'), payCard: el('pay-card'),
	payScreen: el('pay-screen'), paySheet: document.querySelector('.pay-sheet'),
	payBack: el('pay-back'),
	dueLabel: el('due-label'), dueAmount: el('due-amount'), dueNote: el('due-note'),
	cashPad: el('cash-pad'), pad: el('pad'),
	change: el('change'), changeAmount: el('change-amount'),
	cardWait: el('card-wait'), confirm: el('confirm'),
	done: el('done'), doneText: el('done-text'),
	check: document.querySelector('.check'),
	checkCircle: document.querySelector('.check-circle'),
	checkMark: document.querySelector('.check-mark'),
};

/* --------------------------------------------------------------------------
   Argent
   -------------------------------------------------------------------------- */

/** 130 → « 1,30 € » (avec une espace insécable avant le symbole). */
function money(cents) {
	const sign = cents < 0 ? '-' : '';
	const a = Math.abs(cents);
	return `${sign}${Math.floor(a / 100)},${String(a % 100).padStart(2, '0')} €`;
}

/** Arrondi belge au multiple de 5 centimes le plus proche. */
function arrondiCash(cents) {
	return ARRONDI_CASH_5_CENTIMES ? Math.round(cents / 5) * 5 : cents;
}

function totalCents() {
	let t = 0;
	for (const l of state.cart.values()) t += l.priceCents * l.qty;
	return t;
}

/** Montant réellement réclamé au client, selon le mode de paiement. */
function dueCents(method) {
	const t = totalCents();
	return method === 'cash' ? arrondiCash(t) : t;
}

/* --------------------------------------------------------------------------
   Retour tactile — la partie qui doit être instantanée
   -------------------------------------------------------------------------- */

const PRESSABLE = '.tile, .cat, .pad-btn, .pay-btn:not(:disabled), .qty-btn, .confirm';

/* `pointerdown` plutôt que `click` : l'enfoncement est visible avant même que
   le doigt se relève. C'est ce décalage de ~80 ms qui fait toute la différence
   entre une interface « qui répond » et une interface « qui rame ». */
document.addEventListener('pointerdown', (e) => {
	const t = e.target.closest(PRESSABLE);
	if (t) t.classList.add('is-down');
}, { passive: true });

/* On relâche TOUT, pas seulement l'élément sous le doigt : si le doigt glisse
   hors de la tuile avant de se lever, le relâchement ne vise plus la tuile
   pressée, qui resterait enfoncée indéfiniment. */
const release = () => {
	document.querySelectorAll('.is-down').forEach((n) => n.classList.remove('is-down'));
};
document.addEventListener('pointerup', release, { passive: true });
document.addEventListener('pointercancel', release, { passive: true });
document.addEventListener('pointerleave', release, { passive: true });

/** Animation courte et interruptible : la précédente est remplacée, jamais mise
 *  en file d'attente.
 *
 *  `fill: 'forwards'` est indispensable pour les disparitions : sans lui,
 *  l'élément revient brutalement à son opacité de départ à la dernière image,
 *  ce qui produit un clignotement juste avant qu'on le masque. */
function animate(node, keyframes, duration = 200, opts = {}) {
	if (!node) return null;
	node.getAnimations().forEach((a) => a.cancel());
	return node.animate(keyframes, {
		duration,
		easing: opts.easing || 'cubic-bezier(0.22, 0.61, 0.20, 1)',
		fill: opts.fill || 'none',
		delay: opts.delay || 0,
	});
}

/* --------------------------------------------------------------------------
   Catalogue
   -------------------------------------------------------------------------- */

async function loadCatalog() {
	try {
		const res = await fetch('/api/catalog');
		if (!res.ok) throw new Error(res.statusText);
		state.catalog = await res.json();
	} catch (err) {
		console.error('catalogue :', err);
		dom.grid.innerHTML =
			'<p class="empty" style="position:static">Catalogue indisponible.<br>Le serveur de la caisse est-il démarré ?</p>';
		return;
	}
	if (state.catalog.length === 0) return;

	// Après un rechargement du catalogue, on reste sur la même catégorie si
	// elle existe encore : les identifiants changent à chaque import, pas les
	// noms.
	const cat = state.catalog.find((c) => c.name === previousName) || state.catalog[0];
	state.activeCatId = cat.id;
	previousName = cat.name;

	renderCats();
	renderGrid(false);
}

let previousName = null;

/* --------------------------------------------------------------------------
   Mise à jour du catalogue par SSH

   La boulangerie ne met pas son catalogue à jour depuis l'écran : il n'y a
   volontairement aucun bouton « paramètres ». On dépose un CSV sur la machine,
   le serveur le réimporte, et la caisse s'en aperçoit ici.

   Le rafraîchissement n'a jamais lieu pendant une vente : ni panier en cours,
   ni écran de paiement ouvert. Voir un produit changer sous le doigt serait
   pire que de rester une minute sur l'ancien catalogue.
   -------------------------------------------------------------------------- */

let catalogVersion = null;

async function verifierCatalogue() {
	if (state.cart.size > 0 || !dom.payScreen.hidden || state.busy) return;
	try {
		const res = await fetch('/api/catalog/version');
		if (!res.ok) return;
		const { version } = await res.json();
		if (catalogVersion === null) { catalogVersion = version; return; }
		if (version !== catalogVersion) {
			catalogVersion = version;
			await loadCatalog();
			console.info('catalogue rechargé');
		}
	} catch {
		// Serveur momentanément absent : on retentera au prochain tour.
	}
}

setInterval(verifierCatalogue, 8000);

/* Chaque catégorie reçoit une icône déduite de son nom. Le catalogue vient d'un
   CSV qui ne contient que « catégorie, produit, prix » : rien ne dit quelle
   icône utiliser, on la devine donc par mots-clés. Une catégorie inattendue
   tombe sur l'icône générique, ce qui est toujours mieux que rien. */
const ICONES = [
	[/pain|boulang|miche|baguet/, 'i-pain', 'wheat'],
	[/viennois|croissant|couque|donut/, 'i-croissant', 'butter'],
	[/p[âa]tiss|g[âa]teau|tarte|dessert|sucr/, 'i-patisserie', 'berry'],
	[/sandwich|snack|salade|tartine|panini|baguette garnie/, 'i-sandwich', 'herb'],
	[/boisson|caf[ée]|jus|drink|soda|th[ée]/, 'i-boisson', 'water'],
];

function iconeCategorie(nom, couleur) {
	const n = nom.toLowerCase();
	for (const [motif, icone, teinte] of ICONES) {
		if (motif.test(n)) return { icone, teinte: couleur || teinte };
	}
	return { icone: 'i-divers', teinte: couleur || 'stone' };
}

function renderCats() {
	dom.cats.innerHTML = '';
	for (const c of state.catalog) {
		const { icone, teinte } = iconeCategorie(c.name, c.color);
		const b = document.createElement('button');
		b.type = 'button';
		b.className = 'cat';
		b.dataset.catId = c.id;
		b.setAttribute('role', 'tab');
		b.setAttribute('aria-selected', String(c.id === state.activeCatId));
		b.innerHTML =
			`<svg class="cat-ico" style="--dot:var(--c-${teinte})" aria-hidden="true">` +
			`<use href="#${icone}"></use></svg>${escapeHtml(c.name)}`;
		dom.cats.appendChild(b);
	}
}

function renderGrid(withAnimation = true) {
	const cat = state.catalog.find((c) => c.id === state.activeCatId);
	dom.grid.innerHTML = '';
	if (!cat) return;

	for (const p of cat.products) {
		const b = document.createElement('button');
		b.type = 'button';
		b.className = p.image ? 'tile has-img' : 'tile';
		b.dataset.productId = p.id;
		// Le nom accessible est porté par le bouton : l'image est décorative
		// (alt vide) et ne doit pas être annoncée à la place du produit.
		b.setAttribute('aria-label', `${p.name}, ${money(p.priceCents)}`);
		b.innerHTML =
			(p.image
				? `<img class="tile-img" src="${escapeHtml(p.image)}" alt="" loading="lazy" decoding="async">`
				: '') +
			`<span class="tile-name">${escapeHtml(p.name)}</span>` +
			`<span class="tile-price">${money(p.priceCents)}</span>`;
		dom.grid.appendChild(b);
	}

	if (withAnimation) {
		animate(dom.grid, [
			{ opacity: 0, transform: 'translateY(0.5rem)' },
			{ opacity: 1, transform: 'translateY(0)' },
		], 190);
	}
	dom.grid.parentElement.scrollTop = 0;
}

/* --------------------------------------------------------------------------
   Panier
   -------------------------------------------------------------------------- */

function addProduct(id) {
	const product = findProduct(id);
	if (!product) return;

	const existing = state.cart.get(id);
	if (existing) {
		existing.qty += 1;
	} else {
		state.cart.set(id, {
			id, name: product.name, priceCents: product.priceCents, qty: 1,
		});
	}
	renderCart(id);
}

function changeQty(id, delta) {
	const line = state.cart.get(id);
	if (!line) return;
	line.qty += delta;
	if (line.qty <= 0) state.cart.delete(id);
	renderCart(line.qty > 0 ? id : null);
}

function findProduct(id) {
	for (const c of state.catalog) {
		const p = c.products.find((p) => p.id === id);
		if (p) return p;
	}
	return null;
}

/** Redessine le ticket. `highlightId` est la ligne qui vient de bouger : elle
 *  seule est animée, pour que l'œil sache où regarder. */
function renderCart(highlightId) {
	const previousTotal = readDisplayedTotal();

	dom.lines.innerHTML = '';
	for (const line of state.cart.values()) {
		const li = document.createElement('li');
		li.className = 'line';
		li.dataset.productId = line.id;
		li.innerHTML =
			`<span class="line-name">${escapeHtml(line.name)}</span>` +
			`<span class="line-price">${money(line.priceCents)} × ${line.qty} = ${money(line.priceCents * line.qty)}</span>` +
			`<span class="line-qty">
				<button class="qty-btn" type="button" data-delta="-1" aria-label="Retirer un ${escapeHtml(line.name)}">−</button>
				<span class="qty-val">${line.qty}</span>
				<button class="qty-btn" type="button" data-delta="1" aria-label="Ajouter un ${escapeHtml(line.name)}">+</button>
			</span>`;
		dom.lines.appendChild(li);
	}

	const empty = state.cart.size === 0;
	dom.empty.hidden = !empty;
	dom.clear.hidden = empty;
	dom.payCash.disabled = empty;
	dom.payCard.disabled = empty;
	disarmClear();

	if (highlightId != null) {
		const li = dom.lines.querySelector(`[data-product-id="${highlightId}"]`);
		if (li) {
			animate(li, [
				{ opacity: 0, transform: 'translateX(0.75rem)' },
				{ opacity: 1, transform: 'translateX(0)' },
			], 200);
			li.scrollIntoView({ block: 'nearest' });
		}
	}

	rollTotal(previousTotal, totalCents());
}

/* --------------------------------------------------------------------------
   Le total qui roule
   -------------------------------------------------------------------------- */

let totalRAF = 0;
let displayedTotal = 0;

function readDisplayedTotal() { return displayedTotal; }

/* On anime la VALEUR, pas une propriété CSS : le texte défile de l'ancien au
   nouveau montant. Combiné à `tabular-nums`, la largeur ne bouge pas, donc
   aucun recalcul de mise en page pendant l'animation. */
function rollTotal(from, to) {
	cancelAnimationFrame(totalRAF);
	displayedTotal = to;

	if (from === to) { dom.total.textContent = money(to); return; }

	animate(dom.total, [
		{ transform: 'scale(1.045)' },
		{ transform: 'scale(1)' },
	], 220);

	const start = performance.now();
	const step = (now) => {
		const t = Math.min(1, (now - start) / DUREE_TOTAL);
		const eased = 1 - Math.pow(1 - t, 3);           // ease-out cubique
		dom.total.textContent = money(Math.round(from + (to - from) * eased));
		if (t < 1) totalRAF = requestAnimationFrame(step);
		else dom.total.textContent = money(to);
	};
	totalRAF = requestAnimationFrame(step);
}

/* --------------------------------------------------------------------------
   « Tout effacer » — armé puis confirmé, pour qu'un faux contact ne vide
   jamais un ticket en cours.
   -------------------------------------------------------------------------- */

let clearTimer = 0;

function armClear() {
	dom.clear.classList.add('is-armed');
	dom.clear.textContent = 'Confirmer ?';
	clearTimer = setTimeout(disarmClear, 2600);
}

function disarmClear() {
	clearTimeout(clearTimer);
	dom.clear.classList.remove('is-armed');
	dom.clear.textContent = 'Tout effacer';
}

/* --------------------------------------------------------------------------
   Paiement
   -------------------------------------------------------------------------- */

function openPayment(method) {
	if (state.cart.size === 0) return;
	state.method = method;
	state.givenCents = null;

	const total = totalCents();
	const due = dueCents(method);

	dom.dueAmount.textContent = money(due);
	dom.dueLabel.textContent = method === 'cash' ? 'À payer en espèces' : 'À payer par Bancontact';

	// L'arrondi n'est jamais silencieux : s'il change le montant, on le dit.
	if (method === 'cash' && due !== total) {
		dom.dueNote.textContent = `Total ${money(total)} — arrondi aux 5 centimes`;
		dom.dueNote.hidden = false;
	} else {
		dom.dueNote.hidden = true;
	}

	dom.cashPad.hidden = method !== 'cash';
	dom.cardWait.hidden = method !== 'card';
	dom.change.hidden = true;
	dom.confirm.textContent = 'Encaissé';

	if (method === 'cash') renderPad(due);

	dom.payScreen.hidden = false;
	animate(dom.payScreen, [{ opacity: 0 }, { opacity: 1 }], 160);
	animate(dom.paySheet, [
		{ opacity: 0, transform: 'translateY(1.5rem) scale(0.985)' },
		{ opacity: 1, transform: 'translateY(0) scale(1)' },
	], 240);
}

function closePayment() {
	state.method = null;
	state.givenCents = null;
	dom.payScreen.hidden = true;
}

/** Propositions de billets et pièces : le montant exact, puis les coupures
 *  plausibles au-dessus. Tout est optionnel — « Encaissé » clôture sans saisie. */
function renderPad(due) {
	const candidates = new Set([due]);

	// Arrondis « naturels » que fait un client : au demi-euro, à l'euro, aux 5 €.
	for (const step of [50, 100, 500, 1000]) {
		candidates.add(Math.ceil(due / step) * step);
	}
	// Coupures belges courantes, jusqu'au billet de 100 €.
	for (const note of [500, 1000, 2000, 5000, 10000]) {
		if (note > due) candidates.add(note);
	}

	const values = [...candidates].filter((v) => v >= due).sort((a, b) => a - b).slice(0, 9);

	dom.pad.innerHTML = '';
	for (const v of values) {
		const b = document.createElement('button');
		b.type = 'button';
		b.className = 'pad-btn' + (v === due ? ' is-exact' : '');
		b.dataset.given = String(v);
		b.textContent = v === due ? 'Compte juste' : money(v);
		dom.pad.appendChild(b);
	}
}

function setGiven(given) {
	const due = dueCents(state.method);
	state.givenCents = given;

	const change = given - due;
	dom.changeAmount.textContent = money(change);
	dom.change.hidden = false;
	animate(dom.change, [
		{ opacity: 0, transform: 'translateY(0.4rem)' },
		{ opacity: 1, transform: 'translateY(0)' },
	], 200);

	dom.pad.querySelectorAll('.pad-btn').forEach((b) => {
		b.classList.toggle('is-exact', Number(b.dataset.given) === given);
	});
}

async function confirmPayment() {
	if (state.busy || state.cart.size === 0) return;
	state.busy = true;
	dom.confirm.textContent = 'Enregistrement…';

	const lines = [...state.cart.values()].map((l) => ({
		productId: l.id,
		name: l.name,
		unitPriceCents: l.priceCents,
		quantity: l.qty,
	}));

	try {
		const res = await fetch('/api/sales', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({
				paymentMethod: state.method,
				givenCents: state.givenCents,
				lines,
			}),
		});
		if (!res.ok) throw new Error(`HTTP ${res.status}`);
	} catch (err) {
		/* Une vente qui ne s'enregistre pas ne doit JAMAIS disparaître en
		   silence : on garde le ticket à l'écran et on le dit. */
		console.error('enregistrement :', err);
		dom.dueNote.textContent = 'Vente non enregistrée — le ticket est conservé, réessayez.';
		dom.dueNote.hidden = false;
		dom.confirm.textContent = 'Réessayer';
		state.busy = false;
		return;
	}

	const change = state.givenCents != null ? state.givenCents - dueCents(state.method) : null;
	finishSale(change);
	state.busy = false;
}

/* L'encaissement est le moment le plus satisfaisant de la vente : il mérite un
   enchaînement, pas une coupure. La feuille de paiement se retire vers le bas
   pendant que la confirmation monte — les deux se croisent, si bien que l'œil
   suit un mouvement continu au lieu de subir deux changements d'écran.
   La coche arrive avec un léger dépassement d'échelle : c'est ce petit rebond
   qui fait qu'on la sent « se poser » au lieu d'apparaître. */
function finishSale(change) {
	// 1. Sortie de la feuille de paiement.
	animate(dom.paySheet, [
		{ opacity: 1, transform: 'scale(1) translateY(0)' },
		{ opacity: 0, transform: 'scale(0.955) translateY(0.7rem)' },
	], 200, { fill: 'forwards', easing: 'cubic-bezier(0.4, 0, 0.9, 1)' });
	animate(dom.payScreen, [{ opacity: 1 }, { opacity: 0 }], 240, { fill: 'forwards' });

	// 2. Entrée de la confirmation, croisant la sortie précédente.
	dom.doneText.textContent =
		change != null && change > 0 ? `À rendre ${money(change)}` : 'Vente enregistrée';

	dom.done.hidden = false;
	animate(dom.done, [{ opacity: 0 }, { opacity: 1 }], 200, { fill: 'forwards', delay: 90 });

	animate(dom.check, [
		{ opacity: 0, transform: 'scale(0.7)' },
		{ opacity: 1, transform: 'scale(1.06)', offset: 0.6 },
		{ opacity: 1, transform: 'scale(1)' },
	], 460, { fill: 'forwards', delay: 110 });

	animate(dom.checkCircle,
		[{ strokeDashoffset: 152 }, { strokeDashoffset: 0 }], 420,
		{ fill: 'forwards', delay: 130 });
	animate(dom.checkMark,
		[{ strokeDashoffset: 40 }, { strokeDashoffset: 40 }, { strokeDashoffset: 0 }], 600,
		{ fill: 'forwards', delay: 130 });

	// Le montant à rendre monte en dernier : c'est la seule chose que la
	// caissière doit encore lire.
	animate(dom.doneText, [
		{ opacity: 0, transform: 'translateY(0.7rem)' },
		{ opacity: 1, transform: 'translateY(0)' },
	], 320, { fill: 'forwards', delay: 320 });

	// 3. Remise à zéro, effectuée derrière la confirmation.
	setTimeout(() => {
		closePayment();
		state.cart.clear();
		renderCart(null);
	}, 260);

	// 4. Disparition.
	setTimeout(() => {
		animate(dom.done, [{ opacity: 1 }, { opacity: 0 }], 260, { fill: 'forwards' });
		setTimeout(() => { dom.done.hidden = true; }, 265);
	}, DUREE_DONE);
}

/* --------------------------------------------------------------------------
   Câblage des événements
   -------------------------------------------------------------------------- */

document.addEventListener('click', (e) => {
	const cat = e.target.closest('.cat');
	if (cat) {
		const id = Number(cat.dataset.catId);
		if (id !== state.activeCatId) {
			state.activeCatId = id;
			dom.cats.querySelectorAll('.cat').forEach((n) => {
				n.setAttribute('aria-selected', String(Number(n.dataset.catId) === id));
			});
			renderGrid(true);
		}
		return;
	}

	const tile = e.target.closest('.tile');
	if (tile) { addProduct(Number(tile.dataset.productId)); return; }

	const qty = e.target.closest('.qty-btn');
	if (qty) {
		const line = qty.closest('.line');
		changeQty(Number(line.dataset.productId), Number(qty.dataset.delta));
		return;
	}

	if (e.target.closest('#clear')) {
		if (dom.clear.classList.contains('is-armed')) {
			state.cart.clear();
			renderCart(null);
		} else {
			armClear();
		}
		return;
	}

	if (e.target.closest('#pay-cash')) { openPayment('cash'); return; }
	if (e.target.closest('#pay-card')) { openPayment('card'); return; }
	if (e.target.closest('#pay-back'))  { closePayment(); return; }

	const padBtn = e.target.closest('.pad-btn');
	if (padBtn) { setGiven(Number(padBtn.dataset.given)); return; }

	if (e.target.closest('#confirm')) { confirmPayment(); return; }
});

// Utile au clavier de secours et pendant le développement.
document.addEventListener('keydown', (e) => {
	if (e.key === 'Escape' && !dom.payScreen.hidden) closePayment();
});

/* Le zoom à deux doigts est déjà bloqué par la balise viewport, mais Safari sur
   iPad honore encore le double-tap : on le neutralise ici. */
document.addEventListener('gesturestart', (e) => e.preventDefault());

function escapeHtml(s) {
	return String(s).replace(/[&<>"']/g, (c) => (
		{ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
	));
}

loadCatalog();
