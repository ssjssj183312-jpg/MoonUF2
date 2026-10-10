///|
/// 转换错误会保留上游解析器的诊断信息。除非调用方显式设置
/// `discard_metadata=true`，否则拒绝会丢失元数据的转换。
pub(all) enum AdapterError {
  Firmware(@firmware.FirmwareError)
  MetadataLoss(String)
  InvalidImage(String)
  ResourceLimit(String)
} derive(Eq, Debug)

///|
pub fn AdapterError::code(self : AdapterError) -> String {
  match self {
    Firmware(error) => error.code()
    MetadataLoss(_) => "adapter.metadata_loss"
    InvalidImage(_) => "adapter.invalid_image"
    ResourceLimit(_) => "adapter.resource_limit"
  }
}

///|
/// 为上游错误码提供中文概括。结构化 FirmwareError 仍保留原始诊断信息，
/// 普通消息不直接输出上游英文；新增或未知错误码使用中文兜底提示。
fn firmware_error_message(error : @firmware.FirmwareError) -> String {
  match error.code() {
    "hex.odd_length" => "十六进制字符数量必须为偶数"
    "hex.invalid_digit" => "包含无效的十六进制字符"
    "record.empty" => "固件记录不能为空"
    "record.invalid_prefix" => "固件记录的起始标记无效"
    "record.invalid_type" => "固件记录类型无效或不受支持"
    "record.length_mismatch" => "记录声明的数据长度与实际长度不符"
    "record.too_long" => "固件记录超过允许的长度上限"
    "checksum.mismatch" => "固件记录的校验和不匹配"
    "address.out_of_range" => "固件记录地址超出允许范围"
    "image.overlap" => "固件数据地址重叠，即使内容相同也不允许"
    "image.invalid_range" => "镜像范围或导出参数无效"
    "integrity.violation" => "固件记录的计数或结构不一致"
    "document.missing_terminator" => "固件文档缺少必需的结束记录"
    "document.record_after_terminator" => "固件文档的结束记录后仍有其他记录"
    "document.duplicate_metadata" => "固件元数据记录重复或顺序不合法"
    _ => "固件处理失败，请根据错误代码检查输入"
  }
}

///|
pub fn AdapterError::message(self : AdapterError) -> String {
  match self {
    Firmware(error) =>
      firmware_error_message(error) +
      "（源文件第 " +
      (error.line_index() + 1).to_string() +
      " 行）"
    MetadataLoss(message) | InvalidImage(message) | ResourceLimit(message) =>
      message
  }
}

///|
/// 如果存在解析错误，返回其原始源文件行号；行号从零开始。
pub fn AdapterError::line_index(self : AdapterError) -> Int? {
  match self {
    Firmware(error) => Some(error.line_index())
    _ => None
  }
}

///|
fn check_range(address : UInt64, length : Int) -> Result[Unit, AdapterError] {
  if address > 0xFFFFFFFFUL || length.to_uint64() > 0x100000000UL - address {
    Err(InvalidImage("数据范围超出 32 位 UF2 地址空间"))
  } else {
    Ok(())
  }
}

///|
/// 所有公开适配接口均将实际数据量限制为 16 MiB。有效固件文本使用 ASCII，
/// 在解析前将其输入长度限制为 16 MiB。
fn check_byte_budget(
  current : Int,
  additional : Int,
) -> Result[Int, AdapterError] {
  if additional > 16777216 - current {
    Err(ResourceLimit("镜像的实际数据量超出适配层的 16 MiB 上限"))
  } else {
    Ok(current + additional)
  }
}

