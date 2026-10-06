///|
struct Config {
  command : String
  input : String
  output : String
  from_format : String
  to_format : String
  base : UInt64?
  family : UInt?
  max_bytes : Int
  payload_size : Int
  fill : Byte
  discard_metadata : Bool
}

///|
fn usage() -> Unit {
  let help =
    #|MoonUF2 0.1.0：严格校验、检查和转换固件文件（不会烧录设备）
    #|
    #|用法：
    #|  moonuf2 inspect INPUT [--from uf2|bin|hex|srec] [选项]
    #|  moonuf2 verify INPUT [--from uf2|bin|hex|srec] [选项]
    #|  moonuf2 convert INPUT OUTPUT --from FORMAT --to FORMAT [选项]
    #|
    #|选项：
    #|  --base N              BIN 输入的必填起始地址（十进制或 0x 十六进制）
    #|  --family N            UF2 输入的预期 family ID；其他输入设置 family ID
    #|  --max-bytes N         输入/输出上限，默认 16777216（16 MiB），最高 16 MiB
    #|  --payload-size N      UF2 输出块有效载荷，默认 256；4..476，且为 4 的倍数
    #|  --fill N              BIN 输出空洞填充值，默认 255；0..255
    #|  --discard-metadata    明确允许丢弃 entry point/header/family 等不可表示元数据
    #|  --                    结束选项解析（用于以 - 开头的文件名）
    #|  --help                显示帮助
    #|  --version             显示版本
    #|
    #|转换必须显式指定 --from 和 --to；不按文件扩展名猜测。
    #|输出文件必须不存在；已有文件不会覆盖。HEX/S-record 使用 MoonBit 上游库。
    #|BIN 输出从最低地址开始，空洞填充；请保留输出中报告的 base 地址。
    #|严格 UF2 仅支持普通 main-flash 数据与可选 family ID；地址和长度须 4 字节对齐。
    #|当前 HEX/S-record 检查也使用严格图像适配器；入口点/头信息需 --discard-metadata。
    #|校验仅检查文件结构，不保证设备兼容性、固件真实性或可安全烧录。
    #|
    #|示例：
    #|  moonuf2 convert app.bin app.uf2 --from bin --to uf2 --base 0x10000000 --family 0xe48bff56
    #|  moonuf2 verify app.uf2 --family 0xe48bff56
    #|  moonuf2 convert app.uf2 restored.bin --from uf2 --to bin --discard-metadata
  println(help)
}

///|
/// Numeric parsing is strict and bounded before multiplication; no signs or whitespace.
fn number(text : String) -> Result[UInt64, String] {
  let hex = text.has_prefix("0x") || text.has_prefix("0X")
  let start = if hex { 2 } else { 0 }
  if text.length() == start {
    return Err("cli.number: 数值为空")
  }
  let radix : UInt64 = if hex { 16UL } else { 10UL }
  let mut value = 0UL
  for i = start; i < text.length(); i = i + 1 {
    let c = text[i].to_int()
    let digit = if c >= 48 && c <= 57 {
      c - 48
    } else if hex && c >= 65 && c <= 70 {
      c - 55
    } else if hex && c >= 97 && c <= 102 {
      c - 87
    } else {
      -1
    }
    if digit < 0 || digit.to_uint64() >= radix {
      return Err("cli.number: 非法数值：" + text)
    }
    // All CLI numeric options are within the UF2 32-bit address domain.
    if value > (0xffffffffUL - digit.to_uint64()) / radix {
      return Err(
        "cli.number: 数值超过 32 位无符号整数范围：" + text,
      )
    }
    value = value * radix + digit.to_uint64()
  }
  Ok(value)
}

///|
fn is_format(value : String) -> Bool {
  value == "uf2" || value == "bin" || value == "hex" || value == "srec"
}

