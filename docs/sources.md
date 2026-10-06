# 来源与归属

- UF2 官方规范：https://microsoft.github.io/uf2/
- 微软 UF2 参考仓库：https://github.com/microsoft/uf2
  - 固定提交：90e9741f217f5a40c98ba74d663e408041037578
  - 原样复制 `utils/uf2conv.py`、`utils/uf2families.json` 至 `tests/reference/`，保留 MIT 许可证 `LICENSE.txt`
  - 差分测试仅覆盖双方共有的普通 256 字节主闪存子集。微软转换器将不足一块的末尾数据补齐到 256 字节；MoonUF2 则输出按 4 字节对齐的短末块
- MoonBit Firmware Image Toolkit：https://github.com/Zzqy-yi/moonbit-firmware-image
  - 固定提交：cd34551136a5c2663af48634ebc72d8ce8b6a8c0
  - `vendor/firmware/` 保留原始源码与署名；用于稀疏镜像、Intel HEX、Motorola S-record 校验和序列化。UF2 编解码部分为本项目新写的 MoonBit 代码
- MoonBit 官方文档：https://docs.moonbitlang.com/en/latest/
- 官方工具链安装来源：https://cli.moonbitlang.com/install/unix.sh

本项目自有代码采用 Apache-2.0 许可证。第三方原文、作者署名、许可证和固定提交保持原样，不将第三方能力包装为独立原创。不伪造提交历史、日期、人工独立创作或硬件测试结果。

公开仓库：https://github.com/ssjssj183312-jpg/MoonUF2 。源代码公开不等于参赛提交、Mooncakes 包发布或硬件认证。
