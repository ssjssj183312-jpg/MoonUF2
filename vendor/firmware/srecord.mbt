///|
pub(all) enum SRecordType {
  SHeader
  SData16
  SData24
  SData32
  SCount16
  SCount24
  STerminate32
  STerminate24
  STerminate16
} derive(Eq, Debug)

///|
pub struct SRecord {
  record_type_value : SRecordType
  address_value : UInt64
  data_value : Bytes
  checksum_value : Byte
  line_index_value : Int
} derive(Eq, Debug)

///|
fn srecord_error(
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
fn srecord_type(
  code : Int,
  line_index : Int,
) -> Result[SRecordType, FirmwareError] {
  match code {
    48 => Ok(SHeader)
    49 => Ok(SData16)
    50 => Ok(SData24)
    51 => Ok(SData32)
    53 => Ok(SCount16)
    54 => Ok(SCount24)
    55 => Ok(STerminate32)
    56 => Ok(STerminate24)
    57 => Ok(STerminate16)
    _ =>
      Err(
        srecord_error(
          RecordInvalidType,
          "S-record type must be S0, S1, S2, S3, S5, S6, S7, S8 or S9",
          line_index,
          column_index=Some(1),
        ),
      )
  }
}

///|
fn SRecordType::type_digit(self : SRecordType) -> String {
  match self {
    SHeader => "0"
    SData16 => "1"
    SData24 => "2"
    SData32 => "3"
    SCount16 => "5"
    SCount24 => "6"
    STerminate32 => "7"
    STerminate24 => "8"
    STerminate16 => "9"
  }
}

///|
pub fn SRecordType::address_bytes(self : SRecordType) -> Int {
  match self {
    SHeader | SData16 | SCount16 | STerminate16 => 2
    SData24 | SCount24 | STerminate24 => 3
    SData32 | STerminate32 => 4
  }
}

///|
pub fn SRecordType::is_data(self : SRecordType) -> Bool {
  match self {
    SData16 | SData24 | SData32 => true
    _ => false
  }
}

///|
pub fn SRecordType::is_count(self : SRecordType) -> Bool {
  self == SCount16 || self == SCount24
}

///|
pub fn SRecordType::is_termination(self : SRecordType) -> Bool {
  self == STerminate16 || self == STerminate24 || self == STerminate32
}

///|
fn address_from_bytes(bytes : Bytes, start : Int, length : Int) -> UInt64 {
  let mut value = 0UL
  for index = 0; index < length; index = index + 1 {
    value = value * 256UL + bytes[start + index].to_uint64()
  }
  value
}

///|
fn validate_srecord_shape(
  record_type : SRecordType,
  data_length : Int,
  line_index : Int,
) -> Result[Unit, FirmwareError] {
  if (record_type.is_count() || record_type.is_termination()) &&
    data_length != 0 {
    Err(
      srecord_error(
        RecordLengthMismatch,
        "S-record count and termination records cannot contain data bytes",
        line_index,
      ),
    )
  } else {
    Ok(())
  }
}

///|
/// Parse and validate one Motorola S-record line.
pub fn parse_srecord(
  line : String,
  line_index? : Int = 0,
) -> Result[SRecord, FirmwareError] {
  if line.length() == 0 {
    return Err(srecord_error(RecordEmpty, "S-record is empty", line_index))
  }
  if line.length() < 2 || line[0].to_int() != 83 {
    return Err(
      srecord_error(
        RecordInvalidPrefix,
        "S-record must start with an uppercase S and a type digit",
        line_index,
        column_index=Some(0),
      ),
    )
  }
  let record_type = match srecord_type(line[1].to_int(), line_index) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let bytes = match decode_hex_bytes(line[2:].to_owned(), line_index~) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if bytes.length() < 2 {
    return Err(
      srecord_error(
        RecordLengthMismatch,
        "S-record is shorter than its count and checksum fields",
        line_index,
      ),
    )
  }
  let count = bytes[0].to_int()
  if bytes.length() != count + 1 {
    return Err(
      srecord_error(
        RecordLengthMismatch,
        "S-record count does not match the encoded record length",
        line_index,
        column_index=Some(2),
      ),
    )
  }
  let address_length = record_type.address_bytes()
  if count < address_length + 1 {
    return Err(
      srecord_error(
        RecordLengthMismatch,
        "S-record count is too small for its address and checksum",
        line_index,
      ),
    )
  }
  if !ones_complement_valid(bytes) {
    return Err(
      srecord_error(
        ChecksumMismatch,
        "S-record checksum does not match the record bytes",
        line_index,
        column_index=Some(line.length() - 2),
      ),
    )
  }
  let data_length = count - address_length - 1
  match validate_srecord_shape(record_type, data_length, line_index) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let address = address_from_bytes(bytes, 1, address_length)
  let data = Bytes::makei(data_length, index => {
    bytes[1 + address_length + index]
  })
  Ok({
    record_type_value: record_type,
    address_value: address,
    data_value: data,
    checksum_value: bytes[bytes.length() - 1],
    line_index_value: line_index,
  })
}

///|
pub fn SRecord::record_type(self : SRecord) -> SRecordType {
  self.record_type_value
}

///|
pub fn SRecord::address(self : SRecord) -> UInt64 {
  self.address_value
}

///|
pub fn SRecord::data(self : SRecord) -> Bytes {
  Bytes::makei(self.data_value.length(), index => self.data_value[index])
}

///|
pub fn SRecord::byte_count(self : SRecord) -> Int {
  self.record_type_value.address_bytes() + self.data_value.length() + 1
}

///|
pub fn SRecord::checksum(self : SRecord) -> Byte {
  self.checksum_value
}

///|
pub fn SRecord::line_index(self : SRecord) -> Int {
  self.line_index_value
}

///|
/// Encode a validated record using uppercase hexadecimal digits.
pub fn SRecord::encode(self : SRecord) -> String {
  let address_length = self.record_type_value.address_bytes()
  let count = address_length + self.data_value.length() + 1
  let body = Bytes::makei(1 + address_length + self.data_value.length(), index => {
    if index == 0 {
      count.to_byte()
    } else if index <= address_length {
      let shift = (address_length - index) * 8
      ((self.address_value >> shift) & 0xFFUL).to_byte()
    } else {
      self.data_value[index - address_length - 1]
    }
  })
  let checksum = Bytes::makei(1, _ => ones_complement_checksum(body))
  "S" +
  self.record_type_value.type_digit() +
  encode_hex_bytes(body) +
  encode_hex_bytes(checksum)
}
