# 可复现演示数据

这里的 256 字节是顺序值 0..255，只是格式演示数据，不是可运行固件。

- demo.bin：原始顺序值
- demo.uf2：基址 0x10000000，示例 family 0xe48bff56，256 字节 payload
- demo.hex / demo.srec：同地址同数据的文本输出；不包含 UF2 family
- demo.srec：终止入口为默认零，不代表有效启动入口

请勿烧录这些样例。family 值用于演示校验，不是硬件兼容承诺。

```sh
sh scripts/moonuf2 inspect examples/demo.uf2
sh scripts/moonuf2 verify examples/demo.uf2 --family 0xe48bff56
sh scripts/moonuf2 convert examples/demo.hex /tmp/demo-from-hex.uf2 \
  --from hex --to uf2 --family 0xe48bff56
```

输出路径需尚不存在。
