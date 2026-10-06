///|
fn sample_image() -> @uf2.Image {
  {
    segments: [
      { address: 0x1000UL, data: b"ABCD", },
      { address: 0xF0000000UL, data: b"WXYZ", },
    ],
    family: None,
  }
}

///|
test "Intel HEX 稀疏往返转换不填充数 GiB 的地址空洞" {
  let input = sample_image()
  let text = image_to_intel_hex(input).unwrap()
  assert_true(text.length() < 200)
  let output = intel_hex_to_image(text).unwrap()
  assert_eq(output, input)
  let firmware = to_firmware_image(output).unwrap()
  assert_eq(firmware.total_bytes(), 8)
  assert_eq(firmware.gaps().length(), 1)
  assert_eq(firmware.byte_at(0x2000UL), None)
}

///|
test "S-record 稀疏往返转换需要显式许可丢弃元数据" {
  let input = sample_image()
  let text = image_to_srecord(input).unwrap()
  assert_true(text.length() < 200)
  assert_true(srecord_to_image(text) is Err(MetadataLoss(_)))
  assert_eq(srecord_to_image(text, discard_metadata=true).unwrap(), input)
}

///|
test "Intel HEX 与 UF2 双向组合转换支持芯片家族元数据" {
  let input = sample_image()
  let text = image_to_intel_hex(input).unwrap()
  let parsed = intel_hex_to_image(text, family=Some(0xE48BFF56U)).unwrap()
  let binary = @uf2.encode(parsed).unwrap()
  assert_eq(binary.length(), 1024)
  let decoded = @uf2.decode(binary).unwrap()
  assert_eq(decoded, parsed)
  assert_true(image_to_intel_hex(decoded) is Err(MetadataLoss(_)))
  let emitted = image_to_intel_hex(decoded, discard_metadata=true).unwrap()
  assert_eq(intel_hex_to_image(emitted).unwrap(), input)
}

///|
test "S-record 与 UF2 组合转换不填充地址空洞" {
  let input = sample_image()
  let text = image_to_srecord(input, entry_point=Some(0x1000UL)).unwrap()
  let binary = @uf2.encode(
    srecord_to_image(text, discard_metadata=true).unwrap(),
  ).unwrap()
  let emitted = image_to_srecord(@uf2.decode(binary).unwrap()).unwrap()
  assert_eq(srecord_to_image(emitted, discard_metadata=true).unwrap(), input)
}

///|
test "不得隐式丢弃 Intel HEX 入口地址" {
  let firmware = to_firmware_image(sample_image(), entry_point=Some(0x1000UL)).unwrap()
  let text = firmware.to_intel_hex().unwrap()
  assert_true(intel_hex_to_image(text) is Err(MetadataLoss(_)))
  assert_true(from_firmware_image(firmware) is Err(MetadataLoss(_)))
  assert_eq(
    intel_hex_to_image(text, discard_metadata=true).unwrap(),
    sample_image(),
  )
}

///|
test "S-record 头记录和零终止地址仍属于显式元数据" {
  let text = image_to_srecord(sample_image(), header="MoonUF2").unwrap()
  assert_true(srecord_to_image(text) is Err(MetadataLoss(_)))
  assert_eq(
    srecord_to_image(text, discard_metadata=true).unwrap(),
    sample_image(),
  )
  let document = @firmware.parse_srecord_document(text).unwrap()
  assert_eq(document.entry_point(), Some(0UL))
  assert_eq(document.header(), Some(b"MoonUF2"))
}

///|
test "两种导出器均不得隐式丢弃 UF2 芯片家族 ID" {
  let input : @uf2.Image = {
    segments: sample_image().segments,
    family: Some(1U),
  }
  assert_true(image_to_intel_hex(input) is Err(MetadataLoss(_)))
  assert_true(image_to_srecord(input) is Err(MetadataLoss(_)))
  assert_true(to_firmware_image(input) is Err(MetadataLoss(_)))
  assert_true(image_to_intel_hex(input, discard_metadata=true) is Ok(_))
  assert_true(image_to_srecord(input, discard_metadata=true) is Ok(_))
}

