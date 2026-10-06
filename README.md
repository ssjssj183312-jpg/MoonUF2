# MoonUF2

用 MoonBit 实现的严格 UF2 编解码库和命令行工具。面向普通、单一 family 的 main-flash 固件；复用有清晰出处的 MoonBit Firmware Image Toolkit，连接 BIN、Intel HEX、Motorola S-record。

**它检查文件结构，不证明固件可信、适合目标板或可以安全烧录。不会寻找设备、写入闪存、校验签名或把魔数当作完整性校验。**

## 已实现

- 真正的 MoonBit UF2 解析/生成，全部多字节字段按 little-endian 处理
- 检查三个魔数、512 字节块、4 字节对齐、payload 4–476 字节、32 位地址范围
- 检查 blockNo/numBlocks、缺块、重复冲突、不同逻辑块的地址重叠、family 一致性/期望值
- 支持任意块顺序；同 blockNo、地址、payload 一致的重复块可接受，未使用 padding 不参与重复比较
- 稀疏镜像不展开空洞；BIN 展开必须符合跨度限制，默认空洞填 0xFF，可显式修改
- BIN / UF2 / HEX / Srec 的检查和转换；文本校验和、记录终止、地址范围由复用层验证
- JS、Wasm GC、native 库测试；CLI 为 Node.js 后端，仅文件 IO 使用 JS FFI，格式算法仍为 MoonBit

## 开始使用

已验证 MoonBit moon 0.1.20260920、moonc v0.10.14+7d59c7ec9，Node v24.19.0、Python 3.12.14。

```sh
# 已有兼容 MoonBit 和 Node 时：
moon test --target js
./scripts/moonuf2 --help

# Linux x86_64 可安装本项目哈希锁定的官方工具链至一个不存在的目录：
./scripts/install-toolchain.sh "$HOME/moonuf2-toolchain"
export MOON_HOME="$HOME/moonuf2-toolchain"
export PATH="$MOON_HOME/bin:$PATH"
```

安装脚本会先核对固定 SHA-256，再解包运行。官方 latest 地址变化时会主动失败，不能保证历史归档永久可用；见 [工具链锁定说明](docs/toolchain-lock.md)。

```sh
# BIN 的基址必须显式提供；数据长度和基址必须为 4 的倍数
./scripts/moonuf2 convert app.bin app.uf2 --from bin --to uf2 \
  --base 0x10000000 --family 0xe48bff56

./scripts/moonuf2 inspect app.uf2
./scripts/moonuf2 verify app.uf2 --family 0xe48bff56

# BIN 无法保存 family；显式同意丢失元数据，并记录程序输出的 base
./scripts/moonuf2 convert app.uf2 restored.bin --from uf2 --to bin \
  --discard-metadata --max-bytes 1048576 --fill 255

./scripts/moonuf2 convert app.uf2 app.hex --from uf2 --to hex --discard-metadata
./scripts/moonuf2 convert app.hex recovered.uf2 --from hex --to uf2 --family 0xe48bff56
./scripts/moonuf2 convert app.uf2 app.srec --from uf2 --to srec --discard-metadata
./scripts/moonuf2 convert app.srec from-srec.uf2 --from srec --to uf2 --discard-metadata
```

输入格式必须显式选择，不按扩展名猜测。输出文件必须不存在；拒绝覆盖已有文件。参数错误/格式失败返回非零退出码。`inspect` 和 `verify` 默认输入 UF2。非 UF2 可加 `--from`；BIN 输入另需 `--base`。文本的只读 `inspect`/`verify` 也使用严格适配器，入口点/header 会要求 `--discard-metadata`。

## 明确的范围和限制

