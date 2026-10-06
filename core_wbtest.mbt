///|
test "BIN、UF2 往返转换及头字段" {
  let data = Bytes::makei(1024, i => i.to_byte())
  let image = from_bin(data, 0x10000000UL, family=Some(0xE48BFF56U)).unwrap()
  let uf2 = encode(image).unwrap()
  assert_eq(uf2.length(), 2048)
  assert_eq(read32(uf2, 0), 0x0A324655U)
  assert_eq(read32(uf2, 8), 0x2000U)
  assert_eq(read32(uf2, 28), 0xE48BFF56U)
  assert_eq(
    to_bin(decode(uf2, expected_family=Some(0xE48BFF56U)).unwrap()).unwrap(),
    data,
  )
}

///|
test "所有支持的有效载荷长度均可往返转换" {
  for size = 4; size <= 476; size = size + 4 {
    let data = Bytes::makei(size * 3 + 4, i => (i * 13).to_byte())
    let image = from_bin(data, 0UL).unwrap()
    assert_eq(
      to_bin(decode(encode(image, payload_size=size).unwrap()).unwrap()).unwrap(),
      data,
    )
  }
}

///|
test "稀疏转换限制跨度并显式选择填充值" {
  let image : Image = {
    family: None,
    segments: [
      { address: 0UL, data: b"abcd", },
      { address: 16UL, data: b"efgh", },
    ],
  }
  let result = to_bin(image, fill=0x00).unwrap()
  assert_eq(result.length(), 20)
  assert_eq(result[4], 0x00)
  assert_true(to_bin(image, max_span=19) is Err(_))
  let huge : Image = {
    family: None,
    segments: [
      { address: 0UL, data: b"abcd", },
      { address: 0xFFFFFFFCUL, data: b"efgh", },
    ],
  }
  assert_true(to_bin(huge) is Err(_))
  assert_eq(encode(huge).unwrap().length(), 1024)
}

///|
test "接受恰好到达地址空间末端的数据" {
  let image = from_bin(b"abcd", 0xFFFFFFFCUL).unwrap()
  let decoded = decode(encode(image).unwrap()).unwrap()
  assert_eq(decoded.segments[0].address, 0xFFFFFFFCUL)
  assert_eq(to_bin(decoded).unwrap(), b"abcd")
  assert_true(from_bin(b"abcdefgh", 0xFFFFFFFCUL) is Err(_))
}

///|
test "生成要求显式对齐且数据非空" {
  assert_true(from_bin(b"abc", 0UL) is Err(_))
  assert_true(from_bin(b"abcd", 1UL) is Err(_))
  assert_true(from_bin(b"", 0UL) is Err(_))
  let image = from_bin(b"abcd", 0UL).unwrap()
  for size in [0, 1, 3, 477, 512, -4] {
    assert_true(encode(image, payload_size=size) is Err(_))
  }
  assert_true(encode({ segments: [], family: None, }) is Err(_))
}
