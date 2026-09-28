"""Exercise the actual interactive picker with a terminal, without host networking."""
import os
import pty
import subprocess
from pathlib import Path

script = Path(__file__).with_name("profile-binding.sh")
for answer, expected in [
    (b"1\n", "SELECTED=74.219.23.237@ens3"),
    (b"99\n2\n", "SELECTED=74.219.23.240@ens3"),
    (b"\n", "SELECTED=@"),
]:
    master, slave = pty.openpty()
    try:
        process = subprocess.Popen(
            [os.environ.get("BASH_BIN", "bash"), str(script), "--menu"],
            stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        os.write(master, answer)
        try:
            output, _ = process.communicate(timeout=15)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate()
            raise
        assert process.returncode == 0, output.decode()
        assert expected in output.decode(), output.decode()
    finally:
        os.close(master)
        os.close(slave)
print("PASS: interactive selection, invalid choice retry, and default selection")