///|
test "已知 Intel HEX 记录保留预期绝对地址数据并拒绝损坏的校验和" {
  let text = ":0400100001020304E2\n:00000001FF"
  let image = intel_hex_to_image(text).unwrap()
  assert_eq(image.segments.length(), 1)
  assert_eq(image.segments[0].address, 0x10UL)
  assert_eq(image.segments[0].data, b"\x01\x02\x03\x04")
  match intel_hex_to_image(":0400100001020304E3\n:00000001FF") {
    Err(error) => {
      assert_eq(error.code(), "checksum.mismatch")
      assert_eq(error.line_index(), Some(0))
      assert_true(error.message().contains("源文件第 1 行"))
    }
    Ok(_) => fail("错误地接受了损坏的校验和")
  }
}

///|
test "校验已知 S-record 的记录计数和校验和" {
  let text = "S107001001020304DE\nS5030001FB\nS9030000FC"
  let image = srecord_to_image(text, discard_metadata=true).unwrap()
  assert_eq(image.segments[0].address, 0x10UL)
  assert_eq(image.segments[0].data, b"\x01\x02\x03\x04")
  assert_true(
    srecord_to_image("S107001001020304DF\nS9030000FC", discard_metadata=true)
    is Err(Firmware(_)),
  )
  assert_true(
    srecord_to_image(
      "S107001001020304DE\nS5030002FA\nS9030000FC",
      discard_metadata=true,
    )
    is Err(Firmware(_)),
  )
}

///|
test "拒绝重叠记录和根镜像段，即使重叠字节完全一致" {
  let text = ":0400100001020304E2\n:0400100001020304E2\n:00000001FF"
  match intel_hex_to_image(text) {
    Err(error) => assert_eq(error.code(), "image.overlap")
    Ok(_) => fail("错误地接受了重叠记录")
  }
  let input : @uf2.Image = {
    segments: [
      { address: 16UL, data: b"ABCD", },
      { address: 18UL, data: b"CD", },
    ],
    family: None,
  }
  assert_true(image_to_intel_hex(input) is Err(Firmware(_)))
  assert_true(image_to_srecord(input) is Err(Firmware(_)))
}

///|
test "拒绝缺少终止记录或 EOF 后仍有数据的输入" {
  assert_true(intel_hex_to_image(":0400100001020304E2") is Err(Firmware(_)))
  assert_true(
    intel_hex_to_image(":00000001FF\n:0400100001020304E2") is Err(Firmware(_)),
  )
  assert_true(
    srecord_to_image("S107001001020304DE", discard_metadata=true)
    is Err(Firmware(_)),
  )
}

///|
test "保留 32 位地址边界而不回绕，并拒绝溢出" {
  let last : @uf2.Image = {
    segments: [{ address: 0xFFFFFFFCUL, data: b"ABCD", }],
    family: None,
  }
  assert_eq(
    intel_hex_to_image(image_to_intel_hex(last).unwrap()).unwrap(),
    last,
  )
  assert_eq(
    srecord_to_image(image_to_srecord(last).unwrap(), discard_metadata=true).unwrap(),
    last,
  )
  let overflow : @uf2.Image = {
    segments: [{ address: 0xFFFFFFFFUL, data: b"AB", }],
    family: None,
  }
  assert_true(image_to_intel_hex(overflow) is Err(InvalidImage(_)))
  assert_true(image_to_srecord(overflow) is Err(InvalidImage(_)))
  let too_high : @uf2.Image = {
    segments: [{ address: 0x100000000UL, data: b"ABCD", }],
    family: None,
  }
  assert_true(to_firmware_image(too_high) is Err(InvalidImage(_)))
  // 上游 S-record 解析器接受 32 位起始地址，适配层额外检查数据结束地址。
  assert_true(
    srecord_to_image(
      "S307FFFFFFFF0102F9\nS70500000000FA",
      discard_metadata=true,
    )
    is Err(InvalidImage(_)),
  )
}

///|
test "文本导出器正确处理 Intel HEX 的 64 KiB 边界" {
  let input : @uf2.Image = {
    segments: [{ address: 0xFFFCUL, data: b"ABCDEFGH", }],
    family: None,
  }
  let text = image_to_intel_hex(input, record_bytes=7).unwrap()
  assert_true(text.contains(":020000040001F9"))
  assert_eq(intel_hex_to_image(text).unwrap(), input)
}

