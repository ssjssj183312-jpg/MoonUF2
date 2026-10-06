///|
/// A non-flashing sparse image. Addresses are checked before encoding.
pub(all) struct Segment {
  address : UInt64
  data : Bytes
} derive(Eq, Debug)

///|
pub(all) struct Image {
  segments : Array[Segment]
  family : UInt?
} derive(Eq, Debug)

///|
/// block is the physical input block index, or -1 for image-level errors.
pub(all) struct Uf2Error {
  code : String
  block : Int
  message : String
} derive(Eq, Debug)

///|
fn failure(code : String, block : Int, message : String) -> Uf2Error {
  { code, block, message, }
}

///|
fn read32(data : Bytes, at : Int) -> UInt {
  data[at].to_uint() |
  (data[at + 1].to_uint() << 8) |
  (data[at + 2].to_uint() << 16) |
  (data[at + 3].to_uint() << 24)
}

///|
fn write32(data : FixedArray[Byte], at : Int, value : UInt) -> Unit {
  for i = 0; i < 4; i = i + 1 {
    data[at + i] = (value >> (i * 8)).to_byte()
  }
}

///|
/// Strict ordinary main-flash UF2 only. Repeated identical logical blocks
/// are tolerated; different block numbers may never overlap addresses.
pub fn decode(
  data : Bytes,
  expected_family? : UInt? = None,
) -> Result[Image, Uf2Error] {
  if data.length() == 0 || data.length() % 512 != 0 {
    return Err(
      failure("uf2.length", -1, "expected nonempty multiple of 512 bytes"),
    )
  }
  if data.length() > 16777216 {
    return Err(failure("uf2.input_limit", -1, "UF2 exceeds 16 MiB input limit"))
  }
  let seen : Map[UInt, (UInt, Bytes)] = Map([])
  let segments : Array[Segment] = []
  let mut total = 0U
  let mut family : UInt? = None
  for i = 0; i < data.length() / 512; i = i + 1 {
    let p = i * 512
    if read32(data, p) != 0x0A324655U ||
      read32(data, p + 4) != 0x9E5D5157U ||
      read32(data, p + 508) != 0x0AB16F30U {
      return Err(failure("uf2.magic", i, "invalid UF2 magic"))
    }
    let flags = read32(data, p + 8)
    if flags != 0U && flags != 0x2000U {
      return Err(
        failure(
          "uf2.unsupported_flags",
          i,
          "unsupported flags: " +
          flags.to_string(radix=16) +
          "; only optional family ID (0x2000) is supported",
        ),
      )
    }
    let address = read32(data, p + 12)
    let size = read32(data, p + 16)
    if size == 0U || size > 476U {
      return Err(failure("uf2.payload", i, "payload must be 1..476 bytes"))
    }
    if size % 4U != 0U || address % 4U != 0U {
      return Err(
        failure(
          "uf2.alignment", i, "payload size and address must be 4-byte aligned",
        ),
      )
    }
    if address.to_uint64() + size.to_uint64() > 0x100000000UL {
      return Err(
        failure(
          "uf2.address_overflow", i, "payload extends past 32-bit address space",
        ),
      )
    }
    let no = read32(data, p + 20)
    let count = read32(data, p + 24)
    if count == 0U || no >= count {
      return Err(
        failure(
          "uf2.block_number", i, "blockNo must be less than nonzero numBlocks",
        ),
      )
    }
    let f = if flags == 0x2000U { Some(read32(data, p + 28)) } else { None }
    if flags == 0U && read32(data, p + 28) != 0U {
      return Err(
        failure(
          "uf2.reserved", i, "family/file-size field must be zero without family flag",
        ),
      )
    }
    if i == 0 {
      total = count
      family = f
    } else {
      if count != total {
        return Err(failure("uf2.block_count", i, "inconsistent numBlocks"))
      }
      if family != f {
        return Err(
          failure("uf2.family", i, "mixed family IDs or mixed family presence"),
        )
      }
    }
    if expected_family is Some(wanted) {
      if f != Some(wanted) {
        return Err(failure("uf2.family", i, "expected family does not match"))
      }
    }
    let payload = Bytes::makei(size.reinterpret_as_int(), j => data[p + 32 + j])
    match seen.get(no) {
      Some((old_address, old_data)) =>
        if old_address != address || old_data != payload {
          return Err(
            failure(
              "uf2.duplicate_conflict", i, "same blockNo has conflicting address or payload",
            ),
          )
        }
      None => {
        seen[no] = (address, payload)
        segments.push({ address: address.to_uint64(), data: payload, })
      }
    }
  }
  if seen.length().reinterpret_as_uint() != total {
    return Err(
      failure(
        "uf2.missing_blocks", -1, "one or more logical blocks are missing",
      ),
    )
  }
  segments.sort_by((a, b) => a.address.compare(b.address))
  for i = 1; i < segments.length(); i = i + 1 {
    if segments[i].address <
      segments[i - 1].address + segments[i - 1].data.length().to_uint64() {
      return Err(
        failure("uf2.overlap", -1, "different blocks overlap address ranges"),
      )
    }
  }
  Ok({ segments, family, })
}

