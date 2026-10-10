# 本地验证记录

## 2026-10-10：公开文本导入拒绝被分行器丢弃的非 ASCII 字符

本轮基线为远端 `main` 的 `ee125947c9d13a0da0dc320d08da7cc446fb1abf`。直接调用适配接口时，在合法 HEX 或 S-record 记录中插入 `😺`，上游分行器会逐个处理 UTF-16 码元并丢掉代理码元，结果仍被当作合法记录接受。两条拒绝断言在未修复代码上均失败，原有适配层 22 项测试通过。CLI 已在原始字节层拒绝非 ASCII，此缺陷影响公开库导入接口。

适配层在现有线性预检查中拒绝所有非 ASCII 码元，先于上游分行和解析执行；不修改所引用的上游源码。错误沿用 `Firmware` / `hex.invalid_digit`，保留原始行列位置。新增的 2 项适配测试覆盖 HEX 与 S-record、补充平面字符、汉字和重音字符，以及 LF、CR、CRLF 下的错误位置和合法 ASCII 控制输入。另增加 4 项 CLI 子进程检查，验证文件级拒绝和失败后不产生输出或临时文件。

实际本地环境为 Windows，使用昨天的隔离工具链：moon 0.1.20260920 / moonc v0.10.14+7d59c7ec9、Node.js v24.19.0、Python 3.10.0。原 `build-release.sh` 和 `check.sh` 在测试进程环境中均退出 0；原生编译从开始即使用 `MOON_CC` 转发器添加 `-D_CRT_RAND_S`，Windows 的 `python3` 命令由导出的函数调用现有 `python`。没有改变系统设置或官方 runtime。

- JS：47/47；Wasm GC：44/44；native：44/44，全部通过。
- 源码 CLI：115 项；发布 CLI：114 项，全部通过；两者的微软参考实现差分测试各 2 项通过。
- 发布 CLI 由原脚本重建，与 release 编译结果逐字节相同，SHA-256 为 `7d63691baab3762720d7400144fbc153f6302a20815a68a7fa7c7675d7fe1465`。
- Python 语法、4 个 Bash 脚本语法、上游 13 文件哈希和差异空白检查通过；更新后的 58 文件清单已逐项核对。
- Windows 没有 `os.mkfifo`，FIFO 检查未执行；本轮没有执行 Linux 本地回归或硬件烧录。

额外的 `moon fmt --check adapter` 仍报告基线已有长行的布局差异，均位于本轮未改动代码。新增回归已采用格式器输出，未为可选样式检查调整无关行。未加 `_CRT_RAND_S` 的 Windows 原生工具链兼容性问题仍按历史限制处理，不以本轮通过结果宣称系统工具链已修复。

以上为本地验证记录；本轮远端提交及其 CI 状态须在发布后核验。不能将基线的成功运行或本地日志当作新提交的 CI 结果。

## 2026-10-09：文本输出限额不再受 UF2 分块影响

本轮基线为远端 `main` 的 `e75b9a6679ce4958e10dbd40761d8bcf3b168d7b`。3808 字节数据按 476 字节有效载荷生成的 UF2 占 4096 字节，实际 HEX 输出为 10483 字节、S-record 输出为 8946 字节。旧发布 CLI 在 `--max-bytes` 恰好等于这些实际输出大小时仍拒绝转换，新增黑盒回归已在旧产物上复现失败。

预估现在按导出器合并相邻段后的连续地址范围计算，只保存范围，不复制有效载荷。地址空洞、HEX 的 64 KiB 地址边界及 S-record 的地址/计数记录宽度继续参与计算。新增 3 个仅 JS 的 CLI 白盒测试，及 36 项真实 CLI 子进程检查，覆盖精确限额、少一个字节的拒绝、空洞保留、地址空间末端、BIN 往返和失败后不产生文件。