///|
fn parse(args : FixedArray[String]) -> Result[Config, String] {
  let command = args[0]
  if command != "inspect" && command != "verify" && command != "convert" {
    return Err("cli.command: 未知命令：" + command)
  }
  let values : Map[String, String] = Map([])
  let paths : Array[String] = []
  let mut discard = false
  let mut positional_only = false
  let mut i = 1
  while i < args.length() {
    let arg = args[i]
    if positional_only {
      paths.push(arg)
    } else if arg == "--" {
      positional_only = true
    } else if arg == "--discard-metadata" {
      if discard {
        return Err("cli.duplicate: 重复选项：" + arg)
      }
      discard = true
    } else if arg == "--from" ||
      arg == "--to" ||
      arg == "--base" ||
      arg == "--family" ||
      arg == "--max-bytes" ||
      arg == "--payload-size" ||
      arg == "--fill" {
      if values.contains(arg) {
        return Err("cli.duplicate: 重复选项：" + arg)
      }
      if i + 1 >= args.length() || args[i + 1].has_prefix("--") {
        return Err("cli.value: 选项缺少值：" + arg)
      }
      i = i + 1
      values[arg] = args[i]
    } else if arg.has_prefix("-") {
      return Err("cli.option: 未知选项：" + arg)
    } else {
      paths.push(arg)
    }
    i = i + 1
  }
  let expected_paths = if command == "convert" { 2 } else { 1 }
  if paths.length() != expected_paths {
    return Err(
      "cli.arguments: " +
      command +
      " 需要 " +
      expected_paths.to_string() +
      " 个文件路径",
    )
  }
  if command == "convert" &&
    (!values.contains("--from") || !values.contains("--to")) {
    return Err("cli.format: convert 必须显式指定 --from 和 --to")
  }
  if command != "convert" &&
    (
      values.contains("--to") ||
      values.contains("--payload-size") ||
      values.contains("--fill")
    ) {
    return Err(
      "cli.option: --to / --payload-size / --fill 仅适用于 convert",
    )
  }
  let from_format = values.get("--from").unwrap_or("uf2")
  let to_format = values.get("--to").unwrap_or("")
  if !is_format(from_format) || (command == "convert" && !is_format(to_format)) {
    return Err("cli.format: FORMAT 必须是 uf2、bin、hex 或 srec")
  }
  let parsed : Map[String, UInt64] = Map([])
  for key in ["--base", "--family", "--max-bytes", "--payload-size", "--fill"] {
    if values.get(key) is Some(value) {
      match number(value) {
        Ok(n) => parsed[key] = n
        Err(e) => return Err(key + ": " + e)
      }
    }
  }
  let base = parsed.get("--base")
  if from_format == "bin" && base is None {
    return Err(
      "cli.base: BIN 输入必须显式提供 --base；不会猜测地址",
    )
  }
  if from_format != "bin" && base is Some(_) {
    return Err(
      "cli.base: --base 仅适用于 BIN 输入；其他格式已有地址",
    )
  }
  let max_bytes = parsed.get("--max-bytes").unwrap_or(16777216UL)
  if max_bytes == 0UL || max_bytes > 16777216UL {
    return Err("cli.limit: --max-bytes 必须在 1..16777216 范围内")
  }
  let payload_size = parsed.get("--payload-size").unwrap_or(256UL)
  if payload_size < 4UL || payload_size > 476UL || payload_size % 4UL != 0UL {
    return Err(
      "cli.payload: --payload-size 必须在 4..476 内且为 4 的倍数",
    )
  }
  if values.contains("--payload-size") && to_format != "uf2" {
    return Err("cli.payload: --payload-size 仅适用于 UF2 输出")
  }
  let fill = parsed.get("--fill").unwrap_or(255UL)
  if fill > 255UL {
    return Err("cli.fill: --fill 必须在 0..255 范围内")
  }
  if values.contains("--fill") && to_format != "bin" {
    return Err("cli.fill: --fill 仅适用于 BIN 输出")
  }
  Ok({
    command,
    input: paths[0],
    output: if command == "convert" {
      paths[1]
    } else {
      ""
    },
    from_format,
    to_format,
    base,
    family: parsed.get("--family").map(n => n.to_uint()),
    max_bytes: max_bytes.to_int(),
    payload_size: payload_size.to_int(),
    fill: fill.to_byte(),
    discard_metadata: discard,
  })
}

