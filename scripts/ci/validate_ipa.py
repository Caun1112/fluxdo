"""检查 IPA 结构及包内执行文件；不代表 TrollStore 真机安装验证。"""

import pathlib
import plistlib
import subprocess
import sys
import tempfile
import zipfile


def validate(path):
    ipa = pathlib.Path(path)
    if ipa.stat().st_size < 1024 * 1024:
        raise ValueError("IPA 小于 1 MiB，疑似不完整")
    with zipfile.ZipFile(ipa) as archive:
        if archive.testzip() is not None:
            raise ValueError("IPA 校验失败")
        names = set(archive.namelist())
        root = "Payload/Runner.app/"
        info = plistlib.loads(archive.read(root + "Info.plist"))
        executable = info["CFBundleExecutable"]
        if pathlib.PurePosixPath(executable).name != executable:
            raise ValueError("主执行文件名称无效")
        if archive.getinfo(root + executable).file_size == 0:
            raise ValueError("主执行文件为空")
        if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
            raise ValueError("IPA 不是 iPhoneOS 产物")
        for framework in ("App", "Flutter"):
            if root + f"Frameworks/{framework}.framework/{framework}" not in names:
                raise ValueError(f"缺少 {framework}.framework")
        for name in names:
            parts = pathlib.PurePosixPath(name)
            if parts.is_absolute() or ".." in parts.parts:
                raise ValueError(f"归档路径无效: {name}")
        print(f"IPA: {ipa.name}, {ipa.stat().st_size} 字节")
        print(f"Bundle: {info['CFBundleIdentifier']}, 最低 iOS: {info.get('MinimumOSVersion')}")
        # 在临时目录实际解包并逐个检查 Mach-O，诊断信息保留在 Actions 日志。
        with tempfile.TemporaryDirectory() as folder:
            archive.extractall(folder)
            main_binary = pathlib.Path(folder) / root / executable
            main_kind = subprocess.check_output(["file", "-b", str(main_binary)], text=True)
            if "Mach-O" not in main_kind or "arm64" not in main_kind:
                raise ValueError("主执行文件不是 arm64 Mach-O")
            for file in sorted(pathlib.Path(folder).rglob("*")):
                if not file.is_file():
                    continue
                kind = subprocess.check_output(["file", "-b", str(file)], text=True)
                if "Mach-O" not in kind:
                    continue
                print(f"原生文件: {file.relative_to(folder)}: {kind.strip()}")
                if "arm64" not in kind:
                    raise ValueError(f"原生文件缺少 arm64: {file}")
                signature = subprocess.run(
                    ["codesign", "-dv", "--entitlements", ":-", str(file)],
                    capture_output=True, text=True,
                )
                print(signature.stdout + signature.stderr)
                if signature.returncode and "not signed at all" not in signature.stderr:
                    raise ValueError(f"无法检查签名: {file}")
        print("IPA 结构验证通过；TrollStore 安装与启动仍需真机验证。")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("用法: python3 scripts/ci/validate_ipa.py <IPA>")
    validate(sys.argv[1])
