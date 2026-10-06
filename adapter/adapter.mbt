///|
/// Conversion errors preserve upstream parser diagnostics. Metadata loss is
/// rejected unless the caller explicitly supplies `discard_metadata=true`.
pub(all) enum AdapterError {
  Firmware(@firmware.FirmwareError)
  MetadataLoss(String)
  InvalidImage(String)
  ResourceLimit(String)
} derive(Eq, Debug)

///|
pub fn AdapterError::code(self : AdapterError) -> String {
  match self {
    Firmware(error) => error.code()
    MetadataLoss(_) => "adapter.metadata_loss"
    InvalidImage(_) => "adapter.invalid_image"
    ResourceLimit(_) => "adapter.resource_limit"
  }
}

///|
pub fn AdapterError::message(self : AdapterError) -> String {
  match self {
    Firmware(error) =>
      error.message() +
      " (source line " +
      (error.line_index() + 1).to_string() +
      ")"
    MetadataLoss(message) | InvalidImage(message) | ResourceLimit(message) =>
      message
  }
}

///|
/// Original zero-based source line for parser errors, when available.
pub fn AdapterError::line_index(self : AdapterError) -> Int? {
  match self {
    Firmware(error) => Some(error.line_index())
    _ => None
  }
}

///|
fn check_range(address : UInt64, length : Int) -> Result[Unit, AdapterError] {
  if address > 0xFFFFFFFFUL || length.to_uint64() > 0x100000000UL - address {
    Err(InvalidImage("data range exceeds the 32-bit UF2 address space"))
  } else {
    Ok(())
  }
}

///|
/// All public adapter paths limit populated bytes to 16 MiB. Valid text is
/// ASCII; its input length is limited to 16 MiB before parsing.
fn check_byte_budget(
  current : Int,
  additional : Int,
) -> Result[Int, AdapterError] {
  if additional > 16777216 - current {
    Err(ResourceLimit("populated image data exceeds the 16 MiB adapter limit"))
  } else {
    Ok(current + additional)
  }
}

///|
fn check_text_budget(text : String) -> Result[Unit, AdapterError] {
  if text.length() > 16777216 {
    return Err(
      ResourceLimit("firmware text exceeds the 16 MiB adapter input limit"),
    )
  }
  // Bound work before the upstream line splitter copies/concatenates text.
  // The longest legal Intel HEX record is 521 ASCII characters; S-records
  // are shorter. Original upstream line positions remain unchanged.
  let mut line_length = 0
  let mut line_index = 0
  let mut was_cr = false
  for index = 0; index < text.length(); index = index + 1 {
    let code = text[index].to_int()
    if code == 13 || code == 10 {
      if code == 13 || !was_cr {
        line_index = line_index + 1
      }
      was_cr = code == 13
      line_length = 0
    } else {
      was_cr = false
      line_length = line_length + 1
      if line_length > 521 {
        return Err(
          Firmware(
            @firmware.FirmwareError::new(
              @firmware.RecordTooLong,
              "firmware text line exceeds the maximum 521-character record length",
              @firmware.SourcePosition::line(line_index),
            ),
          ),
        )
      }
    }
  }
  Ok(())
}

///|
fn normalize_chunks(
  chunks : Array[@firmware.FirmwareChunk],
  entry_point : UInt64?,
) -> Result[@firmware.FirmwareImage, AdapterError] {
  let mut populated = 0
  for chunk in chunks {
    match check_range(chunk.address(), chunk.length()) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    populated = match check_byte_budget(populated, chunk.length()) {
      Err(error) => return Err(error)
      Ok(total) => total
    }
  }
  // Sorting preserves each chunk's original source line, while preventing
  // quadratic array insertion for reverse-ordered non-overlapping records.
  chunks.sort_by((left, right) => left.address().compare(right.address()))
  match @firmware.FirmwareImage::from_chunks(chunks, entry_point~) {
    Err(error) => Err(Firmware(error))
    Ok(image) => Ok(image)
  }
}

///|
/// Convert an existing upstream sparse image into a UF2 image. No gap is
/// filled. The optional family is newly supplied UF2 metadata; upstream has no
/// family ID. Start-address metadata requires explicit permission to discard.
pub fn from_firmware_image(
  image : @firmware.FirmwareImage,
  family? : UInt? = None,
  discard_metadata? : Bool = false,
) -> Result[@uf2.Image, AdapterError] {
  if image.entry_point() is Some(_) && !discard_metadata {
    return Err(
      MetadataLoss(
        "UF2 cannot retain the firmware entry point; explicitly enable discard_metadata to continue",
      ),
    )
  }
  let segments : Array[@uf2.Segment] = []
  let mut populated = 0
  for segment in image.segments() {
    populated = match check_byte_budget(populated, segment.length()) {
      Err(error) => return Err(error)
      Ok(total) => total
    }
    match check_range(segment.address(), segment.length()) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    segments.push({ address: segment.address(), data: segment.data(), })
  }
  Ok({ segments, family, })
}