///|
fn core_error(error : @uf2.Uf2Error) -> String {
  error.code + " (block " + error.block.to_string() + "): " + error.message
}

///|
fn load_image(bytes : Bytes, cfg : Config) -> Result[@uf2.Image, String] {
  match cfg.from_format {
    "uf2" => @uf2.decode(bytes, expected_family=cfg.family).map_err(core_error)
    "bin" =>
      @uf2.from_bin(bytes, cfg.base.unwrap(), family=cfg.family).map_err(
        core_error,
      )
    "hex" | "srec" => {
      for byte in bytes {
        if byte.to_int() > 127 {
          return Err("text.ascii: HEX/S-record 输入必须是 ASCII 文本")
        }
      }
      let text = ascii_text(bytes)
      let result = if cfg.from_format == "hex" {
        @adapter.intel_hex_to_image(
          text,
          family=cfg.family,
          discard_metadata=cfg.discard_metadata,
        )
      } else {
        @adapter.srecord_to_image(
          text,
          family=cfg.family,
          discard_metadata=cfg.discard_metadata,
        )
      }
      result.map_err(e => e.code() + ": " + e.message())
    }
    _ => Err("cli.format: 不支持的输入格式")
  }
}

///|
fn summary(image : @uf2.Image) -> Unit {
  let mut size = 0UL
  let mut base = 0x100000000UL
  let mut end = 0UL
  for segment in image.segments {
    size = size + segment.data.length().to_uint64()
    if segment.address < base {
      base = segment.address
    }
    let stop = segment.address + segment.data.length().to_uint64()
    if stop > end {
      end = stop
    }
  }
  if image.segments.length() == 0 {
    base = 0UL
  }
  let family = match image.family {
    Some(value) => "0x" + value.to_string(radix=16)
    None => "无"
  }
  println("family: " + family)
  println("base: 0x" + base.to_string(radix=16))
  println("end (exclusive): 0x" + end.to_string(radix=16))
  println("segments: " + image.segments.length().to_string())
  println("data bytes: " + size.to_string())
  println("span bytes: " + (end - base).to_string())
}

///|
/// Include record checksums, address records and newlines without encoding data.
fn text_output_bound(image : @uf2.Image, format : String) -> UInt64 {
  if format == "hex" {
    let mut size = 11UL // EOF, without final newline
    let mut current_upper = 0UL
    for segment in image.segments {
      let mut offset = 0
      while offset < segment.data.length() {
        let address = segment.address + offset.to_uint64()
        let upper = address >> 16
        if upper != current_upper {
          size = size + 16UL
          current_upper = upper
        }
        let boundary = (0x10000UL - (address & 0xffffUL)).to_int()
        let remaining = segment.data.length() - offset
        let mut length = if remaining < 16 { remaining } else { 16 }
        if length > boundary {
          length = boundary
        }
        size = size + length.to_uint64() * 2UL + 12UL
        offset = offset + length
      }
    }
    size
  } else {
    let mut highest = 0UL
    let mut records = 0UL
    let mut bytes = 0UL
    for segment in image.segments {
      let end = segment.address + segment.data.length().to_uint64()
      if end > 0UL && end - 1UL > highest {
        highest = end - 1UL
      }
      records = records + (segment.data.length().to_uint64() + 31UL) / 32UL
      bytes = bytes + segment.data.length().to_uint64()
    }
    let width = if highest <= 0xffffUL {
      2UL
    } else if highest <= 0xffffffUL {
      3UL
    } else {
      4UL
    }
    let count_width = if records <= 0xffffUL { 2UL } else { 3UL }
    bytes * 2UL +
    records * (7UL + 2UL * width) +
    (7UL + 2UL * count_width) +
    (6UL + 2UL * width)
  }
}