本次在 Windows 上使用隔离安装的官方工具链：moon 0.1.20260920 / moonc v0.10.14+7d59c7ec9、Node.js v24.19.0、Python 3.10.0。官方 Windows ZIP 和 core ZIP 完整下载并通过 ZIP CRC 检查，SHA-256 分别为 `faae225a8287d0ce69e44b5b3f754af988e97f4446056d8f32ceb3ddb998fce7` 和 `63e5b99991ac8fd49556b1e17bdcbdc662d797000250dd11ef090f38a2175e84`。这些是本次 Windows 下载的记录，不替代 Linux 安装脚本中的锁定哈希。

类型检查和原样 `build-release.sh` 均成功。发布 CLI 与编译器输出逐字节相同，SHA-256 为 `cc081fe2d3ed761ce1295751eaca335a0e29b3af051b569c6c15eea8dc11e5a6`，未手工修改构建产物。

- JS：45/45 通过（含新增 3 个 CLI 白盒测试）；Wasm GC：42/42 通过。
- Native：使用仅本次调用的 `MOON_CC` 编译器转发程序附加 `-D_CRT_RAND_S` 后，独立运行 `moon test --target native --verbose`，42/42 通过；仓库和官方 runtime 源码未修改。
- 源码 CLI：111 项通过，含 sh 启动脚本；发布 CLI：110 项通过。两种 CLI 的微软参考差分各 2 个测试方法通过。
- 第三方来源 13 项哈希、Python 语法、Bash 脚本语法及差异空白检查通过。
- Windows 没有 `os.mkfifo`，FIFO 检查未执行；本次没有执行 Linux 本地测试或硬件操作。

原样 `check.sh` 在 native 阶段被本机 LLVM-MinGW 22.1.8（`x86_64-w64-windows-gnu`）的兼容性问题阻断：官方 MoonBit runtime 调用 `rand_s`，而该编译器头文件要求定义 `_CRT_RAND_S` 才提供声明。随后通过隔离的编译器转发程序保留所有原始参数并仅附加该宏，独立完成 native 测试；未受影响的源码/发布 CLI 与差分检查也已独立运行并通过。原失败日志保留，不将它记为原样整套脚本成功。

附加的 `moon fmt --check cmd/moonuf2` 对历史 `moon.pkg` 的导入别名和布局提出格式变化，因此未通过。新测试文件已使用格式化结果；保留现有包配置，没有为消除这个无关差异修改它。原有派生方法弃用警告仍存在。

本节记录本地实际验证；本轮远端提交和新提交的 CI 尚未执行，不沿用基线 CI 成功状态冒充本轮结果。

## 2026-10-08：修复合法长输出文件名转换失败

本轮从远端 `main` 的 `4cc7e942b4fd84b86087d42ebb909f8d293201d8` 开始。旧 CLI 在输出目录中使用“完整输出文件名 + 26 字节后缀”作为临时文件名，导致文件系统本来支持的长文件名仍报 `ENAMETOOLONG`。现改为同目录的固定长度随机临时名称，保留独占创建、完整写入后发布和拒绝覆盖已有路径的行为。

回归用例使用 80 个汉字加 `.uf2`（244 个 UTF-8 字节；Windows 中仅 84 个 UTF-16 字符），检查转换、校验、BIN 往返、拒绝覆盖且原文件不变、临时文件清理；另检查已有目录不被替换且失败后无临时文件残留。新增用例先在旧发布 CLI 上复现失败，再用修改后的源码与重新构建的发布 CLI 验证通过。

实际执行环境为 Linux x86_64、MoonBit moon 0.1.20260920 / moonc v0.10.14+7d59c7ec9、Node.js v24.19.0、Python 3.12.14。工具链从官方源重新下载，两个归档的锁定 SHA-256 均匹配，安装成功。

```sh
bash scripts/build-release.sh
bash scripts/check.sh
python3 -m py_compile scripts/cli_test.py tests/differential.py
bash -n scripts/check.sh scripts/build-release.sh scripts/install-toolchain.sh
sha256sum -c MANIFEST.sha256
```

