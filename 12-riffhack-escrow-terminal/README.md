# RIFFHACK Escrow Terminal

- **Category:** Binary Exploitation
- **Difficulty:** Medium
- **Remote:** `107.170.63.55:1337`
- **Flag:** `bitctf{{35cr0w_n0735_wr173_th3_ch3ck}}`

## Overview

The challenge is a small menu-driven escrow terminal. It lets the user view a
pending marketplace deal, update a buyer note, review that note, synchronize a
dispute cache, and finalize the payout.

The hidden payout routine already exists in the binary, but option 5 only calls
it if the currently active vault has two trusted fields:

- an approval latch set to `0x51ff`
- a mirror/checksum field matching the active vault

The intended path is to notice that the program prepares a trusted second vault
but keeps the untrusted first vault active. A format-string bug in the buyer
note renderer lets us redirect the global active-vault pointer to that prepared
second vault, then finalize the escrow and read the flag.

## Artifact Triage

The handout is a Mach-O ARM64 executable:

```bash
$ file artifacts/escrow_terminal
artifacts/escrow_terminal: Mach-O 64-bit executable arm64
```

On the solve host, direct local execution was not useful and failed with a CPU
type error, so the remote service became the main oracle. Static inspection and
remote menu probing were enough to recover the control flow and exploitation
primitive.

The binary exposes a hidden payout routine that opens `/flag.txt`. Reaching it
requires making the active vault look like the synchronized dispute vault.

## Vulnerability

Menu option 3 reviews the saved buyer note with a direct `printf(note, ...)`
call. The program tries to filter dangerous format strings, but the filter only
blocks a plain `%n` conversion. It misses length-modified writes such as:

```text
%3$hn
```

That matters because the review function passes useful pointers as printf
arguments. One of them points at the global active-vault pointer, and later
arguments leak heap pointers around the active vault. In practice, this gives
both halves of the exploit:

1. leak the current heap layout with positional `%p` specifiers
2. use `%hn` to rewrite the low 16 bits of the active-vault pointer

## Exploitation

The exploit flow is:

1. Choose option 4 to synchronize the dispute cache.
2. The program initializes the second vault, `dispute escrow snapshot`, with the
   required approval latch and mirror checksum.
3. Save a buyer note containing positional pointer leaks:

   ```text
   %3$p %4$p %5$p %6$p %7$p %8$p %9$p %10$p %11$p %12$p %13$p %14$p
   ```

4. Review the note and parse the leaked pointers. A typical useful leak looks
   like `active+7`; subtracting that offset recovers the active-vault base.
5. The second vault sits at `active + 0x28`, so the value we need to write is:

   ```text
   (active + 0x28) & 0xffff
   ```

6. Save a second buyer note:

   ```text
   %2$*1$c%3$hn
   ```

   The note renderer uses the controlled display width as the field width for
   `%2$*1$c`. That prints exactly the number of characters we request. Then
   `%3$hn` writes that character count as a 16-bit halfword into the global
   active-vault pointer.

7. View the pending deal again. The active label changes to
   `dispute escrow snapshot`.
8. Choose option 5 to finalize the escrow. The active vault now satisfies the
   latch and checksum checks, so the payout routine prints the flag.

One successful remote run leaked `0x557376249d87` as `active+7`, giving:

```text
active base:        0x557376249d80
target vault:       0x557376249da8
low 16-bit write:   0x9da8
```

## Solver

The included solver automates the full exploit:

```bash
python3 exploit.py 107.170.63.55 1337
```

It performs the dispute sync, installs a leak format string, derives the target
halfword, installs the write format string, confirms the active vault, and
finalizes the escrow.

The final output contains:

```text
bitctf{{35cr0w_n0735_wr173_th3_ch3ck}}
```

## Root Cause

The note renderer treated user-controlled text as a format string. The attempted
blocklist focused on a single spelling of the `%n` conversion instead of
removing the format-string primitive itself.

Even a better `%n` blocklist would still be fragile here. Positional arguments,
width specifiers, and length modifiers give an attacker too many equivalent
ways to express reads and writes.

## Fix

Render notes with a fixed format string:

```c
printf("%s", note);
```

or use a safer output function such as `fputs`. If formatted rendering is truly
needed, parse and allow-list a small set of harmless formatting features before
calling any printf-family function.

The trust check should also avoid relying on mutable adjacent heap state. The
active object should be selected through explicit state transitions, and the
final payout path should validate that the selected vault was reached through
the expected workflow.

## Files

- `exploit.py` - remote exploit script
- `artifacts/escrow_terminal` - original Mach-O ARM64 handout
