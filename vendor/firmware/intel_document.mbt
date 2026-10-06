///|
pub struct IntelHexDocument {
  record_values : Array[IntelHexRecord]
  chunk_values : Array[FirmwareChunk]
  entry_point_value : UInt64?
} derive(Eq, Debug)

///|
fn metadata_value(bytes : Bytes) -> UInt64 {
  let mut value = 0UL
  for byte in bytes {
    value = value * 256UL + byte.to_uint64()
  }
  value
}

///|
fn intel_document_error(
  code : FirmwareErrorCode,
  message : String,
  line_index : Int,
) -> FirmwareError {
  FirmwareError::new(code, message, SourcePosition::line(line_index))
}

///|
/// Parse a complete Intel HEX document and resolve data addresses.
pub fn parse_intel_hex_document(
  text : String,
) -> Result[IntelHexDocument, FirmwareError] {
  let lines = split_firmware_lines(text)
  let records : Array[IntelHexRecord] = []
  let chunks : Array[FirmwareChunk] = []
  let mut base_address = 0UL
  let mut entry_point : UInt64? = None
  let mut terminated = false
  for line_index, line in lines {
    if terminated {
      return Err(
        intel_document_error(
          DocumentRecordAfterTerminator,
          "Intel HEX record appears after the EOF record",
          line_index,
        ),
      )
    }
    let record = match parse_intel_hex_record(line, line_index~) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    records.push(record)
    match record.record_type() {
      IntelData => {
        let absolute = base_address + record.address().to_uint64()
        let length = record.byte_count().to_uint64()
        if length > 0UL && absolute + length - 1UL > 0xFFFFFFFFUL {
          return Err(
            intel_document_error(
              AddressOutOfRange,
              "Intel HEX data range exceeds the 32-bit address space",
              line_index,
            ),
          )
        }
        chunks.push(FirmwareChunk::new(absolute, record.data(), line_index))
      }
      IntelEndOfFile => terminated = true
      IntelExtendedSegmentAddress =>
        base_address = metadata_value(record.data()) << 4
      IntelExtendedLinearAddress =>
        base_address = metadata_value(record.data()) << 16
      IntelStartSegmentAddress => {
        if entry_point is Some(_) {
          return Err(
            intel_document_error(
              DocumentDuplicateMetadata,
              "Intel HEX document contains multiple start addresses",
              line_index,
            ),
          )
        }
        let data = record.data()
        let code_segment = data[0].to_uint64() * 256UL + data[1].to_uint64()
        let instruction = data[2].to_uint64() * 256UL + data[3].to_uint64()
        entry_point = Some((code_segment << 4) + instruction)
      }
      IntelStartLinearAddress => {
        if entry_point is Some(_) {
          return Err(
            intel_document_error(
              DocumentDuplicateMetadata,
              "Intel HEX document contains multiple start addresses",
              line_index,
            ),
          )
        }
        entry_point = Some(metadata_value(record.data()))
      }
    }
  }
  if !terminated {
    return Err(
      intel_document_error(
        DocumentMissingTerminator,
        "Intel HEX document is missing its EOF record",
        lines.length(),
      ),
    )
  }
  Ok({
    record_values: records,
    chunk_values: chunks,
    entry_point_value: entry_point,
  })
}

///|
pub fn IntelHexDocument::records(
  self : IntelHexDocument,
) -> Array[IntelHexRecord] {
  self.record_values.copy()
}

///|
pub fn IntelHexDocument::data_chunks(
  self : IntelHexDocument,
) -> Array[FirmwareChunk] {
  self.chunk_values.copy()
}

///|
pub fn IntelHexDocument::entry_point(self : IntelHexDocument) -> UInt64? {
  self.entry_point_value
}