- 类型检查通过；JS、Wasm GC、native 库测试分别 42/42 通过
- 源码 CLI 76 项检查、发布 CLI 75 项检查全部通过；两种 CLI 的微软参考差分各 2 个测试方法通过
- Python/Bash 语法检查、第三方来源哈希及更新后的 57 文件清单哈希通过
- 发布 CLI 从修改后的 MoonBit 源码重新编译；其差异仅为相同的一行临时文件命名修复，未手工修改构建产物
- 原有 MoonBit 派生方法弃用警告仍存在，不是测试失败；未更改第三方源码、格式算法、硬件操作范围或安全设置

本节是本地实际验证记录；Windows 行为由现有 `release-windows` CI 作业验证，本节不冒充本地 Windows 测试。最终远程状态须查看本轮最终提交的 Actions。

## 2026-10-07：发布 CLI 的 Windows 回归入口

本轮从远端 `main` 的 `1dc4007891d8f1f9c1a9857a6be33d0948ca8911` 开始，增加 `--cli` 参数，让 CLI 和微软参考差分测试能直接运行指定的预编译文件。默认模式仍编译源码；差分测试每次运行只编译一次。中文子进程输出明确按 UTF-8 解码，解决 Windows 默认 CP936 解码失败的问题。

在 Windows、Node.js v24.19.0、Python 3.10.0 上实际运行：

```sh
python scripts/cli_test.py --cli dist/moonuf2.cjs
python tests/differential.py --cli dist/moonuf2.cjs
```

- 发布 CLI 的 69 项真实子进程检查通过；新增中文及空格路径的往返、UF2/HEX/S-record 在 `0xFFFFFFFC` 起始的四字节往返，以及越界拒绝与不产生输出文件的检查。
- 微软参考差分的 2 个测试方法通过，保留完整块逐字节比较及短末块语义互读。
- Windows 不提供命名管道测试所需的 `os.mkfifo`，因此该项仅在提供此 API 的系统运行；`--cli` 模式不调用需要编译器的 sh 启动脚本，默认源码模式仍保留启动脚本检查。69 项不能直接与此前 Linux 源码模式的 58 项相减来计算新增用例数。
- 6 项测试入口检查通过：缺少编译器或 CLI 文件时给出明确错误、从含中文和空格的外部工作目录解析相对 `--cli` 路径，以及保留 unittest 筛选参数。
- Python 语法检查、Bash 检查脚本的只读语法检查通过。第三方源文件和版权保持原样；发布 CLI 本身未修改。

`check.sh` 已加入同一发布文件的检查，CI 增加无需 MoonBit 的 Windows 发布文件检查作业。发布前也在 Linux 独立复测：70 项 CLI 检查（包括 FIFO）及 2 个微软参考差分测试通过，Python/Bash 语法和 57 个文件的清单哈希全部通过。Windows 和 Linux 本地均无可用 MoonBit 工具链，因此本轮本地未执行类型检查及 JS/Wasm GC/native 库测试；这些检查由远端 CI 执行。下面的历史成功记录不代表本轮变更通过 CI，最新状态应查看本轮最终提交对应的 Actions 运行。

本轮 CLI 与差分原始输出保存在本地 `logs/release-cli-windows.log` 和 `logs/release-differential-windows.log`，日志不纳入公开源码仓库。

## 2026-10-06：源码与原有 CI 的历史记录

会话日期：2026-10-06。以下是实际执行结果，不是计划或 GitHub 状态。

## 公开仓库与远程验证

