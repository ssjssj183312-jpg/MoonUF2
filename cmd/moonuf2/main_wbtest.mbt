///|
/// 对照实际导出器，覆盖 UF2 分块、空洞、HEX 地址换页和 S-record 地址宽度。
test "文本限额与相邻数据段合并后的实际输出一致" {
  for base in [0UL, 0xfffcUL, 0xfffffcUL, 0xfffff120UL] {
    let original = @uf2.from_bin(Bytes::makei(3808, i => i.to_byte()), base).unwrap()
    let fragmented = @uf2.decode(
      @uf2.encode(original, payload_size=476).unwrap(),
    ).unwrap()
    assert_eq(fragmented.segments.length(), 8)
    assert_eq(
      text_output_bound(fragmented, "hex"),
      @adapter.image_to_intel_hex(fragmented).unwrap().length().to_uint64(),
    )
    assert_eq(
      text_output_bound(fragmented, "srec"),
      @adapter.image_to_srecord(fragmented).unwrap().length().to_uint64(),
    )
  }
}

///|
test "文本限额保留稀疏空洞及各连续范围的记录边界" {
  let image : @uf2.Image = {
    family: None,
    segments: [
      { address: 0UL, data: b"abcd", },
      { address: 4UL, data: b"efgh", },
      { address: 16UL, data: b"ijkl", },
      { address: 0xfffcUL, data: b"mnop", },
      { address: 0x10000UL, data: b"qrst", },
      { address: 0xfffffffcUL, data: b"uvwx", },
    ],
  }
  assert_eq(
    text_output_bound(image, "hex"),
    @adapter.image_to_intel_hex(image).unwrap().length().to_uint64(),
  )
  assert_eq(
    text_output_bound(image, "srec"),
    @adapter.image_to_srecord(image).unwrap().length().to_uint64(),
  )
}

///|
test "S-record 计数记录宽度按合并后的实际记录数选择" {
  // 合并后恰好 65535 条数据记录；按两个原始段分别计算会错误升级为 S6。
  let image : @uf2.Image = {
    family: None,
    segments: [
      { address: 0UL, data: b"abcd", },
      { address: 4UL, data: Bytes::make(65535 * 32 - 4, 0x00), },
    ],
  }
  assert_eq(text_output_bound(image, "srec"), 65535UL * (64UL + 13UL) + 23UL)
  let larger : @uf2.Image = {
    family: None,
    segments: [{ address: 0UL, data: Bytes::make(65536 * 32, 0x00), }],
  }
  assert_eq(text_output_bound(larger, "srec"), 65536UL * (64UL + 13UL) + 25UL)
}