///|
test "S-record 输出选择 16 位、24 位和 32 位地址宽度" {
  let addresses = [0x1000UL, 0x100000UL, 0x10000000UL]
  let prefixes = ["S1", "S2", "S3"]
  for index, address in addresses {
    let input : @uf2.Image = {
      segments: [{ address, data: b"ABCD", }],
      family: None,
    }
    let text = image_to_srecord(input).unwrap()
    assert_true(text.has_prefix(prefixes[index]))
    assert_eq(srecord_to_image(text, discard_metadata=true).unwrap(), input)
  }
}

///|
test "校验记录宽度、头记录、入口地址和空数据段" {
  let input = sample_image()
  assert_true(image_to_intel_hex(input, record_bytes=0) is Err(Firmware(_)))
  assert_true(image_to_intel_hex(input, record_bytes=256) is Err(Firmware(_)))
  assert_true(image_to_srecord(input, record_bytes=0) is Err(Firmware(_)))
  assert_true(image_to_srecord(input, record_bytes=251) is Err(Firmware(_)))
  assert_true(image_to_srecord(input, header="固件") is Err(Firmware(_)))
  assert_true(
    image_to_srecord(input, entry_point=Some(0x100000000UL))
    is Err(InvalidImage(_)),
  )
  let empty_segment : @uf2.Image = {
    segments: [{ address: 0UL, data: b"", }],
    family: None,
  }
  assert_true(to_firmware_image(empty_segment) is Err(InvalidImage(_)))
}

///|
test "多组确定性稀疏镜像往返转换只保留实际存在的数据" {
  for seed = 0; seed < 32; seed = seed + 1 {
    let segments : Array[@uf2.Segment] = []
    for index = 0; index < 6; index = index + 1 {
      segments.push({
        address: 0x1000UL + index.to_uint64() * 0x1000000UL,
        data: Bytes::makei(4 * (1 + (seed + index) % 7), offset => {
          (seed + index + offset).to_byte()
        }),
      })
    }
    let input : @uf2.Image = { segments, family: None, }
    let hex = image_to_intel_hex(input, record_bytes=1 + seed).unwrap()
    assert_eq(intel_hex_to_image(hex).unwrap(), input)
    let srec = image_to_srecord(input, record_bytes=1 + seed).unwrap()
    assert_eq(srecord_to_image(srec, discard_metadata=true).unwrap(), input)
  }
}

///|
fn reverse_hex_records(count : Int) -> String {
  let lines : Array[String] = []
  for address = count - 1; address >= 0; address = address - 1 {
    let body = Bytes::makei(5, index => {
      match index {
        0 => 1
        1 => (address >> 8).to_byte()
        2 => address.to_byte()
        3 => 0
        _ => (address % 251).to_byte()
      }
    })
    let checksum = Bytes::makei(1, _ => @firmware.twos_complement_checksum(body))
    lines.push(
      ":" +
      @firmware.encode_hex_bytes(body) +
      @firmware.encode_hex_bytes(checksum),
    )
  }
  lines.push(":00000001FF")
  lines.join("\n")
}

///|
test "32768 条逆序短 Intel HEX 记录通过排序后追加完成规范化" {
  let text = reverse_hex_records(32768)
  let output = intel_hex_to_image(text).unwrap()
  assert_eq(output.segments.length(), 1)
  assert_eq(output.segments[0].address, 0UL)
  assert_eq(output.segments[0].data.length(), 32768)
  for index = 0; index < 32768; index = index + 1 {
    assert_eq(output.segments[0].data[index], (index % 251).to_byte())
  }
}

///|
test "16384 条逆序短 S-record 记录通过排序后追加完成规范化" {
  let lines : Array[String] = []
  for address = 16383; address >= 0; address = address - 1 {
    let body = Bytes::makei(4, index => {
      match index {
        0 => 4
        1 => (address >> 8).to_byte()
        2 => address.to_byte()
        _ => (address % 251).to_byte()
      }
    })
    let checksum = Bytes::makei(1, _ => @firmware.ones_complement_checksum(body))
    lines.push(
      "S1" +
      @firmware.encode_hex_bytes(body) +
      @firmware.encode_hex_bytes(checksum),
    )
  }
  lines.push("S9030000FC")
  let output = srecord_to_image(lines.join("\n"), discard_metadata=true).unwrap()
  assert_eq(output.segments.length(), 1)
  assert_eq(output.segments[0].data.length(), 16384)
  for index = 0; index < 16384; index = index + 1 {
    assert_eq(output.segments[0].data[index], (index % 251).to_byte())
  }
}

