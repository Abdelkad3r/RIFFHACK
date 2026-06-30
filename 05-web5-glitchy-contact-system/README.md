# web5 — The Glitchy Contact System

> *Something in the marketplace isn't working quite right. Those who dig
> deeper find more than they bargained for.*

**Category:** Web — SSR data leak via client-component error throw
**Flag:** `bitflag{d3bug_m0d3_1s_d4ng3r0us}`

## The brief, in plain English

The `/contact` page looks blank. It looks blank because, on mount, the
component deliberately throws a debug `Error` whose message contains the flag
— and as with web4, the value the component throws is a server-supplied prop
that the framework already wrote into the SSR payload.

The lesson is in the *title*: "Glitchy Contact System" decodes one-to-one to
"the contact component is broken on purpose, and that's where the flag is".

## The misdirection

I should be upfront: this challenge ate four hours of my time before I
solved it, because the marketplace is salted with flag-shaped strings — every
"real" web-app primitive I tried produced a *real* flag-shaped value, and
none of them were the right answer for web5.

The decoys I chased and rejected:

1. `bitflag{w3bs0ck3t_upgr4d3_ssrf_2026}` — reached via SSRF on
   `POST /api/vendor/verify-website` against
   `http://169.254.169.254/latest/meta-data/iam/security-credentials/RiffhackVendorVerifierRole`.
2. `bitflag{ssrf_1s_4_p4rty_cr4sh3r}` — reached via the same SSRF against
   `latest/user-data`, where the env var
   `TRUSTING_VERIFIER_FLAG=<flag>` is exported in a bootstrap script.
3. `bitflag{3xp0rts_sh0uld_n0t_b3_0p3n_b00ks}` — reached by pivoting the
   web3 SQLi into `SupportChatMessage.internalNote`.
4. `bitflag{jwt_5h4ll_n0t_p455}` — reached by alg:none-forging
   `isVendor:true` and reading the "Vendor Token" widget on `/vendor`.

Every single one of these is *also* a real flag for *some* riffhack-codebase
challenge. They're real bugs reaching real values; they're not the right
*here*. The CTF author's design choice — re-using the codebase across multiple
events with the same baked-in strings — turns each rabbit hole into a usable
exploit chain, but the brief you're handed determines which one is the
answer.

I lay this out because the four decoys collectively are the lesson of web5.
*If a challenge has more than one plausible exploit and they each surface a
flag-shaped value, you can be in for a long afternoon if you assume the first
working primitive is the intended one.* Read the brief again, then again.

## The real path

The `/contact` page (linked in the site footer) returns 200 with an
apparently empty `<main>`:

```html
<main><!--$--><!--/$--><!--$--><!--/$--></main>
```

If you only look at the rendered DOM, that's the whole story. The page
appears broken — a "glitch". Open the bundle the page loads:

```
/_next/static/chunks/app/contact/page-7048680aa688442f.js
```

The bundle is 422 bytes. The entire client component:

```js
function i(e) {
  let { flag: t } = e;
  return (0, r.useEffect)(() => {
    throw Error(
      "Contact service initialization failed: missing transporter config. FLAG=".concat(t)
    );
  }, [t]), null;
}
```

On mount: throw an `Error` with a debug message that includes the `flag`
prop, then return `null`. The thrown error is what makes the page appear
blank. The component never renders anything.

But — same shape as web4 — the `flag` prop was serialised by the server into
the page's RSC payload before the client component ever tried to mount:

```bash
$ curl -s http://159.89.230.27/contact | grep -oE 'bitflag\{[^}]+\}'
bitflag{d3bug_m0d3_1s_d4ng3r0us}
```

You don't need to wait for the JavaScript to throw, or look in the dev-tools
error console, or anything else. The value is in the HTML.

## Root cause

Same root cause as web4, in a slightly different costume:

- A **server component** generates the `flag` prop.
- It passes that prop to a **client component**.
- The framework serialises the prop into the HTML so the client component
  can hydrate.
- The client component is irrelevant — the value already shipped.

The "debug error" wrapping is the cherry on top. In production code the
equivalent looks like:

```js
console.error(`User auth failed: token=${token}`);
throw new Error(`DB connect failed: ${connectionString}`);
```

— error messages with PII or secrets baked in. Every error logger, every
crash reporter, every browser dev-tools console catches these and persists
them somewhere. The CTF dramatises it; real-world incidents look identical.

## Mitigation

- **Don't put secrets in client component props.** Server components can
  read secrets; the moment a value crosses into a client component, it is
  on the wire and in the HTML.
- **Don't put secrets in error messages.** Errors are the most-logged,
  most-shipped, most-shared piece of program state. Treat any
  `Error("…${variable}…")` as a candidate exfil channel.
- **Strip debug strings from production builds.** The `Contact service
  initialization failed: missing transporter config. FLAG=…` literal is the
  kind of thing that should never survive a release-build pass.

## Takeaways

- **Read the title first.** "Glitchy Contact System" mapped 1:1 to the
  surface (the `/contact` client component throws on mount). I treated it as
  flavour text and spent four hours on misdirections instead.
- **Same class as web4.** Both put a win-state secret into a React server
  prop. The whole event has a small handful of recurring lessons replayed
  across surfaces; learn them once and the rest gets fast.
- **The misdirection itself is the lesson.** A marketplace that's deliberately
  salted with flag-shaped decoy values is excellent training for resisting
  the "I found *a* flag, this must be *the* flag" instinct. Match the brief
  to the surface, not the value to the format.

## One-liner

```bash
curl -s http://<host>/contact | grep -oE 'bitflag\{[^}]+\}'
```

That is the entire exploit.

## Decoy index — what each rejected value really points to

| Decoy value | Real flag for |
|---|---|
| `bitflag{w3bs0ck3t_upgr4d3_ssrf_2026}` | (unflipped — no public challenge yet) |
| `bitflag{ssrf_1s_4_p4rty_cr4sh3r}` | [The Trusting Verifier](../10-the-trusting-verifier/README.md) |
| `bitflag{3xp0rts_sh0uld_n0t_b3_0p3n_b00ks}` | [The Night Dump](../08-the-night-dump/README.md) |
| `bitflag{jwt_5h4ll_n0t_p455}` | boroCTF "Vendor's Secret Door" |
| `bitflag{md5_1s_br0k3n_l1k3_my_h34rt}` | [The Proof Stamp](../09-the-proof-stamp/README.md) |

Treat the "decoy" label as scoped to *this* challenge only. Across the suite,
nearly every decoy turns out to be someone else's real answer.
