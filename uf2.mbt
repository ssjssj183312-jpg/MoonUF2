///|
/// 稀疏数据段，不执行烧录；编码前检查地址范围。
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
/// block 为从零计数的物理输入块索引；镜像级错误使用 -1。
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
/// 仅支持严格的普通主闪存 UF2。允许内容一致的逻辑块重复出现；
/// 不同逻辑块编号对应的地址范围不得重叠。
pub fn decode(
  data : Bytes,
  expected_family? : UInt? = None,
) -> Result[Image, Uf2Error] {
  if data.length() == 0 || data.length() % 512 != 0 {
    return Err(
      failure("uf2.length", -1, "输入不能为空，长度必须是 512 字节的整数倍"),
    )
  }
  if data.length() > 16777216 {
    return Err(failure("uf2.input_limit", -1, "UF2 输入超过 16 MiB 上限"))
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
      return Err(failure("uf2.magic", i, "UF2 魔数无效"))
    }
    let flags = read32(data, p + 8)
    if flags != 0U && flags != 0x2000U {
      return Err(
        failure(
          "uf2.unsupported_flags",
          i,
          "不支持的标志位：" +
          flags.to_string(radix=16) +
          "；仅支持可选芯片家族标志（0x2000）",
        ),
      )
    }
    let address = read32(data, p + 12)
    let size = read32(data, p + 16)
    if size == 0U || size > 476U {
      return Err(failure("uf2.payload", i, "有效载荷长度必须在 1..476 字节之间"))
    }
    if size % 4U != 0U || address % 4U != 0U {
      return Err(
        failure(
          "uf2.alignment", i, "有效载荷长度和地址必须按 4 字节对齐",
        ),
      )
    }
    if address.to_uint64() + size.to_uint64() > 0x100000000UL {
      return Err(
        failure(
          "uf2.address_overflow", i, "有效载荷超出 32 位地址空间",
        ),
      )
    }
    let no = read32(data, p + 20)
    let count = read32(data, p + 24)
    if count == 0U || no >= count {
      return Err(
        failure(
          "uf2.block_number", i, "numBlocks 必须非零，且 blockNo 必须小于 numBlocks",
        ),
      )
    }
    let f = if flags == 0x2000U { Some(read32(data, p + 28)) } else { None }
    if flags == 0U && read32(data, p + 28) != 0U {
      return Err(
        failure(
          "uf2.reserved", i, "未设置芯片家族标志时，芯片家族/文件大小字段必须为零",
        ),
      )
    }
    if i == 0 {
      total = count
      family = f
    } else {
      if count != total {
        return Err(failure("uf2.block_count", i, "各块的 numBlocks 不一致"))
      }
      if family != f {
        return Err(
          failure("uf2.family", i, "混用了不同芯片家族编号，或家族标志的有无不一致"),
        )
      }
    }
    if expected_family is Some(wanted) {
      if f != Some(wanted) {
        return Err(failure("uf2.family", i, "芯片家族编号与期望值不匹配"))
      }
    }
    let payload = Bytes::makei(size.reinterpret_as_int(), j => data[p + 32 + j])
    match seen.get(no) {
      Some((old_address, old_data)) =>
        if old_address != address || old_data != payload {
          return Err(
            failure(
              "uf2.duplicate_conflict", i, "相同 blockNo 的地址或有效载荷存在冲突",
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
        "uf2.missing_blocks", -1, "缺少一个或多个逻辑块",
      ),
    )
  }
  segments.sort_by((a, b) => a.address.compare(b.address))
  for i = 1; i < segments.length(); i = i + 1 {
    if segments[i].address <
      segments[i - 1].address + segments[i - 1].data.length().to_uint64() {
      return Err(
        failure("uf2.overlap", -1, "不同逻辑块的地址范围重叠"),
      )
    }
  }
  Ok({ segments, family, })
}

///|
/// 先校验并排序列表副本，再编码；不填充稀疏空洞。
pub fn encode(
  image : Image,
  payload_size? : Int = 256,
) -> Result[Bytes, Uf2Error] {
  if payload_size <= 0 || payload_size > 476 || payload_size % 4 != 0 {
    return Err(
      failure("uf2.payload", -1, "有效载荷长度必须在 4..476 之间，且为 4 的倍数"),
    )
  }
  let segments = image.segments.copy()
  segments.sort_by((a, b) => a.address.compare(b.address))
  if segments.is_empty() {
    return Err(failure("image.empty", -1, "镜像必须包含数据"))
  }
  let mut count = 0UL
  for i = 0; i < segments.length(); i = i + 1 {
    let s = segments[i]
    if s.data.length() == 0 {
      return Err(failure("image.empty_segment", -1, "数据段不能为空"))
    }
    if s.address % 4UL != 0UL || s.data.length() % 4 != 0 {
      return Err(
        failure(
          "uf2.alignment", -1, "数据段地址和长度必须按 4 字节对齐；补齐必须由调用者显式完成",
        ),
      )
    }
    if s.address > 0xFFFFFFFFUL ||
      s.data.length().to_uint64() > 0x100000000UL - s.address {
      return Err(
        failure(
          "uf2.address_overflow", -1, "数据段超出 32 位地址空间",
        ),
      )
    }
    if i > 0 &&
      s.address <
      segments[i - 1].address + segments[i - 1].data.length().to_uint64() {
      return Err(failure("uf2.overlap", -1, "数据段地址范围重叠"))
    }
    count = count +
      (s.data.length().to_uint64() + payload_size.to_uint64() - 1UL) /
      payload_size.to_uint64()
  }
  if count > 32768UL {
    return Err(
      failure("uf2.output_limit", -1, "编码后的 UF2 超过 16 MiB 上限"),
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
/// BIN 不保存地址或芯片家族元数据；调用者必须单独保留基址。
pub fn to_bin(
  image : Image,
  max_span? : Int = 16777216,
  fill? : Byte = 0xFF,
) -> Result[Bytes, Uf2Error] {
  let segments = image.segments.copy()
  segments.sort_by((a, b) => a.address.compare(b.address))
  if segments.is_empty() {
    return Err(failure("image.empty", -1, "镜像必须包含数据"))
  }
  let base = segments[0].address
  let mut end = base
  for s in segments {
    if s.data.length() == 0 ||
      s.address > 0xFFFFFFFFUL ||
      s.data.length().to_uint64() > 0x100000000UL - s.address {
      return Err(failure("image.range", -1, "数据段地址范围无效"))
    }
    if s.address < end {
      return Err(failure("uf2.overlap", -1, "数据段地址范围重叠"))
    }
    end = s.address + s.data.length().to_uint64()
  }
  if max_span <= 0 ||
    end - base > max_span.to_uint64() ||
    end - base > 16777216UL {
    return Err(
      failure(
        "bin.span_limit", -1, "BIN 地址跨度超过调用者设置的上限或 16 MiB 硬上限",
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
    return Err(failure("image.empty", -1, "BIN 输入不能为空"))
  }
  if data.length() > 16777216 {
    return Err(failure("bin.input_limit", -1, "BIN 输入超过 16 MiB 上限"))
  }
  if base > 0xFFFFFFFFUL || data.length().to_uint64() > 0x100000000UL - base {
    return Err(failure("uf2.address_overflow", -1, "BIN 数据超出地址空间"))
  }
  if base % 4UL != 0UL || data.length() % 4 != 0 {
    return Err(
      failure(
        "uf2.alignment", -1, "BIN 基址和长度必须按 4 字节对齐；不会隐式补齐",
      ),
    )
  }
  Ok({ segments: [{ address: base, data, }], family, })
}
