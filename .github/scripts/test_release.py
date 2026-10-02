"""Check publication guards and recovery without modifying a remote."""

import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import publish_release


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        previous = Path.cwd()
        os.chdir(self.temporary.name)
        self.addCleanup(os.chdir, previous)
        self.environment = patch.dict(os.environ, {
            "RELEASE_VERSION": "0.2.0", "GITHUB_SHA": "commit",
            "GITHUB_REF": "refs/heads/main", "GITHUB_REPOSITORY": "example/argi",
        })
        self.environment.start()
        self.addCleanup(self.environment.stop)
        Path("dist").mkdir()
        Path("releases").mkdir()
        Path("releases/0.2.0.md").write_text("# Argi 0.2.0\n")

    def artifacts(self, commit="commit"):
        for target in ("linux-x86_64", "linux-aarch64", "macos-x86_64", "macos-aarch64"):
            name = f"argi-0.2.0-{target}"
            archive = Path("dist") / (name + ".tar.gz")
            content = json.dumps({"commit": commit, "version": "0.2.0", "target": target}).encode()
            with tarfile.open(archive, "w:gz") as output:
                info = tarfile.TarInfo(name + "/BUILD.json")
                info.size = len(content)
                output.addfile(info, io.BytesIO(content))
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            Path(str(archive) + ".sha256").write_text(f"{digest}  {archive.name}\n")

    @contextlib.contextmanager
    def remote(self, existing="", release=None):
        def query(*args):
            if args[:2] == ("git", "rev-parse"):
                return "commit"
            if args[:2] == ("git", "ls-remote"):
                return "commit\trefs/heads/main" if args[3] == "refs/heads/main" else existing
            self.fail(f"Unexpected remote read: {args}")

        def execute(args, **kwargs):
            if args[:2] == ["gh", "api"]:
                return subprocess.CompletedProcess(args, 0 if release else 1,
                                                   json.dumps(release), "" if release else "HTTP 404")
            return subprocess.CompletedProcess(args, 0)

        with patch.object(publish_release, "run", side_effect=query), \
             patch.object(publish_release.subprocess, "run", side_effect=execute) as calls:
            yield calls

    def test_rejects_artifacts_from_another_commit_before_writing(self):
        self.artifacts(commit="other")
        with self.remote() as calls:
            with self.assertRaisesRegex(RuntimeError, "source does not match"):
                publish_release.main()
        self.assertEqual(len(calls.call_args_list), 1)  # Read the release only.

    def test_resumes_draft_without_recreating_tag(self):
        self.artifacts()
        tag = "tag-object\trefs/tags/v0.2.0\ncommit\trefs/tags/v0.2.0^{}"
        with self.remote(tag, {"draft": True}) as calls:
            publish_release.main()
        commands = [call.args[0] for call in calls.call_args_list]
        self.assertFalse(any(command[:2] == ["git", "tag"] for command in commands))
        self.assertTrue(any(command[:3] == ["gh", "release", "upload"] for command in commands))
        self.assertIn(["gh", "release", "edit", "v0.2.0", "--draft=false", "--latest"], commands)
        self.assertEqual(len(Path("dist/SHA256SUMS").read_text().splitlines()), 4)

    def test_rejects_tag_on_another_commit(self):
        with self.remote("tag-object\trefs/tags/v0.2.0\nother\trefs/tags/v0.2.0^{}") as calls:
            with self.assertRaisesRegex(RuntimeError, "another release"):
                publish_release.main()
        calls.assert_not_called()


if __name__ == "__main__":
    unittest.main()