///|
fn output_bytes(image : @uf2.Image, cfg : Config) -> Result[Bytes, String] {
  match cfg.to_format {
    "uf2" => {
      let mut blocks = 0UL
      for segment in image.segments {
        blocks = blocks +
          (
            segment.data.length().to_uint64() +
            cfg.payload_size.to_uint64() -
            1UL
          ) /
          cfg.payload_size.to_uint64()
      }
      if blocks * 512UL > cfg.max_bytes.to_uint64() {
        return Err("io.output_limit: UF2 输出超过 --max-bytes 限制")
      }
      @uf2.encode(image, payload_size=cfg.payload_size).map_err(core_error)
    }
    "bin" => {
      if image.family is Some(_) && !cfg.discard_metadata {
        return Err(
          "adapter.metadata_loss: BIN 不保存 family ID；请明确使用 --discard-metadata",
        )
      }
      @uf2.to_bin(image, max_span=cfg.max_bytes, fill=cfg.fill).map_err(
        core_error,
      )
    }
    "hex" | "srec" => {
      // Bound text allocation using the selected record widths and address fields.
      // Adjacent source segments may be merged upstream, which only reduces size.
      let estimated = text_output_bound(image, cfg.to_format)
      if estimated > cfg.max_bytes.to_uint64() {
        return Err(
          "io.output_limit: 文本输出超过 --max-bytes 安全上界",
        )
      }
      let result = if cfg.to_format == "hex" {
        @adapter.image_to_intel_hex(
          image,
          discard_metadata=cfg.discard_metadata,
        )
      } else {
        @adapter.image_to_srecord(image, discard_metadata=cfg.discard_metadata)
      }
      result.map(utf8_bytes).map_err(e => e.code() + ": " + e.message())
    }
    _ => Err("cli.format: 不支持的输出格式")
  }
}

///|
fn run(cfg : Config) -> Result[Unit, String] {
  let read = read_file(cfg.input, cfg.max_bytes)
  if read.error() != "" {
    return Err(read.error())
  }
  let image = match load_image(read.bytes(), cfg) {
    Ok(value) => value
    Err(e) => return Err(e)
  }
  if cfg.command == "convert" {
    let bytes = match output_bytes(image, cfg) {
      Ok(value) => value
      Err(e) => return Err(e)
    }
    if bytes.length() > cfg.max_bytes {
      return Err("io.output_limit: 输出超过 --max-bytes 限制")
    }
    let error = write_file(cfg.output, bytes)
    if error != "" {
      return Err(error)
    }
    println(
      "转换完成：" +
      cfg.input +
      " -> " +
      cfg.output +
      " (" +
      bytes.length().to_string() +
      " bytes)",
    )
  } else if cfg.command == "verify" {
    println(
      "结构校验通过：" +
      cfg.input +
      "（未验证设备兼容性或固件真实性）",
    )
  } else {
    println("文件：" + cfg.input)
  }
  summary(image)
  Ok(())
}

///|
fn main {
  let args = arguments()
  if args.length() == 0 ||
    (args.length() == 1 && (args[0] == "--help" || args[0] == "help")) {
    usage()
  } else if args.length() == 1 && args[0] == "--version" {
    println("MoonUF2 0.1.0")
  } else {
    match parse(args) {
      Err(e) => {
        stderr(e)
        stderr("运行 moonuf2 --help 查看用法")
        set_exit_code(2)
      }
      Ok(cfg) =>
        match run(cfg) {
          Err(e) => {
            stderr(e)
            set_exit_code(1)
          }
          Ok(_) => ()
        }
    }
  }
}
