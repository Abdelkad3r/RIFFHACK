# web4 — Coupon Stacking (SSR prop leak)

> *Expensive tools shouldn't be free, but some users claim they've found a
> way. Can you discover their secret?*

**Category:** Web — client-side trust / SSR prop leak
**Flag:** `bitflag{c0up0n_st4ck1ng_1s_4_d34l}`

## The brief, in plain English

Two things are true at once:

1. The "intended" exploit is a client-side coupon-stacking bug: the dedup
   check trims and uppercases the input but stores the raw string, so
   `WELCOME20`, `welcome20`, ` WELCOME20`, and friends are all "distinct"
   entries that each shave 20% off.
2. The flag never required actually stacking anything. The win-state secret
   is a React prop, and Next.js serialised it into the SSR HTML before any
   coupon UI even mounted.

There are two ways to solve the challenge. The "real" lesson is in why both
work.

## Recon

The marketplace lists six tool slugs in its client bundle:

```
loader-laas
macro-builder
web-injector
phish-kit
cloud-misconfig
rat-builder
```

Each renders at `/listing/<slug>`. Five of them are pure marketing copy and a
contact form; only **`macro-builder`** ships the `PurchaseButton` component
that mounts the checkout dialog. That's the first piece of recon — figure out
which listing actually has the buy flow.

A quick grep for the `Purchase Tool` button text across the six pages narrows
it down in one pass:

```bash
$ for s in loader-laas macro-builder web-injector phish-kit cloud-misconfig rat-builder; do
    echo "== $s =="
    curl -s http://159.89.230.27/listing/$s | grep -oE 'Purchase Tool[^"]*'
  done
```

Only `macro-builder` matches. So whatever the bug is, it's on
`/listing/macro-builder`.

## The "intended" bug — coupon stacking

Inside the listing-detail bundle
(`/_next/static/chunks/app/listing/%5Bid%5D/page-…js`), module `7176` exports
the checkout dialog. Its math:

```js
let f = 20 * i.length;            // 20% per applied entry
let v = Math.max(0, p - p*f/100);  // total after stacking
if (v === 0) renderFlag();
```

And the "are you applying the same coupon twice?" guard:

```js
const code = c.trim().toUpperCase();
if (code !== "WELCOME20") {
  setError("Only WELCOME20 is accepted.");
  return;
}
if (i.includes(c)) {            // ← checks the raw input, not the normalised one
  setError("Already applied.");
  return;
}
i.push(c);                       // ← stores the raw input
```

The normalisation is only used for the value check, not the dedup check. So
the following five inputs all pass *both* gates and each contributes 20%:

```
WELCOME20
welcome20
Welcome20
 WELCOME20    (leading space)
WELCOME20     (trailing space)
```

Five entries → 100% off → `v === 0` → the dialog renders the `couponFlag`
prop in a `<code>` element.

## The actual shortcut — the prop is already in the HTML

Next.js renders server components on the server and serialises their props
into the page's RSC payload. The `couponFlag` is one of those props. It is in
the HTML before any JavaScript runs, regardless of whether you ever click the
"Purchase" button, ever open the dialog, ever stack a coupon.

```bash
$ curl -s http://159.89.230.27/listing/macro-builder \
     | grep -oE '"couponFlag":"[^"]+"'
"couponFlag":"bitflag{c0up0n_st4ck1ng_1s_4_d34l}"
```

That's the entire exploit. No login, no cookies, no UI interaction. The flag
was shipped to the browser as part of the page itself.

## Root cause

The bug is in choosing to put a server-side secret into a client-side
component's props in the first place. Even if every UI gate had been
implemented correctly — strict dedup, server-side coupon redemption, atomic
discount math — the secret still ends up in the page's serialised RSC stream
because that's what server components *do*: they hand their props to client
components by writing them into the HTML.

The two bugs are conceptually separate:

- **Coupon-stacking** is a logic bug — the dedup check is on the wrong field.
- **Prop leak** is a framework-shape bug — putting any value into a client
  component's props is equivalent to writing it to a public URL.

The challenge is structured so the second bug makes the first one a
distraction.

## Mitigation

- **Never put a server-only secret in client component props.** If a value
  needs to gate a client behaviour, gate it on the server — e.g. only render
  the reward block after a server-confirmed action, and render it inline in
  a separate server component fetched on demand.
- For the coupon flow specifically: redeem coupons server-side, not in the
  browser. The total should be computed by the server in response to an
  `apply` action, and the response should be the *new total*, not "here's
  the win secret if you happen to bring the total to zero".
- If you do have to compare normalised values, **dedupe on the normalised
  form**. Pick one canonical representation and use it consistently for both
  validity and equality.

## Takeaways

- "Discover their secret" is the part of the brief that points squarely at
  the SSR prop. The intended trick is a misdirection — solvers who play
  through the coupon UI learn the logic bug, but solvers who curl the page
  get the same flag in a single HTTP request.
- Six listings, one is vulnerable. The recon move — figuring out which
  listing renders the checkout flow at all — is a useful muscle. Don't
  assume every page in a route group is the same.
- This is the same class of bug as [web5](05-web5-glitchy-contact-system.md).
  Both put a win-state secret into a React server prop and let the framework
  leak it into the HTML.

## One-liner

```bash
curl -s http://<host>/listing/macro-builder | grep -oE 'bitflag\{[^}]+\}'
```
