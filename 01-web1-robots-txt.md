# web1 — Robots.txt Courtesy

> *The marketplace tried to politely hide one operator scrap from search
> engines. Courtesy files are not access control, and crawlers are not the
> only ones who can read them.*

**Category:** Web / recon
**Flag:** `bitflag{r0b0ts_4r3_n0t_4_s3cr3t_v4ult}`

## The brief, in plain English

The hint does most of the work. "Polite courtesy file" + "hide from search
engines" maps to exactly one file on a web server: `robots.txt`. Once you read
the hint that way, the challenge is essentially "read the file, follow the
breadcrumb".

## Recon

First request, before anything else:

```bash
$ curl -s http://159.89.230.27/robots.txt
User-Agent: *
Allow: /
Disallow: /operator-cache-drop
```

A single `Disallow` rule. The whole point of putting a path in a `Disallow`
line is to *tell well-behaved crawlers not to fetch it*. That is the entire
contract — there is no authorization, no token, no rate limit, no IP check. A
crawler that respects the file will skip the URL; a human reading the file in
a browser sees a hyperlink-shaped invitation.

## Exploitation

The URL is just a URL. Fetch it:

```bash
$ curl -s http://159.89.209.27/operator-cache-drop | grep -oE 'bitflag\{[^}]+\}'
bitflag{r0b0ts_4r3_n0t_4_s3cr3t_v4ult}
```

The page renders an "Operator Cache / Crawler quarantine bucket" panel with
the flag printed verbatim in a `<p>` tag. It even includes
`<meta name="robots" content="noindex">` in the page head — a second
"please don't index me" hint that is, again, only a request, not an access
control.

## Root cause

Two layers of the same misconception:

1. **`robots.txt` is a hint to crawlers, not a permission system.** It exists
   to prevent search engines from wasting bandwidth on resources you'd rather
   not have indexed. It is delivered unauthenticated, in cleartext, *to
   everyone who asks*. Anyone curious about what a site is trying to hide
   reads `robots.txt` first.
2. **`<meta name="robots" content="noindex">` has the same property.** It
   tells Googlebot not to put the URL in search results. It does not tell
   anyone *with the URL* not to load it.

Stacking these two "polite request" controls produces a page that is invisible
to search engines and trivially obvious to humans — the opposite of the
intended effect.

## Mitigation

If a page genuinely shouldn't be reached by unauthorized callers:

- Put it behind authentication and authorization (sessions, tokens, role
  checks). The check happens on every request, not in a file the requester is
  free to ignore.
- Don't list "secret" paths in `robots.txt`. If a path needs hiding, the
  presence of the path itself is the leak. Disallow a broader, less
  interesting prefix, or put the resource on an entirely different hostname
  with its own access controls.
- Treat `noindex` and `nofollow` as SEO hygiene only. They never participate
  in security boundaries.

## Takeaways

- **Courtesy ≠ access control.** It is the literal first lesson of web
  security. The hint phrases it as "courtesy files are not access control",
  which is exactly the canonical formulation.
- **Signposting is a leak.** A `Disallow` entry is one of the loudest ways to
  advertise an interesting URL.
- **Pair with web2.** Web1 and web2 both teach the same root lesson on
  different surfaces: trusting a piece of client-side or in-protocol metadata
  to enforce a server-side boundary. Web1 leaks via `robots.txt`; web2 leaks
  via an OAuth-style trusted-return-URL flow.

## One-liner

```bash
curl -s http://<host>/operator-cache-drop | grep -oE 'bitflag\{[^}]+\}'
```
