#!/usr/bin/env python3
"""对已编译的 MoonBit 命令行程序执行黑盒测试；Python 不实现 UF2 编解码。

运行方式：MOON=/path/to/moon python3 scripts/cli_test.py
无需编译器检查已发布 CLI：python3 scripts/cli_test.py --cli dist/moonuf2.cjs
所有格式转换均由实际的 MoonBit 可执行程序完成。Python 仅负责调用子进程、
比较字节，以及修改输入以构造已知错误。
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MOON = os.environ.get("MOON", "moon")
NODE = os.environ.get("NODE", "node")
CLI = ROOT / "_build/js/debug/build/cmd/moonuf2/moonuf2.js"
checks = 0


def run(*args: str, ok: bool = True, contains: str = "", cwd: Path) -> subprocess.CompletedProcess:
    global checks
    process = subprocess.run([NODE, str(CLI), *map(str, args)], cwd=cwd,
                             text=True, encoding="utf-8", capture_output=True, timeout=20)
    assert (process.returncode == 0) == ok, (args, process.returncode, process.stdout, process.stderr)
    if contains:
        assert contains in process.stdout + process.stderr, (args, contains, process.stdout, process.stderr)
    if not ok:
        assert "Error: " not in process.stderr and " at " not in process.stderr, process.stderr
    checks += 1
    return process


def main() -> None:
    global checks, CLI
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=Path, help="直接测试指定的已编译 CLI；不调用 MoonBit 编译器")
    options = parser.parse_args()
    if not shutil.which(NODE):
        parser.error("需要安装 Node.js，或通过 NODE 指定其路径")
    if options.cli is not None:
        # 在创建测试临时目录之前解析路径，保留调用方的相对路径语义。
        CLI = options.cli.resolve()
    else:
        if not shutil.which(MOON):
            parser.error("请通过 MOON 指定 MoonBit，或使用 --cli dist/moonuf2.cjs")
        subprocess.run([MOON, "build", "--target", "js", "cmd/moonuf2", "--quiet"], cwd=ROOT, check=True)
    if not CLI.is_file():
        parser.error(f"已编译 CLI 文件不存在：{CLI}")
    with tempfile.TemporaryDirectory(prefix="moonuf2-cli-") as directory:
        work = Path(directory)
        def cli(*args: str, **kwargs):
            return run(*args, cwd=work, **kwargs)

        cli("--help", contains="--base")
        cli("--version", contains="0.1.0")
        cli("bogus", ok=False, contains="cli.command")
        cli("inspect", "missing.uf2", ok=False, contains="io.read")
        cli("inspect", ".", ok=False, contains="io.input_type")
        cli("inspect", "missing.uf2", "--surprise", ok=False, contains="cli.option")
        cli("inspect", "missing.uf2", "--family", ok=False, contains="cli.value")
        cli("inspect", "missing.uf2", "--family", "1", "--family", "2", ok=False, contains="cli.duplicate")
        cli("inspect", "missing.uf2", "--family", "4294967296", ok=False, contains="cli.number")
        cli("inspect", "missing.uf2", "--family", "0x", ok=False, contains="cli.number")
        cli("inspect", "missing.uf2", "--family", "-1", ok=False, contains="cli.number")
        cli("inspect", "missing.uf2", "--max-bytes", "0", ok=False, contains="cli.limit")
        cli("inspect", "missing.uf2", "--max-bytes", "16777217", ok=False, contains="cli.limit")
        cli("inspect", "missing.uf2", "--base", "0", ok=False, contains="cli.base")
        cli("verify", "missing.uf2", "--to", "bin", ok=False, contains="cli.option")
        cli("convert", "a", "b", ok=False, contains="cli.format")
        cli("convert", "a", "b", "--from", "wat", "--to", "uf2", ok=False, contains="cli.format")
        data = bytes(range(256)) + b"test"
        (work / "app.bin").write_bytes(data)
        cli("convert", "app.bin", "app.uf2", "--from", "bin", "--to", "uf2", ok=False, contains="cli.base")
        cli("convert", "app.bin", "app.uf2", "--from", "bin", "--to", "uf2", "--base", "0x10000000", "--family", "0xe48bff56", contains="起始地址：0x10000000")
        assert (work / "app.uf2").stat().st_size == 1024
        cli("inspect", "app.uf2", contains="芯片家族标识：0xe48bff56")
        cli("verify", "app.uf2", "--family", "0xe48bff56", contains="校验通过")
        cli("verify", "app.uf2", "--family", "0", ok=False, contains="uf2.family")
        cli("convert", "app.uf2", "restored.bin", "--from", "uf2", "--to", "bin", ok=False, contains="adapter.metadata_loss")
        cli("convert", "app.uf2", "restored.bin", "--from", "uf2", "--to", "bin", "--discard-metadata")
        assert (work / "restored.bin").read_bytes() == data
        cli("convert", "app.uf2", "restored.bin", "--from", "uf2", "--to", "bin", "--discard-metadata", ok=False, contains="io.write")
        assert (work / "restored.bin").read_bytes() == data
        assert not list(work.glob(".moonuf2-*")), "临时输出文件未清理"
        cli("inspect", "app.uf2", "--max-bytes", "512", ok=False, contains="io.input_limit")
        cli("convert", "app.bin", "too-big.uf2", "--from", "bin", "--to", "uf2", "--base", "0", "--max-bytes", "300", ok=False, contains="io.output_limit")
        assert not (work / "too-big.uf2").exists()
        for payload in ["0", "3", "477"]:
            cli("convert", "app.bin", "no.uf2", "--from", "bin", "--to", "uf2", "--base", "0", "--payload-size", payload, ok=False, contains="cli.payload")
        cli("convert", "app.bin", "small.uf2", "--from", "bin", "--to", "uf2", "--base", "0", "--payload-size", "4")
        cli("verify", "small.uf2")
        (work / "unaligned.bin").write_bytes(b"123")
        cli("convert", "unaligned.bin", "unaligned.uf2", "--from", "bin", "--to", "uf2", "--base", "0", ok=False, contains="uf2.alignment")
        (work / "tiny.bin").write_bytes(b"1234")
        # 80 个汉字加扩展名为 244 个 UTF-8 字节，仍是常见文件系统的合法名称。
        # 临时文件名不能再拼接完整输出名，否则会先触发 ENAMETOOLONG。
        long_name = "固件" * 40 + ".uf2"
        cli("convert", "tiny.bin", long_name, "--from", "bin", "--to", "uf2", "--base", "0")
        cli("verify", long_name, contains="校验通过")
        cli("convert", long_name, "long-name.bin", "--from", "uf2", "--to", "bin")
        assert (work / "long-name.bin").read_bytes() == b"1234"
        saved_long_output = (work / long_name).read_bytes()
        cli("convert", "tiny.bin", long_name, "--from", "bin", "--to", "uf2", "--base", "0", ok=False, contains="EEXIST")
        assert (work / long_name).read_bytes() == saved_long_output
        assert not list(work.glob(".moonuf2-*")), "长文件名转换后仍有临时输出文件"
        # 发布到已有目录也必须拒绝，并清理已完整写入的临时文件。
        (work / "existing-directory").mkdir()
        cli("convert", "tiny.bin", "existing-directory", "--from", "bin", "--to", "uf2", "--base", "0", ok=False, contains="io.write")
        assert (work / "existing-directory").is_dir()
        assert not list(work.glob(".moonuf2-*")), "发布失败后仍有临时输出文件"
        # 同一套检查也覆盖已发布产物的中文路径、空格和相对路径。
        (work / "中文 空格目录").mkdir()
        (work / "中文 空格目录/原始 固件.bin").write_bytes(b"1234")
        cli("convert", "中文 空格目录/原始 固件.bin", "中文 空格目录/输出 固件.uf2", "--from", "bin", "--to", "uf2", "--base", "0")
        cli("verify", "中文 空格目录/输出 固件.uf2", contains="校验通过")
        cli("convert", "中文 空格目录/输出 固件.uf2", "中文 空格目录/还原 固件.bin", "--from", "uf2", "--to", "bin")
        assert (work / "中文 空格目录/还原 固件.bin").read_bytes() == b"1234"
        # UF2、HEX、S-record 均须保留恰好到达 32 位地址空间末端的数据。
        for format in ["uf2", "hex", "srec"]:
            cli("convert", "tiny.bin", f"end.{format}", "--from", "bin", "--to", format, "--base", "0xfffffffc", contains="结束地址（不包含）：0x100000000")
            metadata = ["--discard-metadata"] if format == "srec" else []
            cli("verify", f"end.{format}", "--from", format, *metadata)
            cli("convert", f"end.{format}", f"end-{format}.bin", "--from", format, "--to", "bin", *metadata)
            assert (work / f"end-{format}.bin").read_bytes() == b"1234"
        cli("convert", "app.bin", "overflow.uf2", "--from", "bin", "--to", "uf2", "--base", "0xfffffffc", ok=False, contains="uf2.address_overflow")
        assert not (work / "overflow.uf2").exists()
        cli("convert", "tiny.bin", "exact.hex", "--from", "bin", "--to", "hex", "--base", "0", "--max-bytes", "31")
        assert (work / "exact.hex").stat().st_size == 31
        cli("convert", "tiny.bin", "short.hex", "--from", "bin", "--to", "hex", "--base", "0", "--max-bytes", "30", ok=False, contains="io.output_limit")
        cli("convert", "tiny.bin", "exact.srec", "--from", "bin", "--to", "srec", "--base", "0", "--max-bytes", "40")
        assert (work / "exact.srec").stat().st_size == 40
        cli("convert", "tiny.bin", "short.srec", "--from", "bin", "--to", "srec", "--base", "0", "--max-bytes", "39", ok=False, contains="io.output_limit")
        damaged = bytearray((work / "app.uf2").read_bytes())
        damaged[0] ^= 1
        (work / "broken.uf2").write_bytes(damaged)
        cli("verify", "broken.uf2", ok=False, contains="uf2.magic")
        (work / "truncated.uf2").write_bytes(damaged[:-1])
        cli("verify", "truncated.uf2", ok=False, contains="uf2.length")
        (work / "-firmware.uf2").write_bytes((work / "app.uf2").read_bytes())
        cli("verify", "--", "-firmware.uf2")
        cli("convert", "app.uf2", "app.hex", "--from", "uf2", "--to", "hex", ok=False, contains="adapter.metadata_loss")
        cli("convert", "app.uf2", "app.hex", "--from", "uf2", "--to", "hex", "--discard-metadata")
        cli("convert", "app.hex", "from-hex.uf2", "--from", "hex", "--to", "uf2", "--family", "0xe48bff56")
        cli("convert", "from-hex.uf2", "hex-roundtrip.bin", "--from", "uf2", "--to", "bin", "--discard-metadata")
        assert (work / "hex-roundtrip.bin").read_bytes() == data
        cli("convert", "app.uf2", "app.srec", "--from", "uf2", "--to", "srec", "--discard-metadata")
        cli("convert", "app.srec", "from-srec.uf2", "--from", "srec", "--to", "uf2", ok=False, contains="adapter.metadata_loss")
        cli("convert", "app.srec", "from-srec.uf2", "--from", "srec", "--to", "uf2", "--discard-metadata")
        cli("convert", "from-srec.uf2", "srec-roundtrip.bin", "--from", "uf2", "--to", "bin")
        assert (work / "srec-roundtrip.bin").read_bytes() == data
        (work / "sparse.hex").write_text(":0400000001020304F2\n:0400200005060708C2\n:00000001FF\n", encoding="ascii")
        cli("convert", "sparse.hex", "sparse.uf2", "--from", "hex", "--to", "uf2", contains="数据段数量：2")
        cli("convert", "sparse.uf2", "filled.bin", "--from", "uf2", "--to", "bin", "--fill", "0")
        assert (work / "filled.bin").read_bytes() == bytes([1, 2, 3, 4]) + bytes(28) + bytes([5, 6, 7, 8])
        # 地址 0 和 0x00100000 各有一个字节：展开为连续数据时必须检查跨度上限。
        (work / "wide.hex").write_text(":0100000001FE\n:020000040010EA\n:0100000002FD\n:00000001FF\n", encoding="ascii")
        cli("convert", "wide.hex", "wide.bin", "--from", "hex", "--to", "bin", "--max-bytes", "1024", ok=False, contains="bin.span_limit")
        (work / "bad.hex").write_text(":0400000001020304F3\n:00000001FF\n", encoding="ascii")
        cli("verify", "bad.hex", "--from", "hex", ok=False, contains="checksum.mismatch")
        (work / "unicode.hex").write_text("你好", encoding="utf-8")
        cli("verify", "unicode.hex", "--from", "hex", ok=False, contains="text.ascii")
        (work / "overlong.hex").write_text(":" + "0" * 522, encoding="ascii")
        cli("verify", "overlong.hex", "--from", "hex", ok=False, contains="record.too_long")
        with (work / "oversized.uf2").open("wb") as oversized:
            oversized.truncate(16777217)
        cli("verify", "oversized.uf2", ok=False, contains="io.input_limit")
        original = (work / "app.uf2").read_bytes()
        cli("convert", "app.uf2", "app.uf2", "--from", "uf2", "--to", "uf2", ok=False, contains="io.write")
        assert (work / "app.uf2").read_bytes() == original
        if hasattr(os, "mkfifo"):
            os.mkfifo(work / "input.fifo")
            cli("inspect", "input.fifo", ok=False, contains="io.input_type")
        if options.cli is None:
            # 源码模式仍检查启动脚本；产物模式使用 Node，不依赖 sh 或 MoonBit。
            process = subprocess.run(["sh", str(ROOT / "scripts/moonuf2"), "verify", "app.uf2"], cwd=work,
                                     env={**os.environ, "MOON": MOON, "NODE": NODE}, capture_output=True,
                                     text=True, encoding="utf-8", timeout=30)
            assert process.returncode == 0, process.stderr
            checks += 1
    print(f"已测试 CLI：{CLI}")
    print(f"命令行端到端测试：{checks} 项检查全部通过")


if __name__ == "__main__":
    main()
