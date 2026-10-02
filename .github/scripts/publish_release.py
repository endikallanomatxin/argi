#!/usr/bin/env python3
"""Publish the exact validated commit and its four native distributions."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tarfile


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    version = os.environ["RELEASE_VERSION"]
    commit = os.environ["GITHUB_SHA"]
    repository = os.environ["GITHUB_REPOSITORY"]
    tag = "v" + version
    assert run("git", "rev-parse", "HEAD") == commit
    assert os.environ["GITHUB_REF"] == "refs/heads/main"
    # Do not silently replace published versions or release an obsolete main.
    remote_main = run("git", "ls-remote", "origin", "refs/heads/main").split()[0]
    if remote_main != commit:
        raise RuntimeError("main changed during validation; release its current commit")
    existing = run("git", "ls-remote", "origin", "refs/tags/" + tag, "refs/tags/" + tag + "^{}")
    if existing:
        lines = existing.splitlines()
        tagged_commit = lines[-1].split()[0]
        if tagged_commit != commit or not lines[-1].endswith("^{}"):
            raise RuntimeError(f"{tag} already identifies another release")
    release_result = subprocess.run(
        ["gh", "api", f"repos/{repository}/releases/tags/{tag}"],
        text=True, capture_output=True)
    release = None
    if release_result.returncode == 0:
        release = json.loads(release_result.stdout)
        if not existing:
            raise RuntimeError("A release exists without its expected tag")
        if not release["draft"]:
            print(f"{tag} is already published; leaving it unchanged")
            return
    elif "404" not in release_result.stderr:
        raise RuntimeError(release_result.stderr)
    targets = {"linux-x86_64", "linux-aarch64", "macos-x86_64", "macos-aarch64"}
    archives = sorted(Path("dist").glob("*.tar.gz"))
    expected = {f"argi-{version}-{target}.tar.gz" for target in targets}
    if {path.name for path in archives} != expected:
        raise RuntimeError("The release does not contain all four native distributions")
    checksums = []
    for archive in archives:
        with archive.open("rb") as source:
            digest = hashlib.file_digest(source, "sha256").hexdigest()
        if Path(str(archive) + ".sha256").read_text().split()[0] != digest:
            raise RuntimeError(f"Checksum mismatch for {archive}")
        with tarfile.open(archive) as source:
            metadata = json.load(source.extractfile(archive.name.removesuffix(".tar.gz") + "/BUILD.json"))
        if metadata["commit"] != commit or metadata["version"] != version:
            raise RuntimeError(f"Artifact source does not match the release: {archive}")
        target = archive.name.removeprefix(f"argi-{version}-").removesuffix(".tar.gz")
        if metadata["target"] != target:
            raise RuntimeError(f"Artifact target does not match its filename: {archive}")
        checksums.append(f"{digest}  {archive.name}\n")
    checksum_file = Path("dist/SHA256SUMS")
    checksum_file.write_text("".join(checksums))
    notes = Path(f"releases/{version}.md").read_text()
    notes = notes.replace("(../", f"(https://github.com/{repository}/blob/{tag}/")
    notes_file = Path("dist/release-notes.md")
    notes_file.write_text(notes)
    subprocess.run(["git", "config", "user.name", "github-actions[bot]"], check=True)
    subprocess.run(["git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com"], check=True)
    if not existing:
        subprocess.run(["git", "tag", "-a", tag, "-m", f"Release {version}", commit], check=True)
        subprocess.run(["git", "push", "origin", "refs/tags/" + tag], check=True)
    if release is None:
        subprocess.run(["gh", "release", "create", tag, "--verify-tag", "--draft",
                        "--title", f"Argi {version}", "--notes-file", str(notes_file)], check=True)
    subprocess.run(["gh", "release", "upload", tag, "--clobber",
                    *map(str, archives), str(checksum_file)], check=True)
    subprocess.run(["gh", "release", "edit", tag, "--draft=false", "--latest"], check=True)


if __name__ == "__main__":
    main()
