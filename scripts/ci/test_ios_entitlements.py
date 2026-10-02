"""校验 Rootless 签名只包含本应用的钥匙串访问组。"""

import plistlib
import unittest
from unittest.mock import patch

from build_rootless_deb import app_entitlements, verify_entitlements


class EntitlementsTest(unittest.TestCase):
    bundle_id = "com.github.lingyan000.fluxdo"

    def test_group_matches_app_identity(self):
        entitlements = app_entitlements(self.bundle_id)
        self.assertEqual(entitlements["application-identifier"], self.bundle_id)
        self.assertEqual(entitlements["keychain-access-groups"], [self.bundle_id])
        self.assertTrue(entitlements["com.apple.private.security.container-required"])

    def test_reject_old_signature_without_keychain_group(self):
        entitlements = app_entitlements(self.bundle_id)
        del entitlements["keychain-access-groups"]
        with patch("subprocess.check_output", return_value=plistlib.dumps(entitlements)):
            with self.assertRaisesRegex(ValueError, "签名权限"):
                verify_entitlements("Runner", self.bundle_id)

    def test_accept_readback_and_reject_foreign_group(self):
        entitlements = app_entitlements(self.bundle_id)
        with patch("subprocess.check_output", return_value=plistlib.dumps(entitlements)):
            verify_entitlements("Runner", self.bundle_id)
        entitlements["keychain-access-groups"] = ["other.app"]
        with patch("subprocess.check_output", return_value=plistlib.dumps(entitlements)):
            with self.assertRaisesRegex(ValueError, "签名权限"):
                verify_entitlements("Runner", self.bundle_id)


if __name__ == "__main__":
    unittest.main()
