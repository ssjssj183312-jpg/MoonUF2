# Vendored firmware-image-toolkit subset

- Author and copyright holder: 张泉义 (Zzqy-yi)
- Project: https://github.com/Zzqy-yi/moonbit-firmware-image
- Original module: `Zzqy-yi/firmware-image-toolkit`
- Revision: `cd34551136a5c2663af48634ebc72d8ce8b6a8c0`
- License: Apache-2.0; the original `LICENSE` and `NOTICE` are included verbatim
- Local package: `ssjssj183312-jpg/moonuf2/vendor/firmware`

This directory contains the smallest independent source subset needed by the
MoonUF2 adapter: the Intel HEX and Motorola S-record codecs and documents,
sparse FirmwareImage and FirmwareChunk types, diagnostics, checksums, line
splitting, and text exporters. The ten `.mbt` files are copied byte-for-byte
from the revision above. `docs/references.md` is also copied unchanged.
`SHA256SUMS` records these copies; `sha256sum -c SHA256SUMS` verifies them.

The local `moon.pkg`, this provenance file, and `SHA256SUMS` are MoonUF2
packaging additions. They do not imply that the upstream author maintains or
endorses MoonUF2. No upstream code has been rewritten or relabeled as original
MoonUF2 implementation. Higher-level upstream auditing/reporting APIs and
its examples and test suite are intentionally omitted; this is not a full
mirror of the upstream module.

## Integration behavior

The upstream image model stores only bytes at present addresses; gaps do not
allocate memory. Its canonicalizer inserts individual bytes into sorted
arrays, so reverse-ordered records can be quadratic in populated byte count.
The adapters deliberately do not fill gaps, reinterpret addresses, or enable
replacement of overlapping bytes.

The adapter checks 32-bit data ranges before accepting or emitting a MoonUF2
image. This supplements upstream S-record parsing, which can parse a record
starting below 2^32 whose payload crosses that bound. The upstream sources
remain unchanged.
