///|
fn conversion_error(message : String) -> FirmwareError {
  FirmwareError::new(ImageInvalidRange, message, SourcePosition::line(0))
}

///|
fn join_record_lines(lines : Array[String]) -> String {
  let mut result = ""
  for index, line in lines {
    if index > 0 {
      result = result + "\n"
    }
    result = result + line
  }
  result
}

///|
fn encode_intel_output_record(
  record_type : Byte,
  address : Int,
  data : Bytes,
) -> String {
  let body = Bytes::makei(data.length() + 4, index => {
    if index == 0 {
      data.length().to_byte()
    } else if index == 1 {
      ((address >> 8) & 0xFF).to_byte()
    } else if index == 2 {
      (address & 0xFF).to_byte()
    } else if index == 3 {
      record_type
    } else {
      data[index - 4]
    }
  })
  let checksum = Bytes::makei(1, _ => twos_complement_checksum(body))
  ":" + encode_hex_bytes(body) + encode_hex_bytes(checksum)
}

///|
/// Deterministically export an image as 32-bit Intel HEX.
pub fn FirmwareImage::to_intel_hex(
  self : FirmwareImage,
  record_bytes? : Int = 16,
) -> Result[String, FirmwareError] {
  if record_bytes <= 0 || record_bytes > 255 {
    return Err(conversion_error("Intel HEX record width must be 1 through 255"))
  }
  match self.highest_address() {
    Some(value) if value > 0xFFFFFFFFUL =>
      return Err(
        conversion_error("Intel HEX output is limited to 32-bit addresses"),
      )
    _ => ()
  }
  match self.entry_point() {
    Some(value) if value > 0xFFFFFFFFUL =>
      return Err(conversion_error("Intel HEX entry point exceeds 32-bit range"))
    _ => ()
  }
  let lines : Array[String] = []
  let mut current_upper = 0UL
  for segment in self.segments() {
    let source = segment.data()
    let mut offset = 0
    while offset < source.length() {
      let absolute = segment.address() + offset.to_uint64()
      let upper = absolute >> 16
      if upper != current_upper {
        let metadata = Bytes::makei(2, index => {
          if index == 0 {
            ((upper >> 8) & 0xFFUL).to_byte()
          } else {
            (upper & 0xFFUL).to_byte()
          }
        })
        lines.push(encode_intel_output_record(4, 0, metadata))
        current_upper = upper
      }
      let low = (absolute & 0xFFFFUL).to_int()
      let boundary = 0x10000 - low
      let remaining = source.length() - offset
      let length = if remaining < record_bytes {
        remaining
      } else {
        record_bytes
      }
      let length = if length < boundary { length } else { boundary }
      let data = Bytes::makei(length, index => source[offset + index])
      lines.push(encode_intel_output_record(0, low, data))
      offset = offset + length
    }
  }
  match self.entry_point() {
    Some(value) => {
      let data = Bytes::makei(4, index => {
        let shift = (3 - index) * 8
        ((value >> shift) & 0xFFUL).to_byte()
      })
      lines.push(encode_intel_output_record(5, 0, data))
    }
    None => ()
  }
  lines.push(encode_intel_output_record(1, 0, b""))
  Ok(join_record_lines(lines))
}

///|
fn srecord_output_type(address_bytes : Int, category : Int) -> Int {
  if category == 0 {
    0
  } else if category == 1 {
    address_bytes - 1
  } else if category == 2 {
    if address_bytes == 2 {
      5
    } else {
      6
    }
  } else {
    11 - address_bytes
  }
}

///|
fn encode_srecord_output(
  type_digit : Int,
  address_bytes : Int,
  address : UInt64,
  data : Bytes,
) -> String {
  let count = address_bytes + data.length() + 1
  let body = Bytes::makei(1 + address_bytes + data.length(), index => {
    if index == 0 {
      count.to_byte()
    } else if index <= address_bytes {
      let shift = (address_bytes - index) * 8
      ((address >> shift) & 0xFFUL).to_byte()
    } else {
      data[index - address_bytes - 1]
    }
  })
  let checksum = Bytes::makei(1, _ => ones_complement_checksum(body))
  "S" +
  type_digit.to_string() +
  encode_hex_bytes(body) +
  encode_hex_bytes(checksum)
}

///|
fn ascii_header(text : String) -> Result[Bytes, FirmwareError] {
  if text.length() > 64 {
    return Err(conversion_error("S-record header is limited to 64 ASCII bytes"))
  }
  for index = 0; index < text.length(); index = index + 1 {
    if text[index].to_int() > 0x7F {
      return Err(conversion_error("S-record header must contain ASCII text"))
    }
  }
  Ok(Bytes::makei(text.length(), index => text[index].to_int().to_byte()))
}

///|
/// Deterministically export an image as Motorola S-record text.
pub fn FirmwareImage::to_srecord(
  self : FirmwareImage,
  record_bytes? : Int = 32,
  header? : String = "",
) -> Result[String, FirmwareError] {
  if record_bytes <= 0 || record_bytes > 250 {
    return Err(conversion_error("S-record data width must be 1 through 250"))
  }
  let highest = match (self.highest_address(), self.entry_point()) {
    (Some(left), Some(right)) => if left > right { left } else { right }
    (Some(value), None) | (None, Some(value)) => value
    _ => 0UL
  }
  if highest > 0xFFFFFFFFUL {
    return Err(
      conversion_error("S-record output is limited to 32-bit addresses"),
    )
  }
  let address_bytes = if highest <= 0xFFFFUL {
    2
  } else if highest <= 0xFFFFFFUL {
    3
  } else {
    4
  }
  let lines : Array[String] = []
  if header.length() > 0 {
    let header_data = match ascii_header(header) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    lines.push(encode_srecord_output(0, 2, 0UL, header_data))
  }
  let mut data_records = 0
  for segment in self.segments() {
    let source = segment.data()
    let mut offset = 0
    while offset < source.length() {
      let remaining = source.length() - offset
      let length = if remaining < record_bytes {
        remaining
      } else {
        record_bytes
      }
      let data = Bytes::makei(length, index => source[offset + index])
      lines.push(
        encode_srecord_output(
          srecord_output_type(address_bytes, 1),
          address_bytes,
          segment.address() + offset.to_uint64(),
          data,
        ),
      )
      data_records = data_records + 1
      offset = offset + length
    }
  }
  if data_records > 0xFFFFFF {
    return Err(conversion_error("S-record data record count exceeds 24 bits"))
  }
  let count_width = if data_records <= 0xFFFF { 2 } else { 3 }
  lines.push(
    encode_srecord_output(
      srecord_output_type(count_width, 2),
      count_width,
      data_records.to_uint64(),
      b"",
    ),
  )
  lines.push(
    encode_srecord_output(
      srecord_output_type(address_bytes, 3),
      address_bytes,
      self.entry_point().unwrap_or(0UL),
      b"",
    ),
  )
  Ok(join_record_lines(lines))
}
