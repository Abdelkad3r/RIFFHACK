# RIFFHACK — Web Challenge Writeups

These are my writeups for the **riffhack** event — a CTF built around a fictional
Next.js "exploit kit marketplace" called *riffhack // exploit kit marketplace*. The
site is themed as a darknet storefront for offensive tooling. Every challenge
plants its bug somewhere in that codebase, and the flag format is `bitflag{...}`
(single braces — not to be confused with bitctf's literal-doubled `bitctf{{...}}`).

Eleven challenges are solved and documented here, in roughly the order I worked
through them.

## Contents

### Core web track

| # | Challenge | Class | Flag |
|---|-----------|-------|------|
| 1 | [Robots.txt Courtesy](01-web1-robots-txt.md) | Recon | `bitflag{r0b0ts_4r3_n0t_4_s3cr3t_v4ult}` |
| 2 | [The Trusting Login Desk](02-web2-open-redirect.md) | Open redirect → token leak | `bitflag{tru5t3d_r3d1r3cts_c4n_c4rry_s3cr3ts}` |
| 3 | [Buyer Lookup Loose Query](03-web3-sqli-orders-lookup.md) | SQL injection | `bitflag{1nj3ct10n_turn5_4_l00kup_1nt0_4_l34k}` |
| 4 | [Coupon Stacking](04-web4-coupon-stacking.md) | SSR prop leak | `bitflag{c0up0n_st4ck1ng_1s_4_d34l}` |
| 5 | [The Glitchy Contact System](05-web5-glitchy-contact-system.md) | SSR prop leak via error throw | `bitflag{d3bug_m0d3_1s_d4ng3r0us}` |
| 6 | [Marketplace Reviews Look Tidy](06-web6-review-idor.md) | IDOR (URL-path id) | `bitflag{r3v13w_0wn3r5h1p_1s_n0t_4_sugg35t10n}` |
| 7 | [Order History Should Be Private](07-web7-orders-jwt-idor.md) | JWT `alg:none` + IDOR | `bitflag{1d0r_1s_4_d4ng3r0us_g4m3}` |

### Named challenges (cross-event / extended track)

| # | Challenge | Class | Flag |
|---|-----------|-------|------|
| 8 | [The Night Dump](08-the-night-dump.md) | Over-scoped diagnostic export | `bitflag{3xp0rts_sh0uld_n0t_b3_0p3n_b00ks}` |
| 9 | [The Proof Stamp](09-the-proof-stamp.md) | Server-stamped fake-proof | `bitflag{md5_1s_br0k3n_l1k3_my_h34rt}` |
| 10 | [The Trusting Verifier](10-the-trusting-verifier.md) | SSRF → IMDS user-data | `bitflag{ssrf_1s_4_p4rty_cr4sh3r}` |
| 11 | [The Proof Locker](11-the-proof-locker.md) | Path traversal → LFI | `bitflag{pr00f_p4ths_5h0uld_st4y_1n_b0unds}` |

## A word on style

Several of these challenges share a clever design pattern worth highlighting up
front, because it shaped how I solved (and mis-solved) the rest:

> The marketplace codebase is **salted with flag-shaped strings**. Many of them
> are real, intentional flags for *some* version of the challenge — they're
> wired into seed rows, SSR props, mocked IMDS responses. Whether a given string
> is the *real* flag or a *decoy* depends entirely on which challenge brief the
> deployment is serving. The same string that's a planted lure on web5 turns up
> as the legitimate answer on "The Night Dump", "Vendor's Secret Door", and so
> on.

That means **grepping for `bitflag\{` is necessary but not sufficient** — you
have to match the brief to the surface, not just the value to the format. A
chunk of every writeup below is about resisting the wrong attractor and
landing the right one.

## Recurring primitives

A handful of bugs in the codebase reappear across challenges. Worth knowing all
of them before tackling any one challenge:

- **`alg:none` JWT** — every endpoint that reads the `auth-token` cookie accepts
  an unsigned token. Forge `{"id":"<anyone>","isVendor":<bool>}` and the server
  treats you as that user. Powers web7 and Vendor's Secret Door.
- **String-concatenated SQL on `/api/orders/lookup`** — the `ref=` query
  parameter is dropped into a raw query, giving classic tautology / UNION
  injection. Powers web3 and is the universal pivot for dumping seed rows in
  any other challenge.
- **SSR-baked client props** — Next.js serialises server props into the page's
  RSC payload before any JS runs. The `couponFlag` on web4 and the `flag` prop
  on web5 are both gated behind UI events that never need to fire — the value
  is in the HTML at first byte.
- **SSRF on `/api/vendor/verify-website`** — no allow-list. Reaches
  `127.0.0.1:3000`, public hosts, and the mocked AWS IMDS at
  `169.254.169.254`. Powers The Trusting Verifier.
- **Path traversal on `/api/reviews/proof?proof=…`** — concatenates the query
  parameter into a filesystem path. Powers The Proof Locker.

If a challenge brief mentions buyers, orders, reviews, vendors, exports, or
"proof", it's almost certainly built on one of the five primitives above.

## How to read these

Each writeup is self-contained: brief, reconnaissance, exploitation, root
cause, mitigation. Where a challenge has a "wrong attractor" I spent time on,
I leave the dead-end in — partly because the misdirection IS the lesson, and
partly so future-me can see why I didn't just walk straight to the answer.

## Repository layout

```
RIFFHACK/
├── README.md                          ← you are here
├── 01-web1-robots-txt.md              ← writeups, in solve order
├── …
├── 11-the-proof-locker.md
├── scripts/                           ← runnable solver per challenge
│   ├── lib/
│   │   ├── login.sh                   ← get an auth-token cookie (any creds)
│   │   └── jwt-none.sh                ← forge an alg:none JWT
│   ├── solve-web1-robots.sh
│   ├── solve-web2-open-redirect.sh
│   ├── solve-web3-sqli.sh
│   ├── solve-web4-coupon.sh
│   ├── solve-web5-glitchy-contact.sh
│   ├── solve-web6-review-idor.sh
│   ├── solve-web7-orders-jwt.sh
│   ├── solve-night-dump.sh
│   ├── solve-proof-stamp.sh
│   ├── solve-trusting-verifier.sh
│   ├── solve-proof-locker.sh
│   └── solve-all.sh                   ← run every solver, summarise flags
└── artifacts/                         ← captures referenced by the writeups
    ├── README.md
    ├── db-schema.sql                  ← recovered via web3 SQLi on sqlite_master
    ├── orders-table-dump.json
    ├── review-table-dump.json
    ├── support-chat-dump.json
    ├── etc-passwd-leak.txt            ← Proof Locker LFI capture
    ├── imds-user-data.sh              ← Trusting Verifier SSRF capture
    └── imds-iam-credentials.json      ← bonus IMDS Token field (unflipped decoy)
```

### Running a solver

```bash
# Single challenge
./scripts/solve-web3-sqli.sh 159.89.230.27

# Everything against one host
./scripts/solve-all.sh 159.89.230.27
```

Most scripts default to `159.89.230.27` if no host is supplied; the named-
challenge solvers (Night Dump, Proof Stamp, Trusting Verifier, Proof Locker)
have a fallback path to the web3 SQLi pivot in case the intended endpoint is
unhealthy on the deployment you're testing against.

Each script prints the flag it recovered on the last line, prefixed `[+] FLAG:`.
