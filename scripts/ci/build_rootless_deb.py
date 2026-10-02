#!/usr/bin/env python3
"""将已构建的 iOS app 打包为 Sileo 使用的 Rootless deb，不改变原 IPA。"""

import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


def build_deb(app: Path, output: Path) -> Path:
    with (app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    version = f"{info['CFBundleShortVersionString']}+{info['CFBundleVersion']}"
    output.mkdir(parents=True, exist_ok=True)
    deb = output.resolve() / f"fluxdo-{version}-rootless.deb"
    with tempfile.TemporaryDirectory(prefix="fluxdo-deb-") as temporary:
        root = Path(temporary) / "package"
        target = root / "var/jb/Applications/Fluxdo.app"
        target.parent.mkdir(parents=True)
        shutil.copytree(app, target, symlinks=True)
        executable = target / info["CFBundleExecutable"]
        # 越狱包使用伪签名；先签嵌套 Mach-O，最后为主程序赋予容器权限。
        magic = {b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"}
        for binary in sorted(target.rglob("*")):
            if binary.is_symlink() or not binary.is_file() or binary == executable:
                continue
            with binary.open("rb") as stream:
                if stream.read(4) not in magic:
                    continue
            subprocess.run(["ldid", "-S", str(binary)], check=True)
        entitlements = Path(temporary) / "entitlements.plist"
        with entitlements.open("wb") as stream:
            plistlib.dump({
                "application-identifier": info["CFBundleIdentifier"],
                "com.apple.developer.web-browser": True,
                "com.apple.private.security.container-required": True,
            }, stream)
        subprocess.run(["ldid", f"-S{entitlements}", str(executable)], check=True)
        metadata = root / "DEBIAN"
        metadata.mkdir()
        (metadata / "control").write_text(
            f"Package: {info['CFBundleIdentifier'].lower()}\n"
            f"Name: FluxDO\nVersion: {version}\nArchitecture: iphoneos-arm64\n"
            "Maintainer: Caun1112\nSection: Applications\nPriority: optional\n"
            "Depends: firmware (>= 15.0), uikittools\n"
            "Description: FluxDO with enlarged right-aligned floating navigation (rootless).\n"
            "Homepage: https://github.com/Caun1112/fluxdo\n",
            encoding="utf-8",
        )
        # 不清理应用数据。升级仅重新注册图标，卸载时仅注销应用。
        for name, action, command in (
            ("postinst", "configure", "/var/jb/usr/bin/uicache -p /var/jb/Applications/Fluxdo.app"),
            ("prerm", "remove|deconfigure", "/var/jb/usr/bin/uicache -u /var/jb/Applications/Fluxdo.app"),
        ):
            script = metadata / name
            script.write_text(
                f'#!/bin/sh\nset -e\ncase "$1" in\n  {action}) {command} ;;\nesac\nexit 0\n',
                encoding="utf-8",
            )
            script.chmod(0o755)
        environment = dict(os.environ, COPYFILE_DISABLE="1")
        subprocess.run(
            ["dpkg-deb", "--root-owner-group", "-Zgzip", "--build", str(root), str(deb)],
            check=True, env=environment,
        )
        subprocess.run(["dpkg-deb", "--info", str(deb)], check=True)
        subprocess.run(["dpkg-deb", "--contents", str(deb)], check=True, stdout=subprocess.DEVNULL)
    return deb


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(build_deb(args.app, args.output))
