///|
/// 独立审查辅助函数直接构造二进制头部，不调用 @moonuf2.encode。
fn review_put32(bytes : FixedArray[Byte], at : Int, value : UInt) -> Unit {
  for i = 0; i < 4; i = i + 1 {
    bytes[at + i] = ((value >> (i * 8)) & 0xFFU).to_byte()
  }
}

///|
fn review_block(
  address : UInt,
  size? : UInt = 4U,
  number? : UInt = 0U,
  count? : UInt = 1U,
  flags? : UInt = 0U,
  family? : UInt = 0U,
  seed? : Int = 0,
) -> Bytes {
  let bytes : FixedArray[Byte] = FixedArray::make(512, 0x00)
  review_put32(bytes, 0, 0x0A324655U)
  review_put32(bytes, 4, 0x9E5D5157U)
  review_put32(bytes, 8, flags)
  review_put32(bytes, 12, address)
  review_put32(bytes, 16, size)
  review_put32(bytes, 20, number)
  review_put32(bytes, 24, count)
  review_put32(bytes, 28, family)
  review_put32(bytes, 508, 0x0AB16F30U)
  if size <= 476U {
    for i = 0; i < size.reinterpret_as_int(); i = i + 1 {
      bytes[32 + i] = (seed + i).to_byte()
    }
  }
  Bytes::makei(512, i => bytes[i])
}

///|
fn review_join(blocks : Array[Bytes]) -> Bytes {
  Bytes::makei(blocks.length() * 512, i => blocks[i / 512][i % 512])
}

///|
fn review_replace32(bytes : Bytes, at : Int, word : UInt) -> Bytes {
  Bytes::makei(bytes.length(), i => {
    if i >= at && i < at + 4 {
      ((word >> ((i - at) * 8)) & 0xFFU).to_byte()
    } else {
      bytes[i]
    }
  })
}

///|
fn review_error(result : Result[@moonuf2.Image, @moonuf2.Uf2Error]) -> String {
  match result {
    Err(error) => error.code
    Ok(_) => "意外成功"
  }
}

///|
test "审查：在读取头部之前拒绝过短和未按块对齐的输入" {
  for n in [0, 1, 31, 32, 507, 508, 511, 513, 1023, 1025] {
    assert_eq(review_error(@moonuf2.decode(Bytes::make(n, 0x00))), "uf2.length")
  }
}

///|
test "审查：逐个物理块检查全部魔数" {
  let a = review_block(0U, number=0U, count=2U)
  let b = review_block(4U, number=1U, count=2U)
  for position in [0, 4, 508] {
    let result = @moonuf2.decode(
      review_join([a, review_replace32(b, position, 0U)]),
    )
    assert_eq(review_error(result), "uf2.magic")
    match result {
      Err(error) => assert_eq(error.block, 1)
      Ok(_) => fail("错误地接受了损坏的魔数")
    }
  }
}

///|
test "审查：拒绝所有不支持的标志位，不推测扩展含义" {
  for bit = 0; bit < 32; bit = bit + 1 {
    if bit != 13 {
      assert_eq(
        review_error(@moonuf2.decode(review_block(0U, flags=1U << bit))),
        "uf2.unsupported_flags",
      )
    }
  }
  assert_eq(
    review_error(@moonuf2.decode(review_block(0U, flags=0x2001U))),
    "uf2.unsupported_flags",
  )
  assert_true(
    @moonuf2.decode(review_block(0U, flags=0x2000U, family=0U)) is Ok(_),
  )
}

///|
test "审查：载荷边界和对齐检查防止不安全读取" {
  for n in [0U, 477U, 512U, 0x80000000U, 0xFFFFFFFFU] {
    assert_eq(
      review_error(@moonuf2.decode(review_block(0U, size=n))),
      "uf2.payload",
    )
  }
  for n in [1U, 2U, 3U, 5U, 475U] {
    assert_eq(
      review_error(@moonuf2.decode(review_block(0U, size=n))),
      "uf2.alignment",
    )
  }
  for address in [1U, 2U, 3U, 0xFFFFFFFFU] {
    assert_eq(
      review_error(@moonuf2.decode(review_block(address))),
      "uf2.alignment",
    )
  }
  for n = 4; n <= 476; n = n + 4 {
    let decoded = @moonuf2.decode(
      review_block(0U, size=n.reinterpret_as_uint()),
    ).unwrap()
    assert_eq(decoded.segments[0].data.length(), n)
    assert_eq(decoded.segments[0].data[n - 1], (n - 1).to_byte())
  }
}

