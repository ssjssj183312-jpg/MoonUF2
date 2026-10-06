# 工具链锁定

已测试的版本与可执行文件哈希记录在 `toolchain.txt`。`install-toolchain.sh`
仅从 MoonBit 官方下载归档，并在解包、运行前验证固定 SHA-256。该安装脚本
目前仅适用于 Linux x86_64。

本次测试的官方历史版本归档地址返回 HTTP 403，因此脚本使用官方 `latest`
地址并固定预期哈希。如果官方更新 `latest`，安装会主动失败，不会静默换用
未测试的编译器。这是版本漂移保护，不代表官方永久托管历史归档。
后续需要获取匹配的官方归档，或在审查新版本、完整重跑测试后更新哈希。
CI 配置已提供；远程运行状态以仓库中的实际 Actions 结果为准。

工具链归档 SHA-256：
9226694de9ff978db1ecf820b7710c4224e84ec7a76b19a222d96f0cd4e31b6a

核心库归档 SHA-256：
6f18b8fdea18f85e628a75e4a1bd3977c5a5c9c6a836fd8824192b0e6bd91b14

可通过 `MOONUF2_ARCHIVE_CACHE=/缓存目录` 离线重放安装。该目录须包含
`toolchain.tar.gz`、`core.tar.gz`；两者仍须通过同一组固定哈希验证。
本次使用从官方地址下载的缓存归档重新安装并执行了完整测试。
一次重复下载返回 HTTP 403，随后 HEAD 请求返回 200；这被记录为外部源
可用性问题，不能将其当作在线安装始终成功的证据。

网页上传可能不保留可执行权限，因此使用：

```sh
bash scripts/install-toolchain.sh "$HOME/moonuf2-toolchain"
```
