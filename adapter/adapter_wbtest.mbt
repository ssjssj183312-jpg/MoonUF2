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
test "Intel HEX sparse round trip does not fill a multigigabyte gap" {
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
test "S-record sparse round trip requires explicit metadata loss" {
  let input = sample_image()
  let text = image_to_srecord(input).unwrap()
  assert_true(text.length() < 200)
  assert_true(srecord_to_image(text) is Err(MetadataLoss(_)))
  assert_eq(srecord_to_image(text, discard_metadata=true).unwrap(), input)
}

///|
test "Intel HEX and UF2 compose both directions with family metadata" {
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
test "S-record and UF2 compose without filling holes" {
  let input = sample_image()
  let text = image_to_srecord(input, entry_point=Some(0x1000UL)).unwrap()
  let binary = @uf2.encode(
    srecord_to_image(text, discard_metadata=true).unwrap(),
  ).unwrap()
  let emitted = image_to_srecord(@uf2.decode(binary).unwrap()).unwrap()
  assert_eq(srecord_to_image(emitted, discard_metadata=true).unwrap(), input)
}

///|
test "Intel HEX entry point cannot be discarded implicitly" {
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
test "S-record header and zero termination remain explicit metadata" {
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
test "UF2 family cannot be discarded by either exporter implicitly" {
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
test "known Intel HEX record has expected absolute data and rejects checksum corruption" {
  let text = ":0400100001020304E2\n:00000001FF"
  let image = intel_hex_to_image(text).unwrap()
  assert_eq(image.segments.length(), 1)
  assert_eq(image.segments[0].address, 0x10UL)
  assert_eq(image.segments[0].data, b"\x01\x02\x03\x04")
  match intel_hex_to_image(":0400100001020304E3\n:00000001FF") {
    Err(error) => {
      assert_eq(error.code(), "checksum.mismatch")
      assert_eq(error.line_index(), Some(0))
      assert_true(error.message().contains("source line 1"))
    }
    Ok(_) => fail("corrupt checksum was accepted")
  }
}

///|
test "known S-record count and checksum are validated" {
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
test "overlapping records and root segments are rejected even if identical" {
  let text = ":0400100001020304E2\n:0400100001020304E2\n:00000001FF"
  match intel_hex_to_image(text) {
    Err(error) => assert_eq(error.code(), "image.overlap")
    Ok(_) => fail("overlapping records were accepted")
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
test "missing terminator and data after EOF are rejected" {
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
test "32-bit boundary is preserved without wrap and overflow is rejected" {
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
  // Upstream S-record parser accepts its 32-bit start; adapter checks the end.
  assert_true(
    srecord_to_image(
      "S307FFFFFFFF0102F9\nS70500000000FA",
      discard_metadata=true,
    )
    is Err(InvalidImage(_)),
  )
}

///|
test "text exporters preserve the 64-KiB Intel HEX boundary" {
  let input : @uf2.Image = {
    segments: [{ address: 0xFFFCUL, data: b"ABCDEFGH", }],
    family: None,
  }
  let text = image_to_intel_hex(input, record_bytes=7).unwrap()
  assert_true(text.contains(":020000040001F9"))
  assert_eq(intel_hex_to_image(text).unwrap(), input)
}

///|
test "S-record output selects 16 24 and 32-bit address widths" {
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
test "record width header entry and empty segment validation" {
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
test "many deterministic sparse image round trips retain occupied data only" {
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
test "32768 reverse ordered tiny Intel records normalize by sorted append" {
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
test "16384 reverse ordered tiny S-records normalize by sorted append" {
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
test "reverse ordered root segments are normalized without quadratic inserts" {
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
test "public adapters reject text and populated data above 16 MiB before normalization" {
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
test "preflight bounds giant lines while retaining CRLF source indices" {
  let oversized_line = ":" + "0".repeat(100000)
  match intel_hex_to_image("\r\n" + oversized_line) {
    Err(error) => {
      assert_eq(error.code(), "record.too_long")
      assert_eq(error.line_index(), Some(1))
    }
    Ok(_) => fail("oversized record was accepted")
  }
}
