"""Exercise real process interrupts without signalling the test runner."""

import errno
import os
import pty
import select
import signal
import subprocess
import sys
import time


def check_vm(argi, fixture):
    # Ignore interrupts across exec until the CLI installs its handler. This
    # avoids a readiness race with process startup without assuming build speed.
    child = subprocess.Popen(
        [argi, "run", "--vm", fixture, "--frontend-jobs", "1",
         "--vm-instructions", "1000000000"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_IGN),
    )
    try:
        deadline = time.monotonic() + 40
        while child.poll() is None and time.monotonic() < deadline:
            child.send_signal(signal.SIGINT)
            time.sleep(0.05)
        stdout, stderr = child.communicate(timeout=2)
        assert child.returncode == 130, (child.returncode, stdout, stderr)
        assert b"ExecutionCancelled" in stderr, stderr
    finally:
        if child.poll() is None:
            child.kill()
        child.wait()


def check_repl(argi):
    pid, master = pty.fork()
    if pid == 0:
        os.execv(argi, [argi, "repl", "--vm-instructions", "1000000000"])
    pending = bytearray()
    transcript = bytearray()
    reaped = False

    def until(marker):
        deadline = time.monotonic() + 40
        while marker not in pending:
            remaining = deadline - time.monotonic()
            assert remaining > 0, (marker, transcript[-8000:])
            ready, _, _ = select.select([master], [], [], remaining)
            assert ready, (marker, transcript[-8000:])
            try:
                data = os.read(master, 4096)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                data = b""
            assert data, ("REPL closed before", marker, transcript[-8000:])
            pending.extend(data)
            transcript.extend(data)
        del pending[:pending.index(marker) + len(marker)]

    try:
        until(b">>> ")
        os.write(master, b"unfinished := {\x03")
        until(b">>> ")
        os.write(master, b":begin\n")
        until(b"... ")
        for line in [b'print("VM_RUNNING")', b"Writer#().flush(.self = writer)",
                     b"while true {}"]:
            os.write(master, line + b"\n")
            until(b"... ")
        os.write(master, b":end\n")
        # This line comes from executed code and an explicit flush, not editor
        # echo. Ctrl+C must now interrupt execution instead of discarding input.
        until(b"\r\nVM_RUNNING\r\n")
        os.write(master, b"\x03")
        until(b"ExecutionCancelled")
        until(b">>> ")
        os.write(master, b":reset\n")
        until(b">>> ")
        os.write(master, b"42\n")
        until(b"_0 = 42")
        until(b">>> ")
        os.write(master, b":quit\n")
        deadline = time.monotonic() + 40
        while time.monotonic() < deadline:
            finished, status = os.waitpid(pid, os.WNOHANG)
            if finished:
                reaped = True
                assert os.waitstatus_to_exitcode(status) == 0, transcript[-8000:]
                return
            time.sleep(0.01)
        raise AssertionError(("REPL did not exit", transcript[-8000:]))
    finally:
        if not reaped:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
        os.close(master)


if __name__ == "__main__":
    executable = os.path.abspath(sys.argv[1])
    check_vm(executable, sys.argv[2])
    check_repl(executable)
