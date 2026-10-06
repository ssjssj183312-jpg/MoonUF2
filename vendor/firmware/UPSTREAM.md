# 内置 firmware-image-toolkit 源码子集

- 作者及版权所有者：张泉义 (Zzqy-yi)
- 项目：https://github.com/Zzqy-yi/moonbit-firmware-image
- 原始模块：`Zzqy-yi/firmware-image-toolkit`
- 版本提交：`cd34551136a5c2663af48634ebc72d8ce8b6a8c0`
- 许可证：Apache-2.0；原始 `LICENSE` 和 `NOTICE` 文件均原样保留
- 本地包：`ssjssj183312-jpg/moonuf2/vendor/firmware`

本目录包含 MoonUF2 适配层所需的最小独立源码子集：Intel HEX 与 Motorola
S-record 的编解码器和文档模型、稀疏 FirmwareImage 与 FirmwareChunk 类型、
诊断信息、校验和、文本分行及文本导出器。十个 `.mbt` 文件均从上述提交逐字节
复制。`docs/references.md` 也保持原样。`SHA256SUMS` 记录这些副本的校验值；
运行 `sha256sum -c SHA256SUMS` 可验证其完整性。

本地 `moon.pkg`、本来源说明和 `SHA256SUMS` 是 MoonUF2 新增的打包文件。
这些文件不表示上游作者维护或认可 MoonUF2。没有将任何上游代码改写或重新
标注为 MoonUF2 的原创实现。上游较高层的审计、报告接口，以及示例和测试套件
被有意省略；本目录不是上游模块的完整镜像。

## 集成行为

上游镜像模型只存储实际地址上的字节，不为空洞分配内存。其规范化逻辑逐字节
插入有序数组，因此逆序记录可能产生相对于实际字节数的平方级时间开销。
适配层会在调用该逻辑前按地址排序数据块。适配层不会填充空洞、重新解释地址，
也不会启用重叠字节替换。

适配层在接受或导出 MoonUF2 镜像前检查 32 位数据地址范围。这补充了上游
S-record 解析器的行为：上游可能接受起始地址小于 2^32、但载荷末端越过该
边界的记录。所有上游源码均保持不变。