///|
/// Validate, sort a copy, and encode without filling sparse gaps.
pub fn encode(
  image : Image,
  payload_size? : Int = 256,
) -> Result[Bytes, Uf2Error] {
  if payload_size <= 0 || payload_size > 476 || payload_size % 4 != 0 {
    return Err(
      failure("uf2.payload", -1, "payload size must be aligned and in 4..476"),
    )
  }
  let segments = image.segments.copy()
  segments.sort_by((a, b) => a.address.compare(b.address))
  if segments.is_empty() {
    return Err(failure("image.empty", -1, "image must contain data"))
  }
  let mut count = 0UL
  for i = 0; i < segments.length(); i = i + 1 {
    let s = segments[i]
    if s.data.length() == 0 {
      return Err(failure("image.empty_segment", -1, "empty segment"))
    }
    if s.address % 4UL != 0UL || s.data.length() % 4 != 0 {
      return Err(
        failure(
          "uf2.alignment", -1, "segment addresses and lengths must be 4-byte aligned; padding must be explicit",
        ),
      )
    }
    if s.address > 0xFFFFFFFFUL ||
      s.data.length().to_uint64() > 0x100000000UL - s.address {
      return Err(
        failure(
          "uf2.address_overflow", -1, "segment exceeds 32-bit address space",
        ),
      )
    }
    if i > 0 &&
      s.address <
      segments[i - 1].address + segments[i - 1].data.length().to_uint64() {
      return Err(failure("uf2.overlap", -1, "segments overlap"))
    }
    count = count +
      (s.data.length().to_uint64() + payload_size.to_uint64() - 1UL) /
      payload_size.to_uint64()
  }
  if count > 32768UL {
    return Err(
      failure("uf2.output_limit", -1, "encoded UF2 exceeds 16 MiB limit"),
    )
  }
  let out = FixedArray::make(count.to_int() * 512, (0).to_byte())
  let mut no = 0
  for s in segments {
    let mut offset = 0
    while offset < s.data.length() {
      let n = if payload_size < s.data.length() - offset {
        payload_size
      } else {
        s.data.length() - offset
      }
      let p = no * 512
      write32(out, p, 0x0A324655U)
      write32(out, p + 4, 0x9E5D5157U)
      write32(out, p + 8, if image.family is Some(_) { 0x2000U } else { 0U })
      write32(out, p + 12, (s.address + offset.to_uint64()).to_uint())
      write32(out, p + 16, n.reinterpret_as_uint())
      write32(out, p + 20, no.reinterpret_as_uint())
      write32(out, p + 24, count.to_uint())
      write32(out, p + 28, image.family.unwrap_or(0U))
      write32(out, p + 508, 0x0AB16F30U)
      for j = 0; j < n; j = j + 1 {
        out[p + 32 + j] = s.data[offset + j]
      }
      offset = offset + n
      no = no + 1
    }
  }
  Ok(Bytes::makei(out.length(), i => out[i]))
}

///|
/// BIN has no address or family metadata; caller must retain base separately.
pub fn to_bin(
  image : Image,
  max_span? : Int = 16777216,
  fill? : Byte = 0xFF,
) -> Result[Bytes, Uf2Error] {
  let segments = image.segments.copy()
  segments.sort_by((a, b) => a.address.compare(b.address))
  if segments.is_empty() {
    return Err(failure("image.empty", -1, "image must contain data"))
  }
  let base = segments[0].address
  let mut end = base
  for s in segments {
    if s.data.length() == 0 ||
      s.address > 0xFFFFFFFFUL ||
      s.data.length().to_uint64() > 0x100000000UL - s.address {
      return Err(failure("image.range", -1, "invalid segment range"))
    }
    if s.address < end {
      return Err(failure("uf2.overlap", -1, "segments overlap"))
    }
    end = s.address + s.data.length().to_uint64()
  }
  if max_span <= 0 ||
    end - base > max_span.to_uint64() ||
    end - base > 16777216UL {
    return Err(
      failure(
        "bin.span_limit", -1, "BIN span exceeds caller limit or 16 MiB hard limit",
      ),
    )
  }
  let out = FixedArray::make((end - base).to_int(), fill)
  for s in segments {
    for i = 0; i < s.data.length(); i = i + 1 {
      out[(s.address - base).to_int() + i] = s.data[i]
    }
  }
  Ok(Bytes::makei(out.length(), i => out[i]))
}

///|
pub fn from_bin(
  data : Bytes,
  base : UInt64,
  family? : UInt? = None,
) -> Result[Image, Uf2Error] {
  if data.length() == 0 {
    return Err(failure("image.empty", -1, "BIN must be nonempty"))
  }
  if data.length() > 16777216 {
    return Err(failure("bin.input_limit", -1, "BIN exceeds 16 MiB input limit"))
  }
  if base > 0xFFFFFFFFUL || data.length().to_uint64() > 0x100000000UL - base {
    return Err(failure("uf2.address_overflow", -1, "BIN exceeds address space"))
  }
  if base % 4UL != 0UL || data.length() % 4 != 0 {
    return Err(
      failure(
        "uf2.alignment", -1, "BIN base and length must be 4-byte aligned; no implicit padding",
      ),
    )
  }
  Ok({ segments: [{ address: base, data, }], family, })
}
