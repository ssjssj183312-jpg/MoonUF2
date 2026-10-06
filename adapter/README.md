# 固件镜像适配层

将 `ssjssj183312-jpg/moonuf2/adapter` 与根 UF2 包一起导入。
适配层使用 `../vendor/firmware` 中保留原始署名的上游源码。

## 公开接口

- `intel_hex_to_image(text, family? = None, discard_metadata? = false)`
- `srecord_to_image(text, family? = None, discard_metadata? = false)`
- `image_to_intel_hex(image, record_bytes? = 16, discard_metadata? = false)`
- `image_to_srecord(image, record_bytes? = 32, entry_point? = None, header? = "", discard_metadata? = false)`
- `from_firmware_image(image, family? = None, discard_metadata? = false)`
- `to_firmware_image(image, entry_point? = None, discard_metadata? = false)`

所有函数均返回 `Result[..., AdapterError]`。`AdapterError` 提供
`code()`、`message()` 和从零开始计数的 `line_index()`；适用时保留原始
上游 `FirmwareError`。文本导入会拒绝错误校验和、缺少终止记录、冲突或
重复的元数据、格式错误的记录，以及所有数据重叠，包括字节完全相同的重叠。
结构化错误对象中的上游诊断原文保持不变；`message()` 按上游错误码提供中文
概括并附带源文件行号，适配层新增的诊断说明也使用中文。

## 稀疏数据与元数据语义

转换保留数据字节及其绝对地址，不填充地址空洞，也不会隐式补零或补 `0xFF`。
相邻源记录可能合并为一个规范化数据段。输出的记录布局、字母大小写、换行符、
计数记录和扩展地址记录不必与输入文本一致。

根 UF2 `Image` 无法表达 Intel HEX 起始地址记录或 S-record 的入口地址和
头记录，因此默认拒绝会丢失这些信息的导入。设置 `discard_metadata=true`
表示显式允许只转换数据。完整的 S-record 文档总是带有终止地址，即使该地址
为零；因此导入 S-record 时始终需要作出这一显式选择。

同样，标准 HEX/S-record 格式没有存储 UF2 芯片家族 ID 的字段。默认情况下，
含有芯片家族 ID 的镜像会被拒绝导出。显式允许丢弃后，数据字节会被导出，但
芯片家族 ID 会丢失。导入时传入的 `family` 是调用方新提供的元数据，
并非从文本中恢复的信息。

S-record 输出必须包含终止记录。除非显式提供 `entry_point`，上游导出器会
将终止地址写为零；这不代表推断出的启动入口地址。可选的输出头记录是调用方
新提供的文本，最多包含 64 个 ASCII 字节。Intel HEX 输出不包含入口地址，
因为根 UF2 `Image` 没有该字段。需要主动添加入口地址时，可调用上游桥接接口
并显式传入入口地址，再使用上游导出方法。

适配层要求实际数据位于 32 位地址范围内。根 UF2 编解码器可能施加额外限制，
包括地址和载荷的对齐要求；适配层不会为了满足这些规则而静默补齐或重定位文本
数据。导出会拒绝重叠或为空的根镜像数据段。Intel HEX 记录宽度为 1–255 字节，
S-record 数据宽度为 1–250 字节。

适配层会先按地址排序解析所得的数据块和根镜像数据段，再调用上游规范化逻辑，
避免逆序记录产生平方级插入开销。每个数据块仍保留解析器记录的原始源文件行号。
对于有效且互不重叠的数据，排序后的逐字节存储只需要向末尾追加。稀疏地址空洞
不会分配稠密内存。直接使用原始内置上游接口时，不会自动获得这项排序保护。

HEX → UF2：先调用 `intel_hex_to_image`，再调用根包的 `encode`。
UF2 → HEX：先调用根包的 `decode`，再调用 `image_to_intel_hex`。
S-record 使用对应接口，并显式允许必要的元数据丢失。

## 公开接口的资源限制

两个文本导入函数都会在调用上游解析器之前，拒绝长度超过 16 MiB 的输入。
有效固件文本使用 ASCII，因此字符长度与字节长度一致。线性时间的预检查会
拒绝超过最长合法记录长度（521 个字符）的单行，防止超长畸形行进入上游通过
拼接字符串实现的分行器。LF、CRLF 和 CR 文本的源文件行号均会保留。

所有桥接和导出路径都会在规范化前拒绝超过 16 MiB 的实际数据。统计的是传入
数据块的字节数，包括重叠部分；稀疏地址跨度不计入数据量。超限错误码为
`adapter.resource_limit`；超长文本记录使用上游风格的 `record.too_long`
错误码，并附带原始的、从零开始计数的源文件行号。

这些上限直接保护库调用方，不依赖命令行工具的限制。它们限制可接受的输入，
但不构成恒定内存或流式处理保证。导出的文本可能比原始数据字节更大。

适配层的 22 项测试均在 native、wasm-gc 和 JS 目标上通过。除格式校验和
稀疏往返转换外，还测试了 32,768 条逆序 Intel HEX 数据记录、16,384 条逆序
S-record 数据记录、16,384 个逆序根镜像段、超限输入和数据拒绝行为，以及
超长行的源文件位置。运行 `moon test adapter --target native`，也可以将
目标替换为 `wasm-gc` 或 `js`。