///|
fn check_text_budget(text : String) -> Result[Unit, AdapterError] {
  if text.length() > 16777216 {
    return Err(
      ResourceLimit("固件文本超出适配层的 16 MiB 输入上限"),
    )
  }
  // 在上游分行器复制、拼接文本前，先限制需要处理的单行长度。
  // 最长的有效 Intel HEX 记录包含 521 个 ASCII 字符，S-record 记录更短。
  // 保留原始源文件行号，不改变上游诊断的位置。
  let mut line_length = 0
  let mut line_index = 0
  let mut was_cr = false
  for index = 0; index < text.length(); index = index + 1 {
    let code = text[index].to_int()
    if code == 13 || code == 10 {
      if code == 13 || !was_cr {
        line_index = line_index + 1
      }
      was_cr = code == 13
      line_length = 0
    } else {
      was_cr = false
      // 上游按 UTF-16 码元分行时会丢弃代理码元；先拒绝非 ASCII，防止修复坏输入。
      if code > 127 {
        return Err(
          Firmware(
            @firmware.FirmwareError::new(
              @firmware.HexInvalidDigit,
              "HEX/S-record input must contain ASCII characters only",
              @firmware.SourcePosition::column(line_index, line_length),
            ),
          ),
        )
      }
      line_length = line_length + 1
      if line_length > 521 {
        return Err(
          Firmware(
            @firmware.FirmwareError::new(
              @firmware.RecordTooLong,
              "固件文本单行长度超出记录允许的 521 字符上限",
              @firmware.SourcePosition::line(line_index),
            ),
          ),
        )
      }
    }
  }
  Ok(())
}

///|
fn normalize_chunks(
  chunks : Array[@firmware.FirmwareChunk],
  entry_point : UInt64?,
) -> Result[@firmware.FirmwareImage, AdapterError] {
  let mut populated = 0
  for chunk in chunks {
    match check_range(chunk.address(), chunk.length()) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    populated = match check_byte_budget(populated, chunk.length()) {
      Err(error) => return Err(error)
      Ok(total) => total
    }
  }
  // 排序时保留每个数据块的原始源文件行号，避免逆序、互不重叠的记录
  // 在逐字节插入数组时产生平方级时间开销。
  chunks.sort_by((left, right) => left.address().compare(right.address()))
  match @firmware.FirmwareImage::from_chunks(chunks, entry_point~) {
    Err(error) => Err(Firmware(error))
    Ok(image) => Ok(image)
  }
}

///|
/// 将已有的上游稀疏镜像转换为 UF2 镜像，不填充地址空洞。
/// 可选的 family 是调用方新提供的 UF2 元数据，上游模型不包含芯片家族 ID。
/// 丢弃入口地址元数据必须获得调用方的显式许可。
pub fn from_firmware_image(
  image : @firmware.FirmwareImage,
  family? : UInt? = None,
  discard_metadata? : Bool = false,
) -> Result[@uf2.Image, AdapterError] {
  if image.entry_point() is Some(_) && !discard_metadata {
    return Err(
      MetadataLoss(
        "UF2 无法保留固件入口地址；如需继续，请显式启用 discard_metadata",
      ),
    )
  }
  let segments : Array[@uf2.Segment] = []
  let mut populated = 0
  for segment in image.segments() {
    populated = match check_byte_budget(populated, segment.length()) {
      Err(error) => return Err(error)
      Ok(total) => total
    }
    match check_range(segment.address(), segment.length()) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    segments.push({ address: segment.address(), data: segment.data(), })
  }
  Ok({ segments, family, })
}

///|
/// 将 UF2 镜像转换为上游稀疏模型，拒绝重叠段、空段和越界地址。
/// HEX/S-record 没有存储 UF2 芯片家族 ID 的字段，丢弃该信息需要显式许可。
/// 调用方可以为导出结果添加新的入口地址；不会根据数据地址推断入口地址。
pub fn to_firmware_image(
  image : @uf2.Image,
  entry_point? : UInt64? = None,
  discard_metadata? : Bool = false,
) -> Result[@firmware.FirmwareImage, AdapterError] {
  if image.family is Some(_) && !discard_metadata {
    return Err(
      MetadataLoss(
        "Intel HEX 和 S-record 无法保留 UF2 芯片家族 ID；如需继续，请显式启用 discard_metadata",
      ),
    )
  }
  match entry_point {
    Some(address) if address > 0xFFFFFFFFUL =>
      return Err(InvalidImage("入口地址超出 32 位地址空间"))
    _ => ()
  }
  let chunks : Array[@firmware.FirmwareChunk] = []
  let mut populated = 0
  for index, segment in image.segments {
    populated = match check_byte_budget(populated, segment.data.length()) {
      Err(error) => return Err(error)
      Ok(total) => total
    }
    if segment.data.length() == 0 {
      return Err(InvalidImage("镜像包含空数据段"))
    }
    match check_range(segment.address, segment.data.length()) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match
      @firmware.FirmwareChunk::create(
        segment.address,
        segment.data,
        line_index=index,
      ) {
      Err(error) => return Err(Firmware(error))
      Ok(chunk) => chunks.push(chunk)
    }
  }
  normalize_chunks(chunks, entry_point)
}

