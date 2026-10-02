#!/usr/bin/env python3
"""Package an installed compiler with relocatable runtime libraries."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parents[2]
LINUX_SYSTEM_LIBS = {
    "libc.so.6", "libm.so.6", "libdl.so.2", "libpthread.so.0", "librt.so.1",
    "libresolv.so.2", "libutil.so.1",
}


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def linux_dependencies(binary):
    dependencies = []
    for line in run("ldd", str(binary)).splitlines():
        if "not found" in line:
            raise RuntimeError(f"Unresolved runtime library: {line}")
        match = re.match(r"\s*(\S+) => (/\S+)", line)
        if match and match[1] not in LINUX_SYSTEM_LIBS:
            dependencies.append((match[1], Path(match[2])))
    return dependencies


def linux_license(source, destination):
    # Debian packages carry upstream notices and source provenance alongside
    # their libraries. Keep the complete notices for every bundled package.
    candidates = [source, source.resolve()]
    if str(source).startswith("/usr/lib/"):
        candidates.append(Path(str(source).removeprefix("/usr")))
    for candidate in candidates:
        result = subprocess.run(["dpkg-query", "-S", str(candidate)], text=True,
                                capture_output=True)
        if result.returncode == 0:
            owner = result.stdout.split(": ", 1)[0]
            package = owner.split(":", 1)[0]
            notice = Path("/usr/share/doc") / package / "copyright"
            if notice.is_file():
                shutil.copy2(notice, destination / f"{package}.copyright")
                return
    raise RuntimeError(f"No package license found for {source}")


def macos_dependencies(binary, executable):
    # Resolve each original load command before editing it. Dependencies can
    # use the executable's rpaths as well as those of their own loader.
    search = []
    for loader in (binary, executable):
        commands = run("otool", "-l", str(loader))
        for match in re.finditer(r"cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset", commands):
            search.append(match[1].replace("@loader_path", str(loader.parent))
                          .replace("@executable_path", str(executable.parent)))
    dependencies = []
    identity = subprocess.run(["otool", "-D", str(binary)], capture_output=True,
                              text=True).stdout.splitlines()[1:]
    for line in run("otool", "-L", str(binary)).splitlines()[1:]:
        name = line.strip().split(" (", 1)[0]
        if name in identity or name.startswith(("/usr/lib/", "/System/Library/")):
            continue
        if name.startswith("@rpath/"):
            candidates = [Path(path) / name.removeprefix("@rpath/") for path in search]
        else:
            candidates = [Path(name.replace("@loader_path", str(binary.parent))
                               .replace("@executable_path", str(executable.parent)))]
        source = next((path for path in candidates if path.is_file()), None)
        if source is None:
            raise RuntimeError(f"Cannot resolve {name} loaded by {binary}")
        dependencies.append((name, source.resolve()))
    return dependencies


def macos_license(source, destination):
    parts = source.resolve().parts
    if "Cellar" not in parts:
        raise RuntimeError(f"Expected a Homebrew runtime library: {source}")
    index = parts.index("Cellar")
    keg = Path(*parts[:index + 3])
    formula = parts[index + 1]
    notices = [path for path in keg.iterdir() if path.is_file() and
               path.name.upper().startswith(("LICENSE", "COPYING", "NOTICE", "COPYRIGHT"))]
    if not notices:
        raise RuntimeError(f"No license notices found in {keg}")
    for notice in notices:
        shutil.copy2(notice, destination / f"{formula}-{notice.name}")


def bundle_runtime(package):
    executable = package / "bin/argi"
    runtime = package / "lib/argi/runtime"
    licenses = package / "licenses"
    runtime.mkdir(parents=True)
    licenses.mkdir()
    macos = platform.system() == "Darwin"
    copied = {}
    queue = [(executable, executable)]
    while queue:
        source, target = queue.pop()
        dependencies = (macos_dependencies(source, executable) if macos
                        else linux_dependencies(source))
        for original_name, dependency in dependencies:
            name = dependency.name if macos else original_name
            resolved = dependency.resolve()
            if name in copied and copied[name] != resolved:
                raise RuntimeError(f"Conflicting runtime libraries named {name}")
            if name not in copied:
                copied[name] = resolved
                bundled = runtime / name
                shutil.copy2(resolved, bundled)
                bundled.chmod(bundled.stat().st_mode | 0o200)
                (macos_license if macos else linux_license)(dependency, licenses)
                queue.append((dependency, bundled))
            if macos:
                prefix = "@executable_path/../lib/argi/runtime/" if target == executable else "@loader_path/"
                subprocess.run(["install_name_tool", "-change", original_name,
                                prefix + name, str(target)], check=True)
        if macos:
            if target != executable:
                subprocess.run(["install_name_tool", "-id", "@loader_path/" + target.name,
                                str(target)], check=True)
        else:
            rpath = "$ORIGIN/../lib/argi/runtime" if target == executable else "$ORIGIN"
            subprocess.run(["patchelf", "--set-rpath", rpath, str(target)], check=True)
    if not any("LLVM" in name for name in copied):
        raise RuntimeError("The package did not include the LLVM runtime")
    if macos:
        # Editing load commands invalidates signatures. Ad-hoc signing makes
        # the relocated binaries loadable on Apple Silicon without a dev account.
        for binary in [*runtime.iterdir(), executable]:
            subprocess.run(["codesign", "--force", "--sign", "-", str(binary)], check=True)
    else:
        for name, resolved in linux_dependencies(executable):
            if not resolved.resolve().is_relative_to(runtime.resolve()):
                raise RuntimeError(f"Package still uses an external runtime: {name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--target", required=True,
                        choices=["linux-x86_64", "linux-aarch64", "macos-x86_64", "macos-aarch64"])
    args = parser.parse_args()
    version = re.search(r'\.version = "([0-9]+\.[0-9]+\.[0-9]+)"',
                        (ROOT / "build.zig.zon").read_text())[1]
    native = ("macos" if platform.system() == "Darwin" else "linux") + "-" + {
        "x86_64": "x86_64", "arm64": "aarch64", "aarch64": "aarch64",
    }[platform.machine()]
    if native != args.target:
        raise RuntimeError(f"Expected {args.target}, running on {native}")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    name = f"argi-{version}-{args.target}"
    with tempfile.TemporaryDirectory(prefix="argi-package-") as temporary:
        package = Path(temporary) / name
        shutil.copytree(args.prefix, package)
        shutil.copy2(ROOT / "LICENSE", package / "LICENSE")
        shutil.copy2(ROOT / ".github/scripts/binary_installation.md", package / "README.md")
        bundle_runtime(package)
        metadata = {"version": version, "target": args.target,
                    "commit": run("git", "-C", str(ROOT), "rev-parse", "HEAD")}
        (package / "BUILD.json").write_text(json.dumps(metadata, indent=2) + "\n")
        archive = output / f"{name}.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(package, arcname=name)
    digest = hashlib.file_digest(archive.open("rb"), "sha256").hexdigest()
    (output / f"{archive.name}.sha256").write_text(f"{digest}  {archive.name}\n")
    print(archive)


if __name__ == "__main__":
    main()
