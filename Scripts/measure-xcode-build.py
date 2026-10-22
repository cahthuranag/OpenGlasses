#!/usr/bin/env python3
"""Record build wall time and host pressure without logging process arguments."""
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time


def main():
    if len(sys.argv) < 3:
        raise SystemExit("usage: measure-xcode-build.py output.jsonl xcodebuild [arguments...]")
    output, command = Path(sys.argv[1]), sys.argv[2:]
    if command[0] != "xcodebuild":
        raise SystemExit("expected xcodebuild")
    stop = threading.Event()
    started = time.monotonic()

    def query(*args):
        try:
            return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL, timeout=5).strip()
        except (subprocess.SubprocessError, OSError):
            return None

    with output.open("w", buffering=1) as log:
        def record(kind, **values):
            log.write(json.dumps(dict(kind=kind, at=datetime.now(timezone.utc).isoformat(), **values)) + "\n")

        record("host", cores=os.cpu_count(), memory_bytes=query("sysctl", "-n", "hw.memsize"),
               cpu=query("sysctl", "-n", "machdep.cpu.brand_string"), xcode=query("xcodebuild", "-version"))

        def sample():
            while not stop.is_set():
                processes = query("ps", "-axo", "pid,ppid,%cpu,rss,comm") or ""
                compilers = [line for line in processes.splitlines()
                             if any(name in line for name in ("swift-frontend", "clang", "xcodebuild", "ld-prime"))]
                record("sample", elapsed_seconds=round(time.monotonic() - started, 3),
                       load=os.getloadavg(), swap=query("sysctl", "vm.swapusage"),
                       vm=query("vm_stat"), disk=query("df", "-Pk", "."), compilers=compilers)
                stop.wait(15)

        sampler = threading.Thread(target=sample, daemon=True)
        sampler.start()
        process = subprocess.Popen(command, start_new_session=True)

        def forward(signum, _frame):
            if process.poll() is None:
                os.killpg(process.pid, signum)

        signal.signal(signal.SIGTERM, forward)
        signal.signal(signal.SIGINT, forward)
        try:
            result = process.wait()
        finally:
            stop.set()
            sampler.join(timeout=25)
        record("result", exit_code=result, elapsed_seconds=round(time.monotonic() - started, 3))
    return result


if __name__ == "__main__":
    sys.exit(main())