1. 仅支持 flags=0 或 0x2000（family ID）。not-main-flash、file container、MD5、extension tags、未知位一律返回明确错误，不静默略过。多 family 拼接也拒绝；这是严格子集工具，不是所有 UF2 的完整实现。
2. `numBlocks` 必须非零且所有块一致；blockNo 范围为 0..numBlocks-1。不同 blockNo 的任何地址重叠都拒绝，即使数据相同。
3. 没有 family 标志时，文件大小/family 字段必须为零。可接受未指定 family 的普通文件；传 `--family` 后要求文件携带且匹配该 ID。匹配 family 仍不能证明板型/硬件配置正确。
4. 输入 UF2、输入 BIN、生成 UF2、展开 BIN 均有 16 MiB 硬上限。CLI 输入/输出默认 16 MiB，可调小，不能调大。稀疏数据地址仍可覆盖整个 32 位空间；展开超过上限的 BIN 被拒绝。这是逻辑数据上限，不是进程总内存上限；实现暂非流式。
5. 不隐式对齐、补齐或移动数据。非 4 字节对齐 BIN/文本数据不能直接生成 UF2。末块可小于 256 字节，但必须对齐；微软参考脚本会补零到 256，二者该场景不逐字节相同。
6. UF2 不存入口地址/S-record header，BIN/HEX/Srec 不存 UF2 family。会丢失这些信息的转换默认拒绝，需 `--discard-metadata`；S-record 终止记录始终含入口地址，因此导入也需该选项。导出 Srec 未显式指定入口时，底层写零，此值不是推测的启动入口。库 API 可显式提供新入口；详见 [adapter 文档](adapter/README.md)。
7. 稀疏空洞没有被声明为真实数据；只有 BIN 展开时才填充。工具不能推断 ELF section、芯片布局、擦除页规则或板级要求，也不保留原始文本排版和记录分块。

## 库 API

```moonbit
// import "ssjssj183312-jpg/moonuf2" as @uf2
let image = @uf2.from_bin(b"abcd", 0x10000000UL,
  family=Some(0xE48BFF56U)).unwrap()
let encoded = @uf2.encode(image, payload_size=256).unwrap()
let checked = @uf2.decode(encoded,
  expected_family=Some(0xE48BFF56U)).unwrap()
let bytes = @uf2.to_bin(checked, max_span=1024, fill=0xFF).unwrap()
```

公开类型为 `Segment { address: UInt64, data: Bytes }`、`Image { segments, family }`、`Uf2Error { code, block, message }`。`block` 为从零计数的物理输入块；镜像级错误为 -1。库调用返回 `Result`，示例 `.unwrap()` 仅为演示，应用应处理错误。

核心生成/展开会复制并排序 segment 列表，不修改调用者顺序。解析输出按地址排序但不保证合并相邻块，因此比较镜像应比较绝对地址上的数据，而不是 segment 数量。

## 验证

```sh
./scripts/check.sh
```

会核对 vendor 来源哈希，执行类型检查、三种后端测试、真实 CLI 子进程测试与微软参考差分。测试细节见 [验证记录](docs/validation.md)、[独立边界审查](docs/review.md)。CLI 不支持 native/Wasm 文件 IO；这两种后端验证的是纯库和 adapter。

CI 配置已提供；本地通过不等于 GitHub CI 已运行。项目没有硬件烧录测试、签名校验、独立人工安全审计或全格式兼容性认证。

## 来源、许可和 AI 使用

新 UF2 核心、适配和 CLI 在 AI 辅助下开发。复用代码按原作者署名保留，不能把上游已有能力宣称为独立原创。原始许可证/NOTICE/固定 commit/文件哈希随项目保留。测试 oracle 来自微软 MIT 许可代码。

详见 [来源清单](docs/sources.md)、[NOTICE](NOTICE)、[LICENSE](LICENSE)。新代码拟使用 Apache-2.0；外部发布前由项目所有者确认。此目录为本地工作成果，不代表已经提交参赛、推送 GitHub 或发布 Mooncakes 包。

## 不安装 MoonBit 运行已构建 CLI

交付包如包含 `dist/moonuf2.cjs`，可直接执行 `node dist/moonuf2.cjs --help`。
它是上述 MoonBit 源码编译得到的 CommonJS 文件，不是另写的 JS 格式解析器。
开发者运行 `./scripts/build-release.sh` 可重新生成；发布前应再运行完整检查。