///|
/// Convert a UF2 image to the upstream sparse model. Reject overlapping or
/// empty segments and out-of-range addresses. UF2 family IDs have no field in
/// HEX/S-record and need explicit permission to discard. The caller may add
/// a new entry point for an export; it is never inferred from a data address.
pub fn to_firmware_image(
  image : @uf2.Image,
  entry_point? : UInt64? = None,
  discard_metadata? : Bool = false,
) -> Result[@firmware.FirmwareImage, AdapterError] {
  if image.family is Some(_) && !discard_metadata {
    return Err(
      MetadataLoss(
        "Intel HEX and S-record cannot retain the UF2 family ID; explicitly enable discard_metadata to continue",
      ),
    )
  }
  match entry_point {
    Some(address) if address > 0xFFFFFFFFUL =>
      return Err(InvalidImage("entry point exceeds the 32-bit address space"))
    _ => ()
  }
  let chunks : Array[@firmware.FirmwareChunk] = []
  let mut populated = 0
  for index, segment in image.segments {
    populated = match check_byte_budget(populated, segment.data.length()) {
      Err(error) => return Err(error)
      Ok(total) => total
    }
    if segment.data.length() == 0 {
      return Err(InvalidImage("image contains an empty segment"))
    }
    match check_range(segment.address, segment.data.length()) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match
      @firmware.FirmwareChunk::create(
        segment.address,
        segment.data,
        line_index=index,
      ) {
      Err(error) => return Err(Firmware(error))
      Ok(chunk) => chunks.push(chunk)
    }
  }
  normalize_chunks(chunks, entry_point)
}

///|
/// Parse validated Intel HEX into a sparse image, rejecting all overlapping
/// records. Checksums, EOF and address metadata are checked upstream.
pub fn intel_hex_to_image(
  text : String,
  family? : UInt? = None,
  discard_metadata? : Bool = false,
) -> Result[@uf2.Image, AdapterError] {
  match check_text_budget(text) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let document = match @firmware.parse_intel_hex_document(text) {
    Err(error) => return Err(Firmware(error))
    Ok(document) => document
  }
  let image = match
    normalize_chunks(document.data_chunks(), document.entry_point()) {
    Err(error) => return Err(error)
    Ok(image) => image
  }
  from_firmware_image(image, family~, discard_metadata~)
}

///|
/// Parse validated Motorola S-record into a sparse image. Every complete
/// S-record document has a termination entry point (including zero), so this
/// conversion requires `discard_metadata=true`. A header is also non-data
/// metadata and cannot be retained in the UF2 image.
pub fn srecord_to_image(
  text : String,
  family? : UInt? = None,
  discard_metadata? : Bool = false,
) -> Result[@uf2.Image, AdapterError] {
  match check_text_budget(text) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let document = match @firmware.parse_srecord_document(text) {
    Err(error) => return Err(Firmware(error))
    Ok(document) => document
  }
  if document.header() is Some(_) && !discard_metadata {
    return Err(
      MetadataLoss(
        "UF2 cannot retain the S-record header or entry point; explicitly enable discard_metadata to continue",
      ),
    )
  }
  let image = match
    normalize_chunks(document.data_chunks(), document.entry_point()) {
    Err(error) => return Err(error)
    Ok(image) => image
  }
  from_firmware_image(image, family~, discard_metadata~)
}

///|
/// Write sparse Intel HEX without materializing gaps. Records are canonical,
/// not a byte-for-byte reconstruction of the input text.
pub fn image_to_intel_hex(
  image : @uf2.Image,
  record_bytes? : Int = 16,
  discard_metadata? : Bool = false,
) -> Result[String, AdapterError] {
  let firmware = match to_firmware_image(image, discard_metadata~) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  match firmware.to_intel_hex(record_bytes~) {
    Err(error) => Err(Firmware(error))
    Ok(text) => Ok(text)
  }
}

///|
/// Write sparse S-record. If no entry point is supplied, the required
/// termination record contains zero, as specified by the upstream exporter;
/// this is a format placeholder, not an inferred boot entry point. A supplied
/// header is new output metadata. Record widths are validated upstream.
pub fn image_to_srecord(
  image : @uf2.Image,
  record_bytes? : Int = 32,
  entry_point? : UInt64? = None,
  header? : String = "",
  discard_metadata? : Bool = false,
) -> Result[String, AdapterError] {
  let firmware = match
    to_firmware_image(image, entry_point~, discard_metadata~) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  match firmware.to_srecord(record_bytes~, header~) {
    Err(error) => Err(Firmware(error))
    Ok(text) => Ok(text)
  }
}
