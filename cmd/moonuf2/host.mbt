///|
/// 仅封装 Node.js 主机接口；固件解析与编码均不在 JavaScript 中实现。
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
/// 先打开文件，再检查大小并读取同一文件描述符；拒绝设备文件和命名管道。
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
  #|   } catch (e) {
  #|     const code = e && typeof e.code === 'string' ? e.code : 'UNKNOWN';
  #|     const reason = ({
  #|       ENOENT: '文件或路径不存在', EACCES: '没有访问权限', EPERM: '操作权限不足',
  #|       ENOTDIR: '路径中的目录无效', EISDIR: '目标是目录而不是普通文件',
  #|       EMFILE: '进程打开的文件过多', ENFILE: '系统打开的文件过多',
  #|       ENAMETOOLONG: '文件路径过长', EIO: '输入输出错误', EBADF: '文件描述符无效'
  #|     })[code] || '系统读取失败';
  #|     return { error: 'io.read: 读取文件失败：' + reason + '（' + code + '）' };
  #|   }
  #|   finally { if (fd !== undefined) fs.closeSync(fd); }
  #| }

///|
extern "js" fn ReadResult::error(self : ReadResult) -> String =
  #| (result) => result.error

///|
extern "js" fn ReadResult::bytes(self : ReadResult) -> Bytes =
  #| (result) => result.bytes

///|
/// 在目标目录完整写入临时文件，再发布结果；不替换任何已有路径。
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
  #|     const code = e && typeof e.code === 'string' ? e.code : 'UNKNOWN';
  #|     const reason = ({
  #|       ENOENT: '输出目录不存在', EACCES: '没有访问权限', EPERM: '操作权限不足',
  #|       ENOSPC: '存储空间不足', EDQUOT: '存储配额不足', EROFS: '文件系统只读',
  #|       ENOTDIR: '路径中的目录无效', EISDIR: '输出路径是目录',
  #|       EMFILE: '进程打开的文件过多', ENFILE: '系统打开的文件过多',
  #|       ENAMETOOLONG: '文件路径过长', EFBIG: '文件大小超过系统限制',
  #|       EXDEV: '无法跨文件系统发布输出', EIO: '输入输出错误', EBADF: '文件描述符无效'
  #|     })[code] || '系统写入失败';
  #|     return 'io.write: ' + (code === 'EEXIST' ? '输出已存在，不会覆盖：' + path : '写入文件失败：' + reason) + '（' + code + '）';
  #|   } finally { if (created) { try { fs.unlinkSync(temporary); } catch (_) {} } }
  #| }

///|
/// 文本固件使用 ASCII；完整保留原始字节，并明确拒绝非 ASCII 输入。
extern "js" fn ascii_text(bytes : Bytes) -> String =
  #| (bytes) => Buffer.from(bytes).toString('latin1')

///|
extern "js" fn utf8_bytes(text : String) -> Bytes =
  #| (text) => Buffer.from(text, 'utf8')