///|
test "逆序根镜像段的规范化不会产生平方级插入开销" {
  let segments : Array[@uf2.Segment] = []
  for index = 16383; index >= 0; index = index - 1 {
    segments.push({ address: index.to_uint64() * 4UL, data: b"ABCD", })
  }
  let output = to_firmware_image({ segments, family: None, }).unwrap()
  assert_eq(output.segments().length(), 1)
  assert_eq(output.total_bytes(), 65536)
  assert_eq(output.byte_at(0UL), Some(b'A'))
  assert_eq(output.byte_at(65535UL), Some(b'D'))
}

///|
test "公开适配接口在规范化前拒绝超过 16 MiB 的文本和实际数据" {
  let excessive = "X".repeat(16777217)
  assert_true(intel_hex_to_image(excessive) is Err(ResourceLimit(_)))
  assert_true(
    srecord_to_image(excessive, discard_metadata=true) is Err(ResourceLimit(_)),
  )
  let data = Bytes::make(16777217, 0)
  let image : @uf2.Image = {
    segments: [{ address: 0UL, data, }],
    family: None,
  }
  assert_true(to_firmware_image(image) is Err(ResourceLimit(_)))
  assert_true(image_to_intel_hex(image) is Err(ResourceLimit(_)))
  assert_true(image_to_srecord(image) is Err(ResourceLimit(_)))
  assert_eq(check_byte_budget(16777215, 1), Ok(16777216))
  assert_true(check_byte_budget(16777216, 1) is Err(ResourceLimit(_)))
}

///|
test "预检查限制超长行并保留 CRLF 文本的源文件行号" {
  let oversized_line = ":" + "0".repeat(100000)
  match intel_hex_to_image("\r\n" + oversized_line) {
    Err(error) => {
      assert_eq(error.code(), "record.too_long")
      assert_eq(error.line_index(), Some(1))
    }
    Ok(_) => fail("错误地接受了超长记录")
  }
}

///|
test "上游错误的中文概括保留结构化原文错误码和源文件行号" {
  let cases : Array[(@firmware.FirmwareErrorCode, String)] = [
    (@firmware.HexOddLength, "十六进制字符数量必须为偶数"),
    (@firmware.HexInvalidDigit, "包含无效的十六进制字符"),
    (@firmware.RecordEmpty, "固件记录不能为空"),
    (@firmware.RecordInvalidPrefix, "固件记录的起始标记无效"),
    (@firmware.RecordInvalidType, "固件记录类型无效或不受支持"),
    (@firmware.RecordLengthMismatch, "记录声明的数据长度与实际长度不符"),
    (@firmware.RecordTooLong, "固件记录超过允许的长度上限"),
    (@firmware.ChecksumMismatch, "固件记录的校验和不匹配"),
    (@firmware.AddressOutOfRange, "固件记录地址超出允许范围"),
    (@firmware.ImageOverlap, "固件数据地址重叠，即使内容相同也不允许"),
    (@firmware.ImageInvalidRange, "镜像范围或导出参数无效"),
    (@firmware.IntegrityViolation, "固件记录的计数或结构不一致"),
    (@firmware.DocumentMissingTerminator, "固件文档缺少必需的结束记录"),
    (@firmware.DocumentRecordAfterTerminator, "固件文档的结束记录后仍有其他记录"),
    (@firmware.DocumentDuplicateMetadata, "固件元数据记录重复或顺序不合法"),
  ]
  for (code, summary) in cases {
    let original = @firmware.FirmwareError::new(
      code,
      "上游原始诊断",
      @firmware.SourcePosition::line(2),
    )
    let wrapped = Firmware(original)
    assert_eq(wrapped.code(), original.code())
    assert_eq(wrapped.line_index(), Some(2))
    assert_eq(wrapped.message(), summary + "（源文件第 3 行）")
    assert_eq(original.message(), "上游原始诊断")
  }
}
