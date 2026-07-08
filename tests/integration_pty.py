#!/usr/bin/env python3
"""Real end-to-end test: run the actual beacon daemon against a real PTY, fire
real hook processes, and read the actual OSC title bytes painted on the device.

Unlike tests/run.sh (which checks state files), this verifies the *rendered*
color on a genuine terminal, with the background repaint daemon running
concurrently -- the real delivery path minus Claude Code itself.
"""
import os, pty, re, select, shutil, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "src", "beacon.sh")

DOT2COLOR = {
    "\U0001F7E2": "green",
    "\U0001F534": "red",
    "\U0001F7E1": "yellow",
    "\U0001F7E3": "purple",
    "⚪":     "white",
}

tmp = tempfile.mkdtemp()
env = dict(os.environ)
env["HOME"] = os.path.join(tmp, "home"); os.makedirs(env["HOME"], exist_ok=True)
env["BEACON_STATE_DIR"] = os.path.join(tmp, "state")
env["BEACON_WORK_INTERVAL"] = "0.02"
env["BEACON_IDLE_INTERVAL"] = "0.05"
env["BEACON_NO_DAEMON"] = "1"   # hooks won't self-spawn; we run one daemon ourselves

master, slave = pty.openpty()
slave_path = os.ttyname(slave)
env["BEACON_DEVICE"] = slave_path

daemon = subprocess.Popen(["sh", SCRIPT, "daemon", slave_path], env=env,
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

buf = b""
failed = 0


def drain():
    global buf
    while select.select([master], [], [], 0)[0]:
        try:
            data = os.read(master, 8192)
        except OSError:
            break
        if not data:
            break
        buf += data


def color_now():
    drain()
    titles = re.findall(b"\x1b\\]0;([^\x07]*)\x07", buf)
    if not titles:
        return None
    title = titles[-1].decode("utf-8", "replace")
    return DOT2COLOR.get(title[0]) if title else None


def fire(cmd, stdin=""):
    subprocess.run(["sh", SCRIPT, cmd], env=env, input=stdin.encode(),
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.09)   # let the hook's paint + the daemon repaint land


def check(desc, want):
    global failed
    got = color_now()
    if got == want:
        print(f"ok   - {desc}  [rendered {got}]")
    else:
        print(f"FAIL - {desc}  (want {want}, rendered {got})")
        failed += 1


print("== real PTY integration (background daemon + real hook processes) ==")
fire("start")
fire("capture", '{"cwd":"/x/proj","prompt":"do the thing"}')
check("capture -> green", "green")

# nested subagent tree: main->A, A->B, A->C, then drain
fire("subup");                      check("subagent A -> purple", "purple")
fire("subup"); fire("subup");       check("nested A+B+C -> purple", "purple")
fire("subdown");                    check("B done, tree busy -> purple", "purple")
fire("subdown");                    check("C done, A busy -> purple", "purple")
fire("subdown");                    check("whole tree drained -> green", "green")

# attention + resume + done, verified on the real device
fire("notify", '{"message":"needs your permission"}'); check("perm -> red", "red")
fire("notify", '{"message":"waiting for your input"}'); check("idle does NOT downgrade red", "red")
fire("work");                       check("agent resumes -> green", "green")
fire("done");                       check("done -> white", "white")
fire("notify", '{"message":"waiting for your input"}'); check("idle does NOT override white", "white")
fire("subdown");                    check("straggler subagent after done stays white", "white")
fire("notify", '{"message":"needs your permission"}'); check("perm from white -> red", "red")

daemon.terminate()
try:
    daemon.wait(timeout=2)
except Exception:
    daemon.kill()
os.close(master); os.close(slave)
shutil.rmtree(tmp, ignore_errors=True)

print()
if failed:
    print(f"{failed} real-PTY check(s) FAILED")
    sys.exit(1)
print("All real-PTY checks passed.")
