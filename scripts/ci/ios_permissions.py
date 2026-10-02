"""iOS 包权限归一化与归档校验，避免引擎只能由打包用户读取。"""

import argparse
import os
from pathlib import Path
import stat
import subprocess
import tarfile


MACHO_MAGIC = {
    b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf",
    b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
}


def normalize_permissions(root):
    root = Path(root)
    if not root.is_dir() or root.is_symlink():
        raise ValueError(f"不是实际目录: {root}")
    root.chmod(0o755)
    for directory, dirs, files in os.walk(root, followlinks=False):
        for name in dirs:
            path = Path(directory) / name
            if not path.is_symlink():
                path.chmod(0o755)
        for name in files:
            path = Path(directory) / name
            if path.is_symlink():
                continue
            mode = path.stat().st_mode
            if not stat.S_ISREG(mode):
                raise ValueError(f"不支持的文件类型: {path}")
            with path.open("rb") as stream:
                executable = bool(mode & 0o111) or stream.read(4) in MACHO_MAGIC
            path.chmod(0o755 if executable else 0o644)


def validate_mode(name, mode, *, directory=False, executable=False):
    required = 0o555 if directory or executable else 0o444
    if mode & required != required or mode & 0o7022:
        raise ValueError(f"归档权限不安全或不可读: {name}: {mode:o}")


def validate_deb(path):
    # 检查最终 tar，而不是当前用户可读取的临时解包目录。
    with subprocess.Popen(
        ["dpkg-deb", "--fsys-tarfile", str(path)], stdout=subprocess.PIPE,
    ) as process:
        with tarfile.open(fileobj=process.stdout, mode="r|*") as archive:
            for entry in archive:
                if entry.issym() or entry.islnk():
                    continue
                executable = False
                if entry.isfile():
                    with archive.extractfile(entry) as stream:
                        executable = stream.read(4) in MACHO_MAGIC
                validate_mode(entry.name, entry.mode, directory=entry.isdir(), executable=executable)
                if entry.uid != 0 or entry.gid != 0:
                    raise ValueError(f"DEB 文件归属不是 root: {entry.name}")
        if process.wait() != 0:
            raise ValueError("无法读取 DEB 数据归档")
    print("DEB 归档权限与 root 归属检查通过")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    normalize_permissions(args.directory)
