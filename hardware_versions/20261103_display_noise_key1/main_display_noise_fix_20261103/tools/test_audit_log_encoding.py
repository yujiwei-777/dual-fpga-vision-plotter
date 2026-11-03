"""Decode log BOMs strictly without changing raw hash evidence."""
from pathlib import Path
import tempfile
import unittest
import display_noise_paths
import strict_release_review
import td_release_audit
READERS=(display_noise_paths.read,strict_release_review.read,td_release_audit.read)
class EncodingTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
    def test_utf8_utf16_decode_same_diagnostics_preserve_original_bytes(self):
        text='RUN-8007 ERROR: capacity\nUSR-8450 CRITICAL-WARNING: IO\n诊断原文\n'
        paths=[]
        for encoding in ('utf-8','utf-8-sig','utf-16'):
            p=self.root/encoding;p.write_bytes(text.encode(encoding));paths.append(p)
        original={p:p.read_bytes() for p in paths}
        for read in READERS:
            for p in paths:self.assertEqual(read(p),text)
        for p in paths:self.assertEqual(p.read_bytes(),original[p])
        self.assertNotEqual(display_noise_paths.sha(paths[0]),display_noise_paths.sha(paths[2]))
    def test_both_utf16_byte_orders_are_supported(self):
        text='ERROR remains visible\n'
        for raw in (b'\xff\xfe'+text.encode('utf-16-le'),b'\xfe\xff'+text.encode('utf-16-be')):
            p=self.root/'log';p.write_bytes(raw)
            for read in READERS:self.assertEqual(read(p),text)
    def test_invalid_utf8_is_rejected(self):
        p=self.root/'bad';p.write_bytes(b'ERROR \xc3\x28')
        for read in READERS:
            with self.assertRaises(UnicodeDecodeError):read(p)
    def test_truncated_utf16_is_rejected(self):
        p=self.root/'bad16';p.write_bytes(b'\xff\xfeA')
        for read in READERS:
            with self.assertRaises(UnicodeDecodeError):read(p)
    def test_legacy_cp936_hdl_comments_are_lossless_and_dependencies_survive(self):
        p=self.root/'legacy.v'
        text='// 旧版摄像头解码\nmodule m; initial $readmemh("weights.mem", ram); endmodule\n'
        raw=text.encode('cp936');p.write_bytes(raw)
        decoded,encoding=td_release_audit.read_hdl(p)
        self.assertEqual(decoded,text);self.assertEqual(encoding,'cp936-comments-only')
        self.assertIn('$readmemh("weights.mem", ram)',td_release_audit.plain_hdl(decoded))
        self.assertEqual(p.read_bytes(),raw)
        with self.assertRaises(UnicodeDecodeError):td_release_audit.read(p)
    def test_legacy_fallback_does_not_apply_to_logs_or_json(self):
        for suffix in ('.log','.json','.xml','.tcl','.mem'):
            p=self.root/('legacy'+suffix);p.write_bytes('ERROR 原始诊断'.encode('cp936'))
            with self.assertRaises(ValueError):td_release_audit.read_hdl(p)
            with self.assertRaises(UnicodeDecodeError):td_release_audit.read(p)
    def test_legacy_fallback_rejects_invalid_multibyte_sequences(self):
        p=self.root/'invalid.v';p.write_bytes(b'// bad \x81\nmodule m; endmodule\n')
        with self.assertRaises(UnicodeDecodeError):td_release_audit.read_hdl(p)
    def test_legacy_fallback_rejects_nonascii_outside_comments(self):
        p=self.root/'nonascii.v';p.write_bytes('module m; initial $display("错误"); endmodule'.encode('cp936'))
        with self.assertRaises(ValueError):td_release_audit.read_hdl(p)
    def test_bom_errors_never_fall_back_to_legacy(self):
        for raw in (b'\xff\xfeA',b'\xef\xbb\xbf// \xbd\xe2'):
            p=self.root/'bom.v';p.write_bytes(raw)
            with self.assertRaises(UnicodeDecodeError):td_release_audit.read_hdl(p)
if __name__=='__main__':unittest.main()
