# RIFFHACK — Web Challenge Writeups

These are my writeups for the **riffhack** event — a CTF built around a fictional
Next.js "exploit kit marketplace" called *riffhack // exploit kit marketplace*. The
site is themed as a darknet storefront for offensive tooling. Every challenge
plants its bug somewhere in that codebase, and the flag format is `bitflag{...}`
(single braces — not to be confused with bitctf's literal-doubled `bitctf{{...}}`).

Eleven challenges are solved and documented here, in roughly the order I worked
through them. Each challenge gets its own folder containing the writeup
(`README.md`), a runnable solver (`solve.sh`), and — where I captured anything
worth keeping — an `artifacts/` directory with the raw exploit output.

## Contents

### Core web track

| # | Challenge | Class | Flag |
|---|-----------|-------|------|
| 1 | [Robots.txt Courtesy](01-web1-robots-txt/README.md) | Recon | `bitflag{r0b0ts_4r3_n0t_4_s3cr3t_v4ult}` |
| 2 | [The Trusting Login Desk](02-web2-open-redirect/README.md) | Open redirect → token leak | `bitflag{tru5t3d_r3d1r3cts_c4n_c4rry_s3cr3ts}` |
| 3 | [Buyer Lookup Loose Query](03-web3-sqli-orders-lookup/README.md) | SQL injection | `bitflag{1nj3ct10n_turn5_4_l00kup_1nt0_4_l34k}` |
| 4 | [Coupon Stacking](04-web4-coupon-stacking/README.md) | SSR prop leak | `bitflag{c0up0n_st4ck1ng_1s_4_d34l}` |
| 5 | [The Glitchy Contact System](05-web5-glitchy-contact-system/README.md) | SSR prop leak via error throw | `bitflag{d3bug_m0d3_1s_d4ng3r0us}` |
| 6 | [Marketplace Reviews Look Tidy](06-web6-review-idor/README.md) | IDOR (URL-path id) | `bitflag{r3v13w_0wn3r5h1p_1s_n0t_4_sugg35t10n}` |
| 7 | [Order History Should Be Private](07-web7-orders-jwt-idor/README.md) | JWT `alg:none` + IDOR | `bitflag{1d0r_1s_4_d4ng3r0us_g4m3}` |

### Named challenges (cross-event / extended track)

| # | Challenge | Class | Flag |
|---|-----------|-------|------|
| 8 | [The Night Dump](08-the-night-dump/README.md) | Over-scoped diagnostic export | `bitflag{3xp0rts_sh0uld_n0t_b3_0p3n_b00ks}` |
| 9 | [The Proof Stamp](09-the-proof-stamp/README.md) | Server-stamped fake-proof | `bitflag{md5_1s_br0k3n_l1k3_my_h34rt}` |
| 10 | [The Trusting Verifier](10-the-trusting-verifier/README.md) | SSRF → IMDS user-data | `bitflag{ssrf_1s_4_p4rty_cr4sh3r}` |
| 11 | [The Proof Locker](11-the-proof-locker/README.md) | Path traversal → LFI | `bitflag{pr00f_p4ths_5h0uld_st4y_1n_b0unds}` |

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
├── README.md                              ← you are here
├── solve-all.sh                           ← run every solver, summarise flags
├── lib/
│   ├── login.sh                           ← get an auth-token cookie (any creds)
│   └── jwt-none.sh                        ← forge an alg:none JWT
├── 01-web1-robots-txt/
│   ├── README.md                          ← writeup
│   └── solve.sh
├── 02-web2-open-redirect/
│   ├── README.md
│   └── solve.sh
├── 03-web3-sqli-orders-lookup/
│   ├── README.md
│   ├── solve.sh
│   └── artifacts/
│       ├── db-schema.sql                  ← recovered via sqlite_master SQLi
│       └── orders-table-dump.json
├── 04-web4-coupon-stacking/
│   ├── README.md
│   └── solve.sh
├── 05-web5-glitchy-contact-system/
│   ├── README.md
│   └── solve.sh
├── 06-web6-review-idor/
│   ├── README.md
│   ├── solve.sh
│   └── artifacts/
│       └── review-table-dump.json         ← seed Reviews (web7 pivot too)
├── 07-web7-orders-jwt-idor/
│   ├── README.md
│   └── solve.sh
├── 08-the-night-dump/
│   ├── README.md
│   ├── solve.sh
│   └── artifacts/
│       └── support-chat-dump.json
├── 09-the-proof-stamp/
│   ├── README.md
│   └── solve.sh
├── 10-the-trusting-verifier/
│   ├── README.md
│   ├── solve.sh
│   └── artifacts/
│       ├── imds-user-data.sh              ← Trusting Verifier flag (env var)
│       └── imds-iam-credentials.json      ← bonus Token field (unflipped decoy)
└── 11-the-proof-locker/
    ├── README.md
    ├── solve.sh
    └── artifacts/
        └── etc-passwd-leak.txt            ← opsflag GECOS line at bottom
```

## Running

```bash
# Single challenge
./03-web3-sqli-orders-lookup/solve.sh 159.89.230.27

# Every challenge against one host
./solve-all.sh 159.89.230.27
```

Most solvers default to `159.89.230.27` if no host is supplied. The named-
challenge solvers (Night Dump, Proof Stamp) include a fallback to the web3
SQLi pivot in case the intended endpoint is unhealthy on the deployment
you're testing against.

Every script prints the recovered flag on the last line, prefixed
`[+] FLAG: bitflag{...}`.
