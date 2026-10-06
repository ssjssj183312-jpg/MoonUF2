///|
/// Node host bindings only: no firmware parsing or encoding lives in JavaScript.
#external
type ReadResult

///|
extern "js" fn arguments() -> FixedArray[String] =
  #| () => process.argv.slice(2)

///|
extern "js" fn stderr(message : String) -> Unit =
  #| (message) => { process.stderr.write(message + '\n'); }

///|
extern "js" fn set_exit_code(code : Int) -> Unit =
  #| (code) => { process.exitCode = code; }

///|
/// Open first, then bound and read the same descriptor. Reject devices/FIFOs.
extern "js" fn read_file(path : String, limit : Int) -> ReadResult =
  #| (path, limit) => {
  #|   const fs = require('node:fs');
  #|   let fd;
  #|   try {
  #|     fd = fs.openSync(path, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK);
  #|     const stat = fs.fstatSync(fd);
  #|     if (!stat.isFile()) return { error: 'io.input_type: 输入必须是普通文件' };
  #|     if (stat.size > limit) return { error: 'io.input_limit: 输入超过 --max-bytes 限制' };
  #|     const buffer = Buffer.alloc(stat.size + 1);
  #|     let size = 0;
  #|     while (size < buffer.length) {
  #|       const n = fs.readSync(fd, buffer, size, buffer.length - size, null);
  #|       if (n === 0) break;
  #|       size += n;
  #|     }
  #|     if (size !== stat.size) return { error: 'io.input_changed: 读取时输入大小发生变化，请重试' };
  #|     return { bytes: buffer.subarray(0, size), error: '' };
  #|   } catch (e) { return { error: 'io.read: ' + e.message }; }
  #|   finally { if (fd !== undefined) fs.closeSync(fd); }
  #| }

///|
extern "js" fn ReadResult::error(self : ReadResult) -> String =
  #| (result) => result.error

///|
extern "js" fn ReadResult::bytes(self : ReadResult) -> Bytes =
  #| (result) => result.bytes

///|
/// Publish a complete sibling temporary file without replacing an existing path.
extern "js" fn write_file(path : String, bytes : Bytes) -> String =
  #| (path, bytes) => {
  #|   const fs = require('node:fs');
  #|   const p = require('node:path');
  #|   let temporary;
  #|   let created = false;
  #|   try {
  #|     temporary = p.join(p.dirname(path), '.' + p.basename(path) + '.moonuf2-' + require('node:crypto').randomBytes(8).toString('hex'));
  #|     const fd = fs.openSync(temporary, 'wx', 0o600);
  #|     created = true;
  #|     try { fs.writeFileSync(fd, bytes); fs.fsyncSync(fd); }
  #|     finally { fs.closeSync(fd); }
  #|     fs.linkSync(temporary, path);
  #|     return '';
  #|   } catch (e) {
  #|     return 'io.write: ' + (e.code === 'EEXIST' ? '输出已存在，不会覆盖：' + path : e.message);
  #|   } finally { if (created) { try { fs.unlinkSync(temporary); } catch (_) {} } }
  #| }

///|
/// Text firmware is ASCII. Preserve bytes exactly, rejecting non-ASCII explicitly.
extern "js" fn ascii_text(bytes : Bytes) -> String =
  #| (bytes) => Buffer.from(bytes).toString('latin1')

///|
extern "js" fn utf8_bytes(text : String) -> Bytes =
  #| (text) => Buffer.from(text, 'utf8')