///|
/// 将经过校验的 Intel HEX 解析为稀疏镜像，拒绝所有重叠记录。
/// 校验和、EOF 记录和地址元数据由上游解析器检查。
pub fn intel_hex_to_image(
  text : String,
  family? : UInt? = None,
  discard_metadata? : Bool = false,
) -> Result[@uf2.Image, AdapterError] {
  match check_text_budget(text) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let document = match @firmware.parse_intel_hex_document(text) {
    Err(error) => return Err(Firmware(error))
    Ok(document) => document
  }
  let image = match
    normalize_chunks(document.data_chunks(), document.entry_point()) {
    Err(error) => return Err(error)
    Ok(image) => image
  }
  from_firmware_image(image, family~, discard_metadata~)
}

///|
/// 将经过校验的 Motorola S-record 解析为稀疏镜像。完整的 S-record 文档
/// 总会包含终止记录的入口地址（包括零），因此转换时必须设置
/// `discard_metadata=true`。头记录也属于无法保留在 UF2 镜像中的元数据。
pub fn srecord_to_image(
  text : String,
  family? : UInt? = None,
  discard_metadata? : Bool = false,
) -> Result[@uf2.Image, AdapterError] {
  match check_text_budget(text) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let document = match @firmware.parse_srecord_document(text) {
    Err(error) => return Err(Firmware(error))
    Ok(document) => document
  }
  if document.header() is Some(_) && !discard_metadata {
    return Err(
      MetadataLoss(
        "UF2 无法保留 S-record 头记录或入口地址；如需继续，请显式启用 discard_metadata",
      ),
    )
  }
  let image = match
    normalize_chunks(document.data_chunks(), document.entry_point()) {
    Err(error) => return Err(error)
    Ok(image) => image
  }
  from_firmware_image(image, family~, discard_metadata~)
}

///|
/// 导出稀疏 Intel HEX，不为地址空洞分配或填充数据。
/// 输出采用规范化记录，不保证逐字节重现输入文本。
pub fn image_to_intel_hex(
  image : @uf2.Image,
  record_bytes? : Int = 16,
  discard_metadata? : Bool = false,
) -> Result[String, AdapterError] {
  let firmware = match to_firmware_image(image, discard_metadata~) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  match firmware.to_intel_hex(record_bytes~) {
    Err(error) => Err(Firmware(error))
    Ok(text) => Ok(text)
  }
}

///|
/// 导出稀疏 S-record。未提供入口地址时，上游导出器会将必需的终止记录
/// 地址写为零。这只是格式占位值，不代表推断出的启动入口地址。
/// 调用方提供的头记录属于新增的输出元数据。记录宽度由上游校验。
pub fn image_to_srecord(
  image : @uf2.Image,
  record_bytes? : Int = 32,
  entry_point? : UInt64? = None,
  header? : String = "",
  discard_metadata? : Bool = false,
) -> Result[String, AdapterError] {
  let firmware = match
    to_firmware_image(image, entry_point~, discard_metadata~) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  match firmware.to_srecord(record_bytes~, header~) {
    Err(error) => Err(Firmware(error))
    Ok(text) => Ok(text)
  }
}