///|
test "审查：最大地址终点使用扩宽后的整数运算" {
  assert_true(@moonuf2.decode(review_block(0xFFFFFFFCU)) is Ok(_))
  assert_eq(
    review_error(@moonuf2.decode(review_block(0xFFFFFFFCU, size=8U))),
    "uf2.address_overflow",
  )
  assert_true(@moonuf2.decode(review_block(0xFFFFFE24U, size=476U)) is Ok(_))
  assert_eq(
    review_error(@moonuf2.decode(review_block(0xFFFFFE28U, size=476U))),
    "uf2.address_overflow",
  )
}

///|
test "审查：畸形或恶意的块编号不会决定内存分配量" {
  for (number, count) in [(0U, 0U), (1U, 1U), (0xFFFFFFFFU, 0xFFFFFFFFU)] {
    assert_eq(
      review_error(@moonuf2.decode(review_block(0U, number~, count~))),
      "uf2.block_number",
    )
  }
  for number in [0U, 0x80000000U, 0xFFFFFFFEU] {
    assert_eq(
      review_error(
        @moonuf2.decode(review_block(0U, number~, count=0xFFFFFFFFU)),
      ),
      "uf2.missing_blocks",
    )
  }
  assert_eq(
    review_error(
      @moonuf2.decode(
        review_join([
          review_block(0U, number=0U, count=3U),
          review_block(4U, number=2U, count=3U),
          review_block(4U, number=2U, count=3U),
        ]),
      ),
    ),
    "uf2.missing_blocks",
  )
  assert_eq(
    review_error(
      @moonuf2.decode(
        review_join([
          review_block(0U, number=0U, count=2U),
          review_block(4U, number=1U, count=3U),
        ]),
      ),
    ),
    "uf2.block_count",
  )
}

///|
test "审查：严格检查芯片家族标识的存在性、预期值及保留字段" {
  assert_eq(
    review_error(@moonuf2.decode(review_block(0U, family=1U))),
    "uf2.reserved",
  )
  for
    second in [
      review_block(4U, number=1U, count=2U),
      review_block(4U, number=1U, count=2U, flags=0x2000U, family=2U),
    ] {
    assert_eq(
      review_error(
        @moonuf2.decode(
          review_join([
            review_block(0U, number=0U, count=2U, flags=0x2000U, family=1U),
            second,
          ]),
        ),
      ),
      "uf2.family",
    )
  }
  assert_eq(
    review_error(@moonuf2.decode(review_block(0U), expected_family=Some(0U))),
    "uf2.family",
  )
  assert_eq(
    review_error(
      @moonuf2.decode(
        review_block(0U, flags=0x2000U, family=1U),
        expected_family=Some(2U),
      ),
    ),
    "uf2.family",
  )
  assert_eq(
    @moonuf2.decode(
      review_block(0U, flags=0x2000U, family=0xFFFFFFFFU),
      expected_family=Some(0xFFFFFFFFU),
    ).unwrap().family,
    Some(0xFFFFFFFFU),
  )
}

///|
test "审查：合并逻辑重复块并拒绝冲突" {
  let block = review_block(0U)
  let repeated = @moonuf2.decode(review_join([block, block, block])).unwrap()
  assert_eq(repeated.segments.length(), 1)
  // 未使用的字节不属于逻辑载荷。
  let padding_changed = review_replace32(block, 504, 0xDEADBEEFU)
  assert_eq(
    @moonuf2.decode(review_join([block, padding_changed])).unwrap(),
    repeated,
  )
  for
    changed in [
      review_block(4U),
      review_block(0U, seed=1),
      review_block(0U, size=8U),
    ] {
    assert_eq(
      review_error(@moonuf2.decode(review_join([block, changed]))),
      "uf2.duplicate_conflict",
    )
  }
}

///|
test "审查：乱序和重复块仍生成按地址排序的数据" {
  let blocks = [
    review_block(32U, number=0U, count=3U, seed=32),
    review_block(0U, number=1U, count=3U, seed=0),
    review_block(12U, number=2U, count=3U, seed=12),
  ]
  let expected = @moonuf2.decode(review_join(blocks)).unwrap()
  assert_eq(expected.segments[0].address, 0UL)
  assert_eq(expected.segments[1].address, 12UL)
  assert_eq(expected.segments[2].address, 32UL)
  for
    order in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]] {
    let bytes = review_join([
      blocks[order[0]],
      blocks[order[1]],
      blocks[order[2]],
      blocks[order[0]],
    ])
    assert_eq(@moonuf2.decode(bytes).unwrap(), expected)
    assert_eq(
      @moonuf2.to_bin(@moonuf2.decode(bytes).unwrap(), fill=0x77).unwrap()[4],
      0x77,
    )
  }
}