完整源码提交：[`c753047a1e84ca90f4fe75f0fd4798180d000d9f`](https://github.com/ssjssj183312-jpg/MoonUF2/commit/c753047a1e84ca90f4fe75f0fd4798180d000d9f)。公开树的 58 个文件已与冻结本地版本逐一核对 Git blob 哈希，没有缺失或额外文件。

该提交的 [GitHub Actions 运行 37417410538](https://github.com/ssjssj183312-jpg/MoonUF2/actions/runs/37417410538) 已实际成功。首次 CI 因网页上传漏掉 `vendor/firmware/docs/references.md` 而失败；补齐原始参考文档后重新运行成功，未通过删减来源检查规避错误。官方固定哈希工具链的联网安装也已在 CI 中成功执行。

以上远程结果对应明确提交和运行编号。后续文档提交或新代码的结果应分别查看其 Actions，不能沿用此处状态代替验证。

## 结果

- 类型检查：`moon check --target js` 通过
- MoonBit 测试：42 个命名测试，在 JS、Wasm GC、native 三个后端分别 42/42 通过
  - 核心基础 5 组
  - 独立边界/恶意输入/排列检查 15 组
  - HEX/S-record/稀疏适配与资源检查 22 组
- CLI：58 项真实子进程端到端检查通过
- 微软参考差分：2 个测试方法通过，其中 5 组完整 256 字节块场景逐字节相同；另有短末块语义互读场景
- Release CLI：构建成功；直接 Node 执行版本和样例结构校验成功
- Vendor：记录的 10 个源码文件与 LICENSE/NOTICE/原始参考文档 SHA-256 全部匹配
- 哈希锁定工具链：通过已从官方源下载的缓存归档重新安装，并用新安装工具链清理后重跑完整检查

测试数量指分组测试而非穷尽所有输入。分组中包含 119 种合法 payload、31 个非法 flag 位、三块的全部排列、32 个生成的稀疏案例、数万倒序记录、恰好/刚超过 16 MiB、0xFFFFFFFF 地址末端等子案例；不把循环次数冒充独立测试数量。

中文化修订保留 API 标识符、错误码和第三方原文；新增上游错误中文概括映射测试。自有脚本全部设为非可执行权限后，使用显式 sh/bash 启动完整检查，确认不依赖网页上传是否保留执行位。

## 复现

```sh
bash scripts/check.sh
bash scripts/build-release.sh
node dist/moonuf2.cjs verify examples/demo.uf2 --family 0xe48bff56
```

`check.sh` 会执行来源哈希验证、类型检查、三后端测试、CLI 测试和参考差分。无需访问板卡或使用用户账号。

## 证据文件

原始运行日志随交付 ZIP 保存，不纳入公开源码仓库。以下日志路径相对交付目录；公开仓库可运行上述命令重新生成结果。`MANIFEST.sha256` 仅覆盖公开源码、文档、示例和构建产物，不包含日志或缓存。

- `logs/check-chinese.log`：中文化与网页上传执行权限兼容性修订后的完整检查
- `logs/check-clean-toolchain.log`：前一版本的干净构建检查
- `logs/check.log`：集成检查
- `logs/build-release.log`：release 编译
- `logs/differential.log`：微软参考对照
- `logs/toolchain-install-cached.log`：固定哈希归档重新安装
- `logs/toolchain-install.log`：一次在线重复下载失败的记录
- `logs/example.log`：演示转换和检查输出

日志包含当前工具链对派生方法推广的弃用提示，主要来自保留原样的第三方源码；这些不是测试失败。本地执行成功不代表零警告。

## 未完成/未验证的边界

- 本记录仅证明本地测试；公开仓库的远程 CI 状态以 Actions 实际结果为准
- 尚未进行真实硬件烧录、板级兼容测试、固件签名/真实性校验
- 不支持容器、MD5、扩展 tag、not-main-flash、拼接多 family 的 UF2
- 不是流式实现；逻辑大小限额不等于总内存峰值限额
- 上游文本输出在内存中构造字符串；CLI 先估算上界并限制输出，直接库调用仍需关注字符串开销
- 固定版本路径的官方归档请求返回 403；安装器改为校验 latest 归档的固定哈希，源更新即失败。一次重复网络下载也返回 403；缓存路径安装已验证，不能据此声称网络永远可用
- 尚无独立人工审计或竞赛方验收；AI 辅助审查不是安全认证
