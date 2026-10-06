///|
pub struct SRecordDocument {
  record_values : Array[SRecord]
  header_value : Bytes?
  chunk_values : Array[FirmwareChunk]
  declared_data_count_value : Int?
  entry_point_value : UInt64?
} derive(Eq, Debug)

///|
fn srecord_document_error(
  code : FirmwareErrorCode,
  message : String,
  line_index : Int,
) -> FirmwareError {
  FirmwareError::new(code, message, SourcePosition::line(line_index))
}

///|
/// Parse a complete S-record document and validate its bookkeeping records.
pub fn parse_srecord_document(
  text : String,
) -> Result[SRecordDocument, FirmwareError] {
  let lines = split_firmware_lines(text)
  let records : Array[SRecord] = []
  let chunks : Array[FirmwareChunk] = []
  let mut header : Bytes? = None
  let mut declared_count : Int? = None
  let mut entry_point : UInt64? = None
  let mut data_count = 0
  let mut widest_data_address = 0
  let mut terminated = false
  for line_index, line in lines {
    if terminated {
      return Err(
        srecord_document_error(
          DocumentRecordAfterTerminator,
          "S-record appears after the termination record",
          line_index,
        ),
      )
    }
    let record = match parse_srecord(line, line_index~) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    records.push(record)
    match record.record_type() {
      SHeader => {
        if header is Some(_) || data_count > 0 {
          return Err(
            srecord_document_error(
              DocumentDuplicateMetadata,
              "S-record header must appear once before data records",
              line_index,
            ),
          )
        }
        header = Some(record.data())
      }
      SData16 | SData24 | SData32 => {
        data_count = data_count + 1
        let width = record.record_type().address_bytes()
        if width > widest_data_address {
          widest_data_address = width
        }
        chunks.push(
          FirmwareChunk::new(record.address(), record.data(), line_index),
        )
      }
      SCount16 | SCount24 => {
        if declared_count is Some(_) {
          return Err(
            srecord_document_error(
              DocumentDuplicateMetadata,
              "S-record data count appears more than once",
              line_index,
            ),
          )
        }
        declared_count = Some(record.address().to_int())
      }
      STerminate16 | STerminate24 | STerminate32 => {
        let expected = match widest_data_address {
          2 => STerminate16
          3 => STerminate24
          4 => STerminate32
          _ => record.record_type()
        }
        if record.record_type() != expected {
          return Err(
            srecord_document_error(
              IntegrityViolation,
              "S-record termination width does not match data address width",
              line_index,
            ),
          )
        }
        if record.address() != 0UL {
          entry_point = Some(record.address())
        } else {
          entry_point = Some(0UL)
        }
        terminated = true
      }
    }
  }
  if !terminated {
    return Err(
      srecord_document_error(
        DocumentMissingTerminator,
        "S-record document is missing its termination record",
        lines.length(),
      ),
    )
  }
  match declared_count {
    Some(expected) if expected != data_count =>
      return Err(
        srecord_document_error(
          IntegrityViolation,
          "S-record declared data count does not match data records",
          0,
        ),
      )
    _ => ()
  }
  Ok({
    record_values: records,
    header_value: header,
    chunk_values: chunks,
    declared_data_count_value: declared_count,
    entry_point_value: entry_point,
  })
}

///|
pub fn SRecordDocument::records(self : SRecordDocument) -> Array[SRecord] {
  self.record_values.copy()
}

///|
pub fn SRecordDocument::header(self : SRecordDocument) -> Bytes? {
  match self.header_value {
    Some(data) => Some(Bytes::makei(data.length(), index => data[index]))
    None => None
  }
}

///|
pub fn SRecordDocument::data_chunks(
  self : SRecordDocument,
) -> Array[FirmwareChunk] {
  self.chunk_values.copy()
}

///|
pub fn SRecordDocument::declared_data_count(self : SRecordDocument) -> Int? {
  self.declared_data_count_value
}

///|
pub fn SRecordDocument::entry_point(self : SRecordDocument) -> UInt64? {
  self.entry_point_value
}
