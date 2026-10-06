///|
/// A validated contiguous byte range with its source line.
pub struct FirmwareChunk {
  address_value : UInt64
  data_value : Bytes
  line_index_value : Int
} derive(Eq, Debug)

///|
fn FirmwareChunk::new(
  address : UInt64,
  data : Bytes,
  line_index : Int,
) -> FirmwareChunk {
  {
    address_value: address,
    data_value: Bytes::makei(data.length(), index => data[index]),
    line_index_value: line_index,
  }
}

///|
/// Create a chunk after checking that its address range is representable.
pub fn FirmwareChunk::create(
  address : UInt64,
  data : Bytes,
  line_index? : Int = 0,
) -> Result[FirmwareChunk, FirmwareError] {
  let length = data.length().to_uint64()
  if length > 0UL && address > 0xFFFFFFFFFFFFFFFFUL - (length - 1UL) {
    Err(
      FirmwareError::new(
        AddressOutOfRange,
        "firmware chunk address range overflows UInt64",
        SourcePosition::line(line_index),
      ),
    )
  } else {
    Ok(FirmwareChunk::new(address, data, line_index))
  }
}

///|
pub fn FirmwareChunk::address(self : FirmwareChunk) -> UInt64 {
  self.address_value
}

///|
pub fn FirmwareChunk::data(self : FirmwareChunk) -> Bytes {
  Bytes::makei(self.data_value.length(), index => self.data_value[index])
}

///|
pub fn FirmwareChunk::length(self : FirmwareChunk) -> Int {
  self.data_value.length()
}

///|
pub fn FirmwareChunk::end_exclusive(self : FirmwareChunk) -> UInt64 {
  self.address_value + self.data_value.length().to_uint64()
}

///|
pub fn FirmwareChunk::line_index(self : FirmwareChunk) -> Int {
  self.line_index_value
}
