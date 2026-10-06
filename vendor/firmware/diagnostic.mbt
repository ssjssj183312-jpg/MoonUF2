///|
pub(all) enum FirmwareErrorCode {
  HexOddLength
  HexInvalidDigit
  RecordEmpty
  RecordInvalidPrefix
  RecordInvalidType
  RecordLengthMismatch
  RecordTooLong
  ChecksumMismatch
  AddressOutOfRange
  ImageOverlap
  ImageInvalidRange
  IntegrityViolation
  DocumentMissingTerminator
  DocumentRecordAfterTerminator
  DocumentDuplicateMetadata
} derive(Eq, Debug)

///|
pub(all) struct SourcePosition {
  line_index_value : Int
  column_index_value : Int?
} derive(Eq, Debug)

///|
pub struct FirmwareError {
  code_value : String
  message_value : String
  position_value : SourcePosition
} derive(Eq, Debug)

///|
pub fn FirmwareErrorCode::code(self : FirmwareErrorCode) -> String {
  match self {
    HexOddLength => "hex.odd_length"
    HexInvalidDigit => "hex.invalid_digit"
    RecordEmpty => "record.empty"
    RecordInvalidPrefix => "record.invalid_prefix"
    RecordInvalidType => "record.invalid_type"
    RecordLengthMismatch => "record.length_mismatch"
    RecordTooLong => "record.too_long"
    ChecksumMismatch => "checksum.mismatch"
    AddressOutOfRange => "address.out_of_range"
    ImageOverlap => "image.overlap"
    ImageInvalidRange => "image.invalid_range"
    IntegrityViolation => "integrity.violation"
    DocumentMissingTerminator => "document.missing_terminator"
    DocumentRecordAfterTerminator => "document.record_after_terminator"
    DocumentDuplicateMetadata => "document.duplicate_metadata"
  }
}

///|
pub fn SourcePosition::line(line_index : Int) -> SourcePosition {
  { line_index_value: line_index, column_index_value: None }
}

///|
pub fn SourcePosition::column(
  line_index : Int,
  column_index : Int,
) -> SourcePosition {
  { line_index_value: line_index, column_index_value: Some(column_index) }
}

///|
pub fn SourcePosition::line_index(self : SourcePosition) -> Int {
  self.line_index_value
}

///|
pub fn SourcePosition::column_index(self : SourcePosition) -> Int? {
  self.column_index_value
}

///|
pub fn FirmwareError::new(
  code : FirmwareErrorCode,
  message : String,
  position : SourcePosition,
) -> FirmwareError {
  { code_value: code.code(), message_value: message, position_value: position }
}

///|
pub fn FirmwareError::code(self : FirmwareError) -> String {
  self.code_value
}

///|
pub fn FirmwareError::message(self : FirmwareError) -> String {
  self.message_value
}

///|
pub fn FirmwareError::position(self : FirmwareError) -> SourcePosition {
  self.position_value
}

///|
pub fn FirmwareError::line_index(self : FirmwareError) -> Int {
  self.position_value.line_index()
}

///|
pub fn FirmwareError::column_index(self : FirmwareError) -> Int? {
  self.position_value.column_index()
}
