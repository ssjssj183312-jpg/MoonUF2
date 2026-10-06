///|
fn hex_digit_value(code : Int) -> Int {
  if code >= 48 && code <= 57 {
    code - 48
  } else if code >= 65 && code <= 70 {
    code - 55
  } else if code >= 97 && code <= 102 {
    code - 87
  } else {
    -1
  }
}

///|
fn hex_character(value : Int) -> String {
  let digits = "0123456789ABCDEF"
  match digits[value & 0xF].to_char() {
    Some(character) => character.to_string()
    None => "?"
  }
}

///|
/// Decode an even-length hexadecimal string without ignoring whitespace.
pub fn decode_hex_bytes(
  text : String,
  line_index? : Int = 0,
) -> Result[Bytes, FirmwareError] {
  if text.length() % 2 != 0 {
    return Err(
      FirmwareError::new(
        HexOddLength,
        "hexadecimal input must contain an even number of digits",
        SourcePosition::line(line_index),
      ),
    )
  }
  for index = 0; index < text.length(); index = index + 1 {
    if hex_digit_value(text[index].to_int()) < 0 {
      return Err(
        FirmwareError::new(
          HexInvalidDigit,
          "hexadecimal input contains an invalid digit",
          SourcePosition::column(line_index, index),
        ),
      )
    }
  }
  Ok(
    Bytes::makei(text.length() / 2, index => {
      let high = hex_digit_value(text[index * 2].to_int())
      let low = hex_digit_value(text[index * 2 + 1].to_int())
      (high * 16 + low).to_byte()
    }),
  )
}

///|
/// Encode bytes using two uppercase hexadecimal digits per byte.
pub fn encode_hex_bytes(bytes : Bytes) -> String {
  let mut result = ""
  for byte in bytes {
    let value = byte.to_int()
    result = result + hex_character(value >> 4) + hex_character(value)
  }
  result
}

///|
/// Return the low eight bits of the sum of all bytes.
pub fn checksum_sum(bytes : Bytes) -> Int {
  let mut sum = 0
  for byte in bytes {
    sum = (sum + byte.to_int()) & 0xFF
  }
  sum
}

///|
/// Calculate the Intel HEX two's-complement checksum byte.
pub fn twos_complement_checksum(bytes : Bytes) -> Byte {
  (-checksum_sum(bytes) & 0xFF).to_byte()
}

///|
/// Verify a byte sequence that includes its Intel HEX checksum byte.
pub fn twos_complement_valid(bytes : Bytes) -> Bool {
  checksum_sum(bytes) == 0
}

///|
/// Calculate the Motorola S-record one's-complement checksum byte.
pub fn ones_complement_checksum(bytes : Bytes) -> Byte {
  (0xFF - checksum_sum(bytes)).to_byte()
}

///|
/// Verify a byte sequence that includes its S-record checksum byte.
pub fn ones_complement_valid(bytes : Bytes) -> Bool {
  checksum_sum(bytes) == 0xFF
}
