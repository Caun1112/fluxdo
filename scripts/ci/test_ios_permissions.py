"""覆盖受限 umask、引擎资源权限及最终 IPA/DEB 的权限检查。"""

import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest
import zipfile

from ios_permissions import normalize_permissions, validate_deb
from validate_ipa import validate_archive_permissions


class PermissionsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "package"
        self.engine = self.root / "var/jb/Applications/Fluxdo.app/Frameworks/Flutter.framework"
        old_umask = os.umask(0o077)
        try:
            self.engine.mkdir(parents=True)
            (self.engine / "icudtl.dat").write_bytes(b"resource")
            (self.engine / "Flutter").write_bytes(b"\xcf\xfa\xed\xfebinary")
        finally:
            os.umask(old_umask)

    def archive(self):
        path = Path(self.temporary.name) / "test.ipa"
        with zipfile.ZipFile(path, "w") as archive:
            for item in self.root.rglob("*"):
                archive.write(item, item.relative_to(self.root))
        return zipfile.ZipFile(path)

    def test_reject_old_ipa_permissions_and_accept_normalized(self):
        with self.archive() as archive:
            with self.assertRaisesRegex(ValueError, "归档权限"):
                validate_archive_permissions(archive)
        normalize_permissions(self.root)
        self.assertEqual(stat.S_IMODE(self.engine.stat().st_mode), 0o755)
        self.assertEqual(stat.S_IMODE((self.engine / "Flutter").stat().st_mode), 0o755)
        self.assertEqual(stat.S_IMODE((self.engine / "icudtl.dat").stat().st_mode), 0o644)
        with self.archive() as archive:
            validate_archive_permissions(archive)

    def test_preserve_executable_and_do_not_follow_symlink(self):
        script = self.root / "script"
        script.write_text("#!/bin/sh\n")
        script.chmod(0o700)
        outside = Path(self.temporary.name) / "outside"
        outside.write_text("不应修改")
        outside.chmod(0o600)
        (self.root / "link").symlink_to(outside)
        normalize_permissions(self.root)
        self.assertEqual(stat.S_IMODE(script.stat().st_mode), 0o755)
        self.assertEqual(stat.S_IMODE(outside.stat().st_mode), 0o600)

    @unittest.skipUnless(shutil.which("dpkg-deb"), "需要 dpkg-deb")
    def test_final_deb_rejects_restricted_framework(self):
        metadata = self.root / "DEBIAN"
        metadata.mkdir(mode=0o755)
        (metadata / "control").write_text(
            "Package: permissions-test\nVersion: 1\nArchitecture: iphoneos-arm64\n"
            "Maintainer: Test\nDescription: 权限回归测试\n"
        )
        deb = Path(self.temporary.name) / "test.deb"
        def pack():
            subprocess.run(["dpkg-deb", "--root-owner-group", "-Zgzip", "--build", str(self.root), str(deb)],
                           check=True, stdout=subprocess.DEVNULL)
        pack()
        with self.assertRaisesRegex(ValueError, "归档权限"):
            validate_deb(deb)
        normalize_permissions(self.root)
        pack()
        validate_deb(deb)


if __name__ == "__main__":
    unittest.main()
