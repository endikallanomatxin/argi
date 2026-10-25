"""Exercise terminal editing without relying on rendered text as source input."""

import errno
import os
import pty
import re
import select
import signal
import subprocess
import sys
import time


class Repl:
    def __init__(self, executable, colors):
        self.pid, self.master = pty.fork()
        if self.pid == 0:
            os.environ["TERM"] = "xterm-256color"
            if colors:
                os.environ.pop("NO_COLOR", None)
            else:
                os.environ["NO_COLOR"] = "1"
            os.execv(executable, [executable, "repl"])
        self.pending = bytearray()
        self.transcript = bytearray()
        self.reaped = False

    def until(self, marker):
        deadline = time.monotonic() + 40
        while marker not in self.pending:
            remaining = deadline - time.monotonic()
            assert remaining > 0, (marker, self.transcript[-8000:])
            ready, _, _ = select.select([self.master], [], [], remaining)
            assert ready, (marker, self.transcript[-8000:])
            try:
                data = os.read(self.master, 4096)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                data = b""
            assert data, (marker, self.transcript[-8000:])
            self.pending.extend(data)
            self.transcript.extend(data)
        del self.pending[:self.pending.index(marker) + len(marker)]

    def send(self, data):
        os.write(self.master, data)

    def line(self, text, continuation, spaces=0):
        self.send(text + b"\n")
        # Redraws also contain prompts. Wait for Enter's newline before looking
        # for the next initial prompt and its actual editable indentation.
        self.until(b"\r\n")
        self.until(b"\x1b[2K" + (b"... " if continuation else b">>> ") + b" " * spaces)

    def quit(self):
        self.send(b":quit\n")
        deadline = time.monotonic() + 40
        while time.monotonic() < deadline:
            finished, status = os.waitpid(self.pid, os.WNOHANG)
            if finished:
                self.reaped = True
                assert os.waitstatus_to_exitcode(status) == 0, self.transcript[-8000:]
                return
            time.sleep(0.01)
        raise AssertionError(("REPL did not exit", self.transcript[-8000:]))

    def close(self):
        if not self.reaped:
            os.kill(self.pid, signal.SIGKILL)
            os.waitpid(self.pid, 0)
        os.close(self.master)


def check_editor(executable):
    repl = Repl(executable, colors=True)
    try:
        repl.until(b">>> ")
        repl.line(b"answer := () -> (.result: Int32 = 0) {", True, 4)
        repl.line(b"if true {", True, 8)
        repl.line(b"result = 42", True, 8)
        repl.line(b"}", True, 4)
        repl.line(b"}", False)
        assert b"\x1b[2K...     }" in repl.transcript, repl.transcript[-8000:]
        assert b"\x1b[2K... }" in repl.transcript, repl.transcript[-8000:]
        assert b"\x1b[35mif\x1b[0m" in repl.transcript, repl.transcript[-8000:]
        assert b"\x1b[33m42\x1b[0m" in repl.transcript, repl.transcript[-8000:]
        repl.send(b"answer()\n")
        repl.until(b"_0 = 42")
        repl.until(b">>> ")
        repl.send(b"\x1b[A\n")
        repl.until(b"_1 = 42")
        repl.until(b">>> ")
        repl.line(b"unfinished := () -> () {", True, 4)
        repl.send(b"\x03")
        repl.until(b"^C")
        repl.until(b">>> ")
        repl.send(b"answer()\n")
        repl.until(b"_2 = 42")
        repl.until(b">>> ")
        repl.quit()
    finally:
        repl.close()


def check_plain(executable):
    repl = Repl(executable, colors=False)
    try:
        repl.until(b">>> ")
        repl.send(b"42\n")
        repl.until(b"_0 = 42")
        repl.until(b">>> ")
        repl.quit()
        assert re.search(rb"\x1b\[[0-9;]*m", repl.transcript) is None, repl.transcript[-8000:]
    finally:
        repl.close()
    result = subprocess.run([executable, "repl"], input=b'text ::= "a\nb"\ntext\n:quit\n',
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=40)
    assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
    assert b'_0 = "a\\nb"' in result.stdout, result.stdout
    assert b"\x1b" not in result.stdout, result.stdout


if __name__ == "__main__":
    executable = os.path.abspath(sys.argv[1])
    check_editor(executable)
    check_plain(executable)
