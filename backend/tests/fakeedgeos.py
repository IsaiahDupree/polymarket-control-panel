"""
Builds a fake edgeos repo on disk so lifecycle E2E tests can start/stop REAL
processes without the actual trading stack.

The fake `edgeos.grid.hold_roller` module:
  - writes a pidfile (running_<module>_<pid>.json with its live flag) into
    EDGEOS_STATE_DIR on start
  - loops until its STOP file (STOP_HOLD) appears, then removes the pidfile
    and exits — same contract as the real bots

The fake `scripts/bot_status.py`:
  - scans the state dirs listed in FAKE_STATE_DIRS for pidfiles of processes
    that are still alive and prints the same JSON shape the real one does
"""
from __future__ import annotations

from pathlib import Path

GRID_MODULE = '''
import json, os, signal, sys, time
from pathlib import Path

STOP_NAME = "STOP_HOLD"

def main():
    state = Path(os.environ["EDGEOS_STATE_DIR"])
    state.mkdir(parents=True, exist_ok=True)
    live = "--live" in sys.argv
    pidfile = state / f"running_hold_roller_{os.getpid()}.json"
    pidfile.write_text(json.dumps({
        "pid": os.getpid(), "mod": "hold_roller", "live": live,
        "started": time.time(), "argv": sys.argv[1:],
    }))
    def cleanup(*_):
        try: pidfile.unlink()
        except OSError: pass
        sys.exit(0)
    signal.signal(signal.SIGTERM, cleanup)
    try:
        while not (state / STOP_NAME).exists():
            time.sleep(0.15)
    finally:
        cleanup()

if __name__ == "__main__":
    main()
'''

BOT_STATUS = '''
import json, os, sys, time
from pathlib import Path

def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False

procs = []
for d in os.environ.get("FAKE_STATE_DIRS", "").split(":"):
    if not d:
        continue
    for f in Path(d).glob("running_*.json"):
        try:
            info = json.loads(f.read_text())
        except Exception:
            continue
        if not alive(info["pid"]):
            continue
        up = int(time.time() - info["started"])
        procs.append({"pid": info["pid"], "mod": info["mod"], "state": d,
                      "up": f"{up // 60:02d}:{up % 60:02d}", "live": info["live"]})
print(json.dumps({"procs": procs}))
'''


def build(root: Path) -> Path:
    """Create the fake repo under root and return its path."""
    repo = root / "fake_edgeos_repo"
    (repo / "edgeos" / "grid").mkdir(parents=True, exist_ok=True)
    (repo / "scripts").mkdir(exist_ok=True)
    (repo / "edgeos" / "__init__.py").write_text("")
    (repo / "edgeos" / "grid" / "__init__.py").write_text("")
    (repo / "edgeos" / "grid" / "hold_roller.py").write_text(GRID_MODULE)
    (repo / "scripts" / "bot_status.py").write_text(BOT_STATUS)
    return repo
