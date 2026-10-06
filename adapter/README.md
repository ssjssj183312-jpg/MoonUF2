# Firmware image adapters

Import `ssjssj183312-jpg/moonuf2/adapter` alongside the root UF2 package.
The adapter uses the attributed upstream source in `../vendor/firmware`.

## Public API

- `intel_hex_to_image(text, family? = None, discard_metadata? = false)`
- `srecord_to_image(text, family? = None, discard_metadata? = false)`
- `image_to_intel_hex(image, record_bytes? = 16, discard_metadata? = false)`
- `image_to_srecord(image, record_bytes? = 32, entry_point? = None, header? = "", discard_metadata? = false)`
- `from_firmware_image(image, family? = None, discard_metadata? = false)`
- `to_firmware_image(image, entry_point? = None, discard_metadata? = false)`

All functions return `Result[..., AdapterError]`. `AdapterError` exposes
`code()`, `message()`, and `line_index()` (zero-based), and retains the original
upstream `FirmwareError` when applicable. Text import rejects bad checksums,
missing terminators, conflicting or repeated metadata, malformed records,
and all data overlaps, including identical repeated bytes.

## Sparse and metadata semantics

Data bytes and their absolute addresses are retained. No gap filling or
implicit zero/0xFF padding occurs. Adjacent source records may canonicalize
into one segment. Emitted record layout, capitalization, line endings, count
records, and extended-address records need not match the input text.

Intel HEX start-address records and S-record entry/header metadata cannot be
represented by the root UF2 `Image`, so import rejects their loss by default.
`discard_metadata=true` explicitly permits data-only conversion. Every
complete S-record document includes a termination address, even if it is
zero; therefore S-record import always requires that explicit choice.

Likewise, the UF2 family ID has no standard HEX/S-record field. Export of an
image containing a family ID rejects by default. With explicit discard,
the bytes are exported but the family ID is lost. A `family` on import is new
caller-supplied metadata, not something recovered from the text.

S-record output requires a termination record. Unless an `entry_point` is
explicitly supplied, the upstream exporter writes termination address zero;
this is not an inferred boot entry. The optional output header is newly
supplied text (up to 64 ASCII bytes). Intel HEX output has no entry point
because the root UF2 `Image` does not contain one. Call the upstream bridge
with an explicit entry point if a caller deliberately needs to add one.

The adapter enforces 32-bit populated address ranges. The root UF2 codec may
apply additional restrictions, including address/payload alignment; the
adapter never silently pads or relocates text data to satisfy those rules.
An export rejects overlapping or empty root-image segments. Intel HEX record
width is 1–255 bytes; S-record data width is 1–250 bytes. The adapter sorts
parsed chunks and root-image segments by address before
calling the vendor canonicalizer. This prevents reverse-ordered records from
causing quadratic insertions; original parser source-line information stays
attached to each chunk. For valid non-overlapping data, canonicalization uses
append-only per-byte storage after sorting. Sparse holes never allocate dense
memory. The raw vendored API does not add this adapter ordering protection.

For HEX → UF2, call `intel_hex_to_image` then root `encode`. For UF2 → HEX,
call root `decode` then `image_to_intel_hex`. S-record follows the equivalent
functions with explicit metadata-loss permission.

## Public resource limits

Both text import functions reject input longer than 16 MiB before invoking
the upstream parser. Valid firmware text is ASCII, so its character length
matches byte length. A linear preflight rejects lines longer than the largest
legal record (521 characters), preventing a huge malformed line from reaching
the upstream string-building line splitter. LF, CRLF and CR source-line
positions are retained.

Every bridge and export path rejects more than 16 MiB of populated data
before normalization. This counts supplied chunk bytes, including overlaps;
sparse address span is not counted. Limit failures have code
`adapter.resource_limit`; an oversized text record has upstream-style code
`record.too_long` and its original zero-based source line. These caps apply to
library callers independently of CLI limits. They bound accepted input and
do not constitute a constant-memory or streaming guarantee. Exported text
can exceed the size of its source bytes.

The 21-test adapter suite passes on native, wasm-gc and JS. In addition to
format validation and sparse round trips, it tests 32,768 reverse-order Intel
HEX data records, 16,384 reverse-order S-record data records, 16,384 reverse
root-image segments, oversized input/data rejection and oversized-line
source positions. Run `moon test adapter --target native` (or `wasm-gc` / `js`).