///|
test "审查：不同编号的块不得重叠，即使字节内容相同" {
  for second_address in [0U, 4U] {
    assert_eq(
      review_error(
        @moonuf2.decode(
          review_join([
            review_block(0U, size=8U, number=0U, count=2U),
            review_block(second_address, number=1U, count=2U),
          ]),
        ),
      ),
      "uf2.overlap",
    )
  }
  assert_true(
    @moonuf2.decode(
      review_join([
        review_block(0U, size=8U, number=0U, count=2U),
        review_block(8U, number=1U, count=2U),
      ]),
    )
    is Ok(_),
  )
}

///|
test "审查：镜像校验拒绝不安全的地址范围且不修改输入" {
  let high : @moonuf2.Image = {
    family: None,
    segments: [{ address: 0xFFFFFFFFFFFFFFFCUL, data: b"abcd", }],
  }
  assert_true(@moonuf2.encode(high) is Err(_))
  assert_true(@moonuf2.to_bin(high) is Err(_))
  assert_true(@moonuf2.from_bin(b"abcd", 0xFFFFFFFFFFFFFFFCUL) is Err(_))
  let unsorted : @moonuf2.Image = {
    family: Some(0U),
    segments: [
      { address: 8UL, data: b"efgh", },
      { address: 0UL, data: b"abcd", },
    ],
  }
  let original_order = unsorted.segments.copy()
  let output = @moonuf2.encode(unsorted, payload_size=4).unwrap()
  assert_eq(unsorted.segments, original_order)
  assert_eq(
    @moonuf2.to_bin(unsorted, max_span=12, fill=0x00).unwrap(),
    b"abcd\x00\x00\x00\x00efgh",
  )
  assert_eq(unsorted.segments, original_order)
  assert_eq(@moonuf2.decode(output).unwrap().family, Some(0U))
  for limit in [-1, 0, 11] {
    assert_true(@moonuf2.to_bin(unsorted, max_span=limit) is Err(_))
  }
}

///|
test "审查：在分配过大的 UF2 缓冲区之前拒绝超限输出" {
  let image = @moonuf2.from_bin(Bytes::make(32769 * 4, 0x00), 0UL).unwrap()
  match @moonuf2.encode(image, payload_size=4) {
    Err(error) => assert_eq(error.code, "uf2.output_limit")
    Ok(_) => fail("超出了 UF2 输出上限")
  }
  let wide : @moonuf2.Image = {
    family: None,
    segments: [
      { address: 0UL, data: b"abcd", },
      { address: 16777216UL, data: b"efgh", },
    ],
  }
  match @moonuf2.to_bin(wide, max_span=2147483647) {
    Err(error) => assert_eq(error.code, "bin.span_limit")
    Ok(_) => fail("超出了 BIN 地址跨度硬性上限")
  }
}

///|
test "审查：接受恰好 16 MiB 的 UF2，并拒绝多出的一个块" {
  let raw = Bytes::makei(32768 * 4, i => (i * 7).to_byte())
  let image = @moonuf2.from_bin(raw, 0UL).unwrap()
  let encoded = @moonuf2.encode(image, payload_size=4).unwrap()
  assert_eq(encoded.length(), 16777216)
  let restored = @moonuf2.decode(encoded).unwrap()
  assert_eq(restored.segments.length(), 32768)
  assert_eq(@moonuf2.to_bin(restored).unwrap(), raw)
  assert_eq(
    review_error(@moonuf2.decode(Bytes::make(16777216 + 512, 0x00))),
    "uf2.input_limit",
  )
}

///|
test "审查：接受恰好达到 BIN 硬性上限的输入，并拒绝多出的一个对齐字" {
  let raw = Bytes::make(16777216, 0x42)
  let image = @moonuf2.from_bin(raw, 0UL).unwrap()
  let restored = @moonuf2.to_bin(image).unwrap()
  assert_eq(restored.length(), 16777216)
  assert_eq(restored[0], 0x42)
  assert_eq(restored[16777215], 0x42)
  assert_eq(
    review_error(@moonuf2.from_bin(Bytes::make(16777220, 0x00), 0UL)),
    "bin.input_limit",
  )
}

///|
test "审查：编码时将每个未使用的载荷字节填零" {
  let image = @moonuf2.from_bin(Bytes::makei(260, i => i.to_byte()), 0UL).unwrap()
  let encoded = @moonuf2.encode(image).unwrap()
  // 第一个载荷为 256 字节，第二个载荷为 4 字节。
  for i = 32 + 256; i < 508; i = i + 1 {
    assert_eq(encoded[i], 0x00)
  }
  for i = 512 + 32 + 4; i < 512 + 508; i = i + 1 {
    assert_eq(encoded[i], 0x00)
  }
}
