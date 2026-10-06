#!/usr/bin/env python3
"""将双方共有的格式子集与固定版本、未经修改的微软参考实现对照。"""
import contextlib
import importlib.util
import io
from pathlib import Path
import random
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('uf2_reference', ROOT / 'tests/reference/uf2conv.py')
ref = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ref)

class DifferentialTests(unittest.TestCase):
    def run_cli(self, *args):
        result = subprocess.run(['sh', str(ROOT/'scripts/moonuf2'), *map(str,args)], capture_output=True, text=True)
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
    unittest.main(verbosity=2)
