# Artifacts

Raw outputs captured while solving the riffhack challenges. Each file is the
verbatim response body from the relevant exploit primitive, useful both for
verifying the writeups and as reference data when the live host is unhealthy.

Provenance: all artifacts were captured live from `134.209.117.21` during the
follow-up "The Hidden Offer Hunt" investigation on **2026-06-21**, with the
exception of the schema (which is a transcription of the `sqlite_master`
dump). The marketplace re-seeds its database periodically, so timestamps in
the dumps will not survive a reseed — the row IDs and column values do.

| File | Captured via | Notes |
|------|--------------|-------|
| `db-schema.sql` | web3 SQLi → `sqlite_master` | The complete relational schema (5 tables). No `Listing` / `WantedListing` table — those are hardcoded in client chunks / generated on-the-fly. |
| `orders-table-dump.json` | web3 SQLi `' OR 1=1 --` on `/api/orders/lookup` | All three `Order` rows including the `status:"hidden"` row that hides web3's flag. |
| `review-table-dump.json` | web3 SQLi UNION on `Review WHERE moderationNote IS NOT NULL` | The three seeded reviews. `seed-phantom-hacker` is the web6 target. |
| `support-chat-dump.json` | web3 SQLi UNION on `SupportChatMessage` | One seeded admin row whose `internalNote` is the Night Dump flag. |
| `etc-passwd-leak.txt` | Proof Locker LFI on `?proof=../../../../etc/passwd` | The last line is the `opsflag` user record carrying the flag in its GECOS field. |
| `imds-user-data.sh` | SSRF on `?website=http://169.254.169.254/latest/user-data` | Mocked AWS IMDSv1 user-data bootstrap script. The `TRUSTING_VERIFIER_FLAG` env var is the Trusting Verifier flag. |
| `imds-iam-credentials.json` | SSRF on `?website=http://169.254.169.254/latest/meta-data/iam/security-credentials/RiffhackVendorVerifierRole` | Mocked IAM role credentials. The `Token` field is the unflipped riffhack web5 decoy. |

## Reproducing

Each file can be regenerated against a healthy deployment by running the
corresponding `scripts/solve-*.sh`. The Trusting Verifier and Proof Locker
scripts dump the relevant artifact directly to stdout as part of the solve.
