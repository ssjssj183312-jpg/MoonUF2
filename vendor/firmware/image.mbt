///|
pub(all) enum OverlapPolicy {
  RejectOverlap
  AllowIdentical
  ReplaceExisting
} derive(Eq, Debug)

///|
pub struct ImageSegment {
  address_value : UInt64
  data_value : Bytes
} derive(Eq, Debug)

///|
pub(all) struct AddressGap {
  start_value : UInt64
  end_exclusive_value : UInt64
} derive(Eq, Debug)

///|
pub struct FirmwareImage {
  segment_values : Array[ImageSegment]
  entry_point_value : UInt64?
} derive(Eq, Debug)

///|
fn image_overlap_error(line_index : Int, address : UInt64) -> FirmwareError {
  FirmwareError::new(
    ImageOverlap,
    "firmware byte overlaps existing evidence at address " +
    address.to_string(radix=16),
    SourcePosition::line(line_index),
  )
}

///|
fn find_address(addresses : Array[UInt64], address : UInt64) -> (Int, Bool) {
  let mut low = 0
  let mut high = addresses.length()
  while low < high {
    let middle = low + (high - low) / 2
    if addresses[middle] < address {
      low = middle + 1
    } else {
      high = middle
    }
  }
  (low, low < addresses.length() && addresses[low] == address)
}

///|
fn canonical_segments(
  addresses : Array[UInt64],
  values : Array[Byte],
) -> Array[ImageSegment] {
  let segments : Array[ImageSegment] = []
  if addresses.length() == 0 {
    return segments
  }
  let mut start_index = 0
  for index = 1; index <= addresses.length(); index = index + 1 {
    let boundary = index == addresses.length() ||
      addresses[index] != addresses[index - 1] + 1UL
    if boundary {
      let length = index - start_index
      segments.push({
        address_value: addresses[start_index],
        data_value: Bytes::makei(length, offset => values[start_index + offset]),
      })
      start_index = index
    }
  }
  segments
}

///|
fn firmware_image_from_chunks(
  chunks : Array[FirmwareChunk],
  policy : OverlapPolicy,
  entry_point : UInt64?,
) -> Result[FirmwareImage, FirmwareError] {
  let addresses : Array[UInt64] = []
  let values : Array[Byte] = []
  let source_lines : Array[Int] = []
  for chunk in chunks {
    let data = chunk.data()
    for offset = 0; offset < data.length(); offset = offset + 1 {
      let address = chunk.address() + offset.to_uint64()
      let (index, exists) = find_address(addresses, address)
      if exists {
        match policy {
          RejectOverlap =>
            return Err(image_overlap_error(chunk.line_index(), address))
          AllowIdentical =>
            if values[index] != data[offset] {
              return Err(image_overlap_error(chunk.line_index(), address))
            }
          ReplaceExisting => {
            values[index] = data[offset]
            source_lines[index] = chunk.line_index()
          }
        }
      } else {
        addresses.insert(index, address)
        values.insert(index, data[offset])
        source_lines.insert(index, chunk.line_index())
      }
    }
  }
  Ok({
    segment_values: canonical_segments(addresses, values),
    entry_point_value: entry_point,
  })
}

///|
pub fn FirmwareImage::from_chunks(
  chunks : Array[FirmwareChunk],
  policy? : OverlapPolicy = RejectOverlap,
  entry_point? : UInt64? = None,
) -> Result[FirmwareImage, FirmwareError] {
  firmware_image_from_chunks(chunks, policy, entry_point)
}

///|
pub fn FirmwareImage::from_intel_document(
  document : IntelHexDocument,
  policy? : OverlapPolicy = RejectOverlap,
) -> Result[FirmwareImage, FirmwareError] {
  firmware_image_from_chunks(
    document.data_chunks(),
    policy,
    document.entry_point(),
  )
}

///|
pub fn FirmwareImage::from_srecord_document(
  document : SRecordDocument,
  policy? : OverlapPolicy = RejectOverlap,
) -> Result[FirmwareImage, FirmwareError] {
  firmware_image_from_chunks(
    document.data_chunks(),
    policy,
    document.entry_point(),
  )
}

///|
pub fn ImageSegment::address(self : ImageSegment) -> UInt64 {
  self.address_value
}

///|
pub fn ImageSegment::data(self : ImageSegment) -> Bytes {
  Bytes::makei(self.data_value.length(), index => self.data_value[index])
}

///|
pub fn ImageSegment::length(self : ImageSegment) -> Int {
  self.data_value.length()
}

///|
pub fn ImageSegment::end_exclusive(self : ImageSegment) -> UInt64 {
  self.address_value + self.data_value.length().to_uint64()
}

///|
pub fn AddressGap::start(self : AddressGap) -> UInt64 {
  self.start_value
}

///|
pub fn AddressGap::end_exclusive(self : AddressGap) -> UInt64 {
  self.end_exclusive_value
}

///|
pub fn AddressGap::length(self : AddressGap) -> UInt64 {
  self.end_exclusive_value - self.start_value
}

///|
pub fn FirmwareImage::segments(self : FirmwareImage) -> Array[ImageSegment] {
  self.segment_values.copy()
}

///|
pub fn FirmwareImage::entry_point(self : FirmwareImage) -> UInt64? {
  self.entry_point_value
}

///|
pub fn FirmwareImage::total_bytes(self : FirmwareImage) -> Int {
  let mut total = 0
  for segment in self.segment_values {
    total = total + segment.length()
  }
  total
}

///|
pub fn FirmwareImage::lowest_address(self : FirmwareImage) -> UInt64? {
  if self.segment_values.length() == 0 {
    None
  } else {
    Some(self.segment_values[0].address())
  }
}

///|
pub fn FirmwareImage::highest_address(self : FirmwareImage) -> UInt64? {
  if self.segment_values.length() == 0 {
    None
  } else {
    let last = self.segment_values[self.segment_values.length() - 1]
    Some(last.end_exclusive() - 1UL)
  }
}

///|
pub fn FirmwareImage::byte_at(self : FirmwareImage, address : UInt64) -> Byte? {
  for segment in self.segment_values {
    if address >= segment.address() && address < segment.end_exclusive() {
      return Some(segment.data_value[(address - segment.address()).to_int()])
    }
  }
  None
}

///|
pub fn FirmwareImage::gaps(self : FirmwareImage) -> Array[AddressGap] {
  let result : Array[AddressGap] = []
  for index = 1; index < self.segment_values.length(); index = index + 1 {
    let previous_end = self.segment_values[index - 1].end_exclusive()
    let next_start = self.segment_values[index].address()
    if previous_end < next_start {
      result.push({ start_value: previous_end, end_exclusive_value: next_start })
    }
  }
  result
}
