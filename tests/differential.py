#!/usr/bin/env python3
"""将共有格式子集与原始微软参考实现对照；--cli 可直接检查已编译产物。"""
import argparse
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import random
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / '_build/js/debug/build/cmd/moonuf2/moonuf2.js'
NODE = os.environ.get('NODE', 'node')
spec = importlib.util.spec_from_file_location('uf2_reference', ROOT / 'tests/reference/uf2conv.py')
ref = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ref)

class DifferentialTests(unittest.TestCase):
    def run_cli(self, *args):
        result = subprocess.run([NODE, str(CLI), *map(str,args)], capture_output=True,
                                text=True, encoding='utf-8', timeout=20)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_reference_compatibility(self):
        # 仅在不存在短末块时要求逐字节完全一致。
        rng = random.Random(0x554632)
        with tempfile.TemporaryDirectory() as td:
            folder = Path(td)
            for index, (length, base, family) in enumerate([
                (256,0,None),(512,0x2000,0xE48BFF56),(4096,0x10000000,0x68ED2B88),
                (768,0xFFFFFD00,None),(256,0xFFFFFF00,0xE48BFF56),
            ]):
                with self.subTest(length=length,base=base,family=family):
                    data = rng.randbytes(length)
                    src, encoded, decoded = (folder/f'{index}.{ext}' for ext in ('bin','uf2','out'))
                    src.write_bytes(data)
                    extra = [] if family is None else ['--family',hex(family)]
                    self.run_cli('convert',src,encoded,'--from','bin','--to','uf2','--base',hex(base),*extra)
                    ref.appstartaddr, ref.familyid = base, family or 0
                    expected = ref.convert_to_uf2(data)
                    self.assertEqual(encoded.read_bytes(),expected)
                    with contextlib.redirect_stdout(io.StringIO()):
                        self.assertEqual(ref.convert_from_uf2(encoded.read_bytes()),data)
                    oracle = folder/f'{index}.reference.uf2'
                    oracle.write_bytes(expected)
                    self.run_cli('convert',oracle,decoded,'--from','uf2','--to','bin','--discard-metadata',*extra)
                    self.assertEqual(decoded.read_bytes(),data)

    def test_short_payload_semantic_compatibility(self):
        with tempfile.TemporaryDirectory() as td:
            folder = Path(td)
            data = bytes(range(100))
            (folder/'in.bin').write_bytes(data)
            self.run_cli('convert',folder/'in.bin',folder/'out.uf2','--from','bin','--to','uf2','--base','0x2000')
            ref.appstartaddr, ref.familyid = 0x2000,0
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(ref.convert_from_uf2((folder/'out.uf2').read_bytes()),data)
            self.assertNotEqual((folder/'out.uf2').read_bytes(),ref.convert_to_uf2(data))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', type=Path, help='直接测试指定的已编译 CLI；不调用 MoonBit 编译器')
    options, unittest_args = parser.parse_known_args()
    if not shutil.which(NODE):
        parser.error('需要安装 Node.js，或通过 NODE 指定其路径')
    if options.cli is not None:
        CLI = options.cli.resolve()
    else:
        moon = os.environ.get('MOON', 'moon')
        if not shutil.which(moon):
            parser.error('请通过 MOON 指定 MoonBit，或使用 --cli dist/moonuf2.cjs')
        # 每次测试运行只编译一次，随后直接调用同一个真实 CLI。
        subprocess.run([moon, 'build', '--target', 'js', 'cmd/moonuf2', '--quiet'], cwd=ROOT, check=True)
    if not CLI.is_file():
        parser.error(f'已编译 CLI 文件不存在：{CLI}')
    print(f'已测试 CLI：{CLI}', flush=True)
    unittest.main(argv=[sys.argv[0], *unittest_args], verbosity=2)
