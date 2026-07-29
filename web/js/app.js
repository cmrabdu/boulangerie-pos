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

const release = (e) => {
	const t = e.target.closest?.(PRESSABLE);
	if (t) t.classList.remove('is-down');
	// Filet de sécurité : un pointeur perdu (doigt glissé hors de l'écran)
	// laisserait sinon un bouton enfoncé pour toujours.
	if (e.type === 'pointercancel') {
		document.querySelectorAll('.is-down').forEach((n) => n.classList.remove('is-down'));
	}
};
document.addEventListener('pointerup', release, { passive: true });
document.addEventListener('pointercancel', release, { passive: true });
document.addEventListener('pointerleave', release, { passive: true });

/** Animation courte et interruptible : la précédente est remplacée, jamais mise
 *  en file d'attente. */
function animate(node, keyframes, duration = 200) {
	if (!node) return;
	node.getAnimations().forEach((a) => a.cancel());
	node.animate(keyframes, {
		duration,
		easing: 'cubic-bezier(0.22, 0.61, 0.20, 1)',
		fill: 'none',
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
	state.activeCatId = state.catalog[0].id;
	renderCats();
	renderGrid(false);
}

function renderCats() {
	dom.cats.innerHTML = '';
	for (const c of state.catalog) {
		const b = document.createElement('button');
		b.type = 'button';
		b.className = 'cat';
		b.dataset.catId = c.id;
		b.setAttribute('role', 'tab');
		b.setAttribute('aria-selected', String(c.id === state.activeCatId));
		b.innerHTML = `<span class="cat-dot" style="--dot:var(--c-${c.color || 'stone'})"></span>${escapeHtml(c.name)}`;
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
		b.className = 'tile';
		b.dataset.productId = p.id;
		b.innerHTML =
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
	// Coupures belges courantes.
	for (const note of [500, 1000, 2000, 5000]) {
		if (note > due) candidates.add(note);
	}

	const values = [...candidates].filter((v) => v >= due).sort((a, b) => a - b).slice(0, 8);

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

function finishSale(change) {
	closePayment();
	state.cart.clear();
	renderCart(null);

	dom.doneText.textContent =
		change != null && change > 0 ? `À rendre ${money(change)}` : 'Vente enregistrée';

	dom.done.hidden = false;
	animate(dom.done, [{ opacity: 0 }, { opacity: 1 }], 160);
	animate(document.querySelector('.check-circle'),
		[{ strokeDashoffset: 152 }, { strokeDashoffset: 0 }], 380);
	animate(document.querySelector('.check-mark'),
		[{ strokeDashoffset: 40 }, { strokeDashoffset: 40 }, { strokeDashoffset: 0 }], 620);

	setTimeout(() => {
		animate(dom.done, [{ opacity: 1 }, { opacity: 0 }], 180);
		setTimeout(() => { dom.done.hidden = true; }, 170);
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
