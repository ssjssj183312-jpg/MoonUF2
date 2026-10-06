///|
pub(all) enum IntelRecordType {
  IntelData
  IntelEndOfFile
  IntelExtendedSegmentAddress
  IntelStartSegmentAddress
  IntelExtendedLinearAddress
  IntelStartLinearAddress
} derive(Eq, Debug)

///|
pub struct IntelHexRecord {
  record_type_value : IntelRecordType
  address_value : Int
  data_value : Bytes
  checksum_value : Byte
  line_index_value : Int
} derive(Eq, Debug)

///|
fn intel_error(
  code : FirmwareErrorCode,
  message : String,
  line_index : Int,
  column_index? : Int? = None,
) -> FirmwareError {
  let position = match column_index {
    Some(column) => SourcePosition::column(line_index, column)
    None => SourcePosition::line(line_index)
  }
  FirmwareError::new(code, message, position)
}

///|
fn intel_record_type(
  value : Int,
  line_index : Int,
) -> Result[IntelRecordType, FirmwareError] {
  match value {
    0 => Ok(IntelData)
    1 => Ok(IntelEndOfFile)
    2 => Ok(IntelExtendedSegmentAddress)
    3 => Ok(IntelStartSegmentAddress)
    4 => Ok(IntelExtendedLinearAddress)
    5 => Ok(IntelStartLinearAddress)
    _ =>
      Err(
        intel_error(
          RecordInvalidType,
          "Intel HEX record type must be in the range 00 through 05",
          line_index,
          column_index=Some(7),
        ),
      )
  }
}

///|
fn IntelRecordType::type_byte(self : IntelRecordType) -> Byte {
  match self {
    IntelData => 0
    IntelEndOfFile => 1
    IntelExtendedSegmentAddress => 2
    IntelStartSegmentAddress => 3
    IntelExtendedLinearAddress => 4
    IntelStartLinearAddress => 5
  }
}

///|
fn validate_intel_record_shape(
  record_type : IntelRecordType,
  address : Int,
  byte_count : Int,
  line_index : Int,
) -> Result[Unit, FirmwareError] {
  let required_count = match record_type {
    IntelData => None
    IntelEndOfFile => Some(0)
    IntelExtendedSegmentAddress => Some(2)
    IntelStartSegmentAddress => Some(4)
    IntelExtendedLinearAddress => Some(2)
    IntelStartLinearAddress => Some(4)
  }
  match required_count {
    Some(expected) if byte_count != expected =>
      Err(
        intel_error(
          RecordLengthMismatch,
          "Intel HEX metadata record has an invalid data byte count",
          line_index,
        ),
      )
    _ =>
      if record_type != IntelData && address != 0 {
        Err(
          intel_error(
            AddressOutOfRange,
            "Intel HEX metadata record address field must be zero",
            line_index,
            column_index=Some(3),
          ),
        )
      } else {
        Ok(())
      }
  }
}

///|
/// Parse and validate one Intel HEX line without accepting surrounding spaces.
pub fn parse_intel_hex_record(
  line : String,
  line_index? : Int = 0,
) -> Result[IntelHexRecord, FirmwareError] {
  if line.length() == 0 {
    return Err(
      intel_error(RecordEmpty, "Intel HEX record is empty", line_index),
    )
  }
  if line[0].to_int() != 58 {
    return Err(
      intel_error(
        RecordInvalidPrefix,
        "Intel HEX record must start with a colon",
        line_index,
        column_index=Some(0),
      ),
    )
  }
  let encoded = line[1:].to_owned()
  let bytes = match decode_hex_bytes(encoded, line_index~) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  guard bytes.length() >= 5 else {
    return Err(
      intel_error(
        RecordLengthMismatch,
        "Intel HEX record is shorter than its fixed fields",
        line_index,
      ),
    )
  }
  let byte_count = bytes[0].to_int()
  if bytes.length() != byte_count + 5 {
    return Err(
      intel_error(
        RecordLengthMismatch,
        "Intel HEX byte count does not match the encoded record length",
        line_index,
        column_index=Some(1),
      ),
    )
  }
  if !twos_complement_valid(bytes) {
    return Err(
      intel_error(
        ChecksumMismatch,
        "Intel HEX checksum does not match the record bytes",
        line_index,
        column_index=Some(line.length() - 2),
      ),
    )
  }
  let record_type = match intel_record_type(bytes[3].to_int(), line_index) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let address = bytes[1].to_int() * 256 + bytes[2].to_int()
  match
    validate_intel_record_shape(record_type, address, byte_count, line_index) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let data = Bytes::makei(byte_count, index => bytes[index + 4])
  Ok({
    record_type_value: record_type,
    address_value: address,
    data_value: data,
    checksum_value: bytes[bytes.length() - 1],
    line_index_value: line_index,
  })
}

///|
pub fn IntelHexRecord::record_type(self : IntelHexRecord) -> IntelRecordType {
  self.record_type_value
}

///|
pub fn IntelHexRecord::address(self : IntelHexRecord) -> Int {
  self.address_value
}

///|
pub fn IntelHexRecord::byte_count(self : IntelHexRecord) -> Int {
  self.data_value.length()
}

///|
pub fn IntelHexRecord::data(self : IntelHexRecord) -> Bytes {
  Bytes::makei(self.data_value.length(), index => self.data_value[index])
}

///|
pub fn IntelHexRecord::checksum(self : IntelHexRecord) -> Byte {
  self.checksum_value
}

///|
pub fn IntelHexRecord::line_index(self : IntelHexRecord) -> Int {
  self.line_index_value
}

///|
/// Encode a validated record using uppercase hexadecimal digits.
pub fn IntelHexRecord::encode(self : IntelHexRecord) -> String {
  let count = self.data_value.length()
  let body = Bytes::makei(count + 4, index => {
    if index == 0 {
      count.to_byte()
    } else if index == 1 {
      ((self.address_value >> 8) & 0xFF).to_byte()
    } else if index == 2 {
      (self.address_value & 0xFF).to_byte()
    } else if index == 3 {
      self.record_type_value.type_byte()
    } else {
      self.data_value[index - 4]
    }
  })
  let checksum = Bytes::makei(1, _ => twos_complement_checksum(body))
  ":" + encode_hex_bytes(body) + encode_hex_bytes(checksum)
}
