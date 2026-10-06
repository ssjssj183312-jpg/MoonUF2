# 本地验证记录

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
