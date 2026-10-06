///|
/// Split text on CRLF, LF or CR while preserving empty interior lines.
fn split_firmware_lines(text : String) -> Array[String] {
  let lines : Array[String] = []
  let mut current = ""
  let mut previous_was_cr = false
  for index = 0; index < text.length(); index = index + 1 {
    let code = text[index].to_int()
    if code == 13 {
      lines.push(current)
      current = ""
      previous_was_cr = true
    } else if code == 10 {
      if !previous_was_cr {
        lines.push(current)
        current = ""
      }
      previous_was_cr = false
    } else {
      previous_was_cr = false
      let character = match text[index].to_char() {
        Some(value) => value.to_string()
        None => ""
      }
      current = current + character
    }
  }
  if current.length() > 0 ||
    (
      text.length() > 0 &&
      text[text.length() - 1].to_int() != 10 &&
      text[text.length() - 1].to_int() != 13
    ) {
    lines.push(current)
  }
  lines
}
