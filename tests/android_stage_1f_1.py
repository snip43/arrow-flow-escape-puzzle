"""Exercise the actual APK on a newly created, disposable ArrowFlow1F1 AVD."""
import argparse
import json
import os
import shutil
import struct
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "com.romiqolab.arrowflow"
ACTIVITY = PACKAGE + "/com.godot.game.GodotApp"
SLOTS = ("save_a.json", "save_b.json")
PROFILE = "files/arrow_flow/"
SHOTS = ROOT / "docs/screenshots/stage_1f_1"
CATALOG = json.loads((ROOT / "levels/data/catalog.json").read_text())


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def wait_for(predicate, message):
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.4)
    raise RuntimeError(message)


class Emulator:
    def __init__(self, adb, serial, server_port=5037):
        self.command = [adb, "-P", str(server_port), "-s", serial]
        require(serial.startswith(("emulator-", "127.0.0.1:")), "A local emulator transport is required.")
        name = self.shell("getprop", "ro.boot.qemu.avd_name")
        require(name == "ArrowFlow1F1" and self.shell("getprop", "ro.boot.qemu") == "1",
                "Only the isolated ArrowFlow1F1 AVD is supported.")
        require(self.shell("wm", "size") == "Physical size: 720x1280" and
                self.shell("wm", "density") == "Physical density: 320", "Unexpected AVD geometry.")

    def raw(self, *args, data=None):
        attempts = 3 if args[:2] == ("exec-out", "screencap") else 1
        for attempt in range(attempts):
            result = subprocess.run(self.command + list(args), input=data, capture_output=True, timeout=120)
            if result.returncode == 0:
                return result.stdout
            if attempt + 1 == attempts:
                raise RuntimeError(f"adb {args}: {result.stderr.decode(errors='replace')}")
            time.sleep(1)

    def run(self, *args):
        return self.raw(*args).decode().strip()

    def shell(self, *args):
        return self.run("shell", *args)

    def launch(self):
        result = self.shell("am", "start", "-W", "-n", ACTIVITY)
        require(ACTIVITY in result and "Error:" not in result and "Status: timeout" not in result, result)
        # First launch on a cold software renderer can spend several seconds
        # compiling shaders. Wait for the actual game background at the corner.
        for _ in range(45):
            raw = self.raw("exec-out", "screencap")
            offset = len(raw) - 720 * 1280 * 4
            if offset in (12, 16) and raw[offset:offset + 3] == bytes.fromhex("101d27"):
                break
            time.sleep(1)
        else:
            raise RuntimeError("Game frame did not appear. Inspect the AVD for system dialogs.")
        time.sleep(1)
        pid = self.shell("pidof", PACKAGE)
        log = self.run("logcat", "-d", "--pid=" + pid, "-v", "brief")
        require(not any(tag in log for tag in ("SCRIPT ERROR:", "FATAL EXCEPTION", "Failed to load script")),
                "Application error in PID-scoped logcat.")
        print("Game process", pid, flush=True)
        return pid

    def frame(self, name=None):
        png = self.raw("exec-out", "screencap", "-p")
        require(png.startswith(b"\x89PNG\r\n\x1a\n") and struct.unpack(">II", png[16:24]) == (720, 1280),
                "Invalid portrait capture.")
        if name:
            SHOTS.mkdir(parents=True, exist_ok=True)
            (SHOTS / (name + ".png")).write_bytes(png)
        return png

    def tap(self, x, y):
        self.shell("input", "tap", str(x), str(y))
        time.sleep(1.7)

    def game_pixels(self, rows=1000):
        # Ignore focus/hover decoration on the bottom buttons. Compare HUD
        # and playfield from the actual Android framebuffer.
        raw = self.raw("exec-out", "screencap")
        start = len(raw) - 720 * 1280 * 4
        require(start in (12, 16), "Unexpected framebuffer format.")
        return raw[start:start + 720 * rows * 4]

    def arrow(self, level, arrow_id):
        row = CATALOG[level - 1]
        cell = next(a["path"][0] for a in row["arrows"] if a["id"] == arrow_id)
        step = min(984 / (row["width"] + .6), 1270 / (row["height"] + .6))
        x = 540 + (cell[0] + .5 - row["width"] / 2) * step
        y = 944 + (cell[1] + .5 - row["height"] / 2) * step
        return round(x * 2 / 3), round(y * 2 / 3)

    def has_arrow(self, level, arrow_id):
        x, y = self.arrow(level, arrow_id)
        pos = (720 * y + x) * 4
        pixels = self.game_pixels()
        return pixels[pos:pos + 3] == bytes.fromhex("a7f2dd")

    def move(self, level, arrow_id):
        wait_for(lambda: self.has_arrow(level, arrow_id), "Expected arrow " + arrow_id)
        def counter():
            pixels = self.game_pixels()
            return b"".join(pixels[(row*720+530)*4:(row*720+690)*4] for row in range(150,190))
        before = counter()
        self.tap(*self.arrow(level, arrow_id))
        wait_for(lambda: counter() != before, "Move did not finish: " + arrow_id)

    def slots(self):
        names = self.shell("run-as", PACKAGE, "ls", PROFILE).split()
        return {name: json.loads(self.run("exec-out", "run-as", PACKAGE, "cat", PROFILE + name))
                for name in SLOTS if name in names}

    def latest(self):
        return max(self.slots().values(), key=lambda slot: slot["revision"])

    def recovery(self, name):
        original = self.latest()
        cp = original["checkpoint"]
        def matches_checkpoint():
            pixels = self.game_pixels(1280)
            for arrow in CATALOG[cp["level"] - 1]["arrows"]:
                key = arrow["id"]
                x, y = self.arrow(cp["level"], key)
                pos = (720*y+x)*4
                color = pixels[pos:pos+3].hex()
                if key in cp["removed"]:
                    if color in ("a7f2dd", "ffd175"):
                        return False
                elif color != ("ffd175" if key == cp["hint"] else "a7f2dd"):
                    return False
            return True
        wait_for(matches_checkpoint, "Purchase was not visible on the board.")
        pid = self.shell("pidof", PACKAGE)
        for _ in range(2):
            self.shell("am", "force-stop", PACKAGE)
            new_pid = self.launch()
            require(pid != new_pid and self.latest() == original, "Paid save changed on cold start.")
            wait_for(matches_checkpoint, "Restored arrow positions or highlight differ.")
            self.frame(name)
            pid = new_pid

    def seed_dense(self):
        # Called only after the fresh-install gate and completion of the tutorial test.
        self.shell("am", "force-stop", PACKAGE)
        slots = self.slots()
        current = max(slots, key=lambda key: slots[key]["revision"])
        inactive = next(name for name in SLOTS if name != current)
        fixture = {"schema_version": 2, "revision": slots[current]["revision"] + 1,
                   "campaign": {"completed_count": 99}, "wallet": {"coins": 150}}
        path = PROFILE + inactive
        self.raw("shell", "-T", "run-as", PACKAGE, "sh", "-c", "'cat > " + path + ".tmp'",
                 data=json.dumps(fixture).encode())
        self.shell("run-as", PACKAGE, "mv", path + ".tmp", path)
        self.launch()

    def test_two_fingers(self):
        # Use the public UI Automator gesture API, with a single tap at the
        # same location as a positive control. The APK contains no test code.
        sdk = Path(shutil.which(self.command[0]) or self.command[0]).resolve().parents[1]
        platform = sdk / "platforms/android-34"
        libs = [platform / "android.jar", platform / "uiautomator.jar", platform / "optional/android.test.base.jar"]
        java = Path(os.environ["JAVA_HOME"]) / "bin/javac.exe"
        with tempfile.TemporaryDirectory(prefix="arrow-flow-touch-") as temp:
            jar = Path(temp) / "touch.jar"
            source = ROOT / "tests/android/TwoPointerTest.java"
            subprocess.run([java, "--release", "8", "-classpath", os.pathsep.join(map(str, libs)),
                            "-d", temp, source], check=True)
            subprocess.run([sdk / "build-tools/34.0.0/d8.bat", "--lib", libs[0], "--classpath", libs[1],
                            "--classpath", libs[2], "--output", jar, Path(temp) / "arrowflow/qa/TwoPointerTest.class"],
                           check=True)
            remote = "/data/local/tmp/arrowflow-qa-" + uuid.uuid4().hex + ".jar"
            self.run("push", str(jar), remote)
            try:
                self.tap(360, 1048)
                key = CATALOG[99]["solution"][0]
                wait_for(lambda: self.has_arrow(100,key), "Expected dense field.")
                original = self.game_pixels(1280)
                x, y = self.arrow(100,key)
                log = self.shell("uiautomator", "runtest", remote, "/system/framework/android.test.base.jar",
                                 "/system/framework/android.test.runner.jar", "-c", "arrowflow.qa.TwoPointerTest",
                                 "-e", "x", str(x), "-e", "y", str(y))
                require("ARROW_FLOW_TWO_POINTERS_INJECTED" in log and "OK (1 test)" in log and
                        "shortMsg=" not in log, log)
                time.sleep(2)
                require(self.game_pixels(1280) == original, "Two contacts changed the dense field.")
                self.move(100,key)
                print("PASS Android two fingers and single-tap control", flush=True)
            finally:
                self.shell("rm", remote)

    def exercise(self):
        require(not self.shell("pm", "list", "packages", "-u", PACKAGE), "A fresh AVD is required.")
        apk = ROOT / "build/android/arrow-flow-debug.apk"
        require("Success" in self.run("install", str(apk)), "Fresh install failed.")
        self.test_game()

    def test_game(self):
        self.shell("settings", "put", "secure", "immersive_mode_confirmations", "confirmed")
        self.shell("input", "keyevent", "KEYCODE_WAKEUP")
        self.shell("wm", "dismiss-keyguard")
        self.launch()
        self.frame("01_menu_emulator")
        menu = self.game_pixels()
        rotation = self.shell("wm", "user-rotation").split()
        try:
            self.shell("wm", "user-rotation", "lock", "1")
            time.sleep(2)
            require(self.game_pixels() == menu, "Portrait layout changed on rotation request.")
            self.frame()
        finally:
            self.shell("wm", "user-rotation", *rotation)
        self.tap(360, 1190)
        require(self.game_pixels() != menu, "Levels selector did not open.")
        self.shell("input", "keyevent", "4")
        time.sleep(1)
        require(self.game_pixels() == menu, "Android Back did not restore the menu.")
        self.tap(360, 1048)
        wait_for(lambda: self.has_arrow(1,"B"), "Tutorial did not finish loading.")
        self.frame("02_tutorial_emulator")
        field = self.game_pixels()
        require(field != menu, "Tutorial did not open.")
        x, y = self.arrow(1, "B")
        self.shell("input", "swipe", str(x), str(y), str(x + 70), str(y + 40), "350")
        time.sleep(1)
        require(self.game_pixels() == field, "Drag changed the board.")
        self.shell("input", "keyevent", "3")
        self.launch()
        require(self.game_pixels() == field, "Background/resume changed the board.")
        for arrow in CATALOG[0]["solution"]:
            self.move(1, arrow)
        won = self.latest()
        require(won["campaign"]["completed_count"] == 1 and won["wallet"]["coins"] == 55, "Tutorial reward.")
        self.tap(360, 785)
        first = CATALOG[1]["solution"][0]
        self.move(2, first)
        self.tap(610, 1197)
        hint = self.latest()
        cp = hint["checkpoint"]
        require(hint["wallet"]["coins"] == 25 and cp["hint"] and cp["used_hint"] and cp["level"] == 2
                and cp["lives"] == 3 and cp["removed"] == [first], "Hint purchase.")
        self.test_paid_attempts(first)

    def test_paid_attempts(self, first):
        self.recovery("03_hint_restored_emulator")
        blocked = blocked_arrow(CATALOG[1], first)
        for _ in range(3):
            self.tap(*self.arrow(2, blocked))
        failed = self.latest()
        require(failed["checkpoint"]["state"] == "failed", "Three blocked moves.")
        self.frame("04_failed_emulator")
        self.tap(360, 692)
        require(self.latest() == failed, "Insufficient funds caused a debit.")
        self.tap(360, 1197)
        fresh = self.latest()
        require("checkpoint" not in fresh and fresh["wallet"]["coins"] == 25, "Free restart.")
        self.tap(610, 1197)
        require(self.latest() == fresh, "Insufficient Hint charge.")
        self.seed_dense()
        self.tap(360, 1048)
        first = CATALOG[99]["solution"][0]
        wait_for(lambda: self.has_arrow(100,first), "Dense field did not finish loading.")
        self.frame("05_level_100_emulator")
        self.move(100, first)
        blocked = blocked_arrow(CATALOG[99], first)
        for _ in range(3):
            self.tap(*self.arrow(100, blocked))
        self.tap(360, 692)
        paid = self.latest()
        cp = paid["checkpoint"]
        require(paid["wallet"]["coins"] == 75 and cp["level"] == 100 and cp["removed"] == [first]
                and cp["errors"] == 3 and cp["lives"] == 1 and cp["kind"] == "continue", "Continue purchase.")
        self.recovery("06_continue_restored_emulator")
        self.shell("input", "keyevent", "4")
        time.sleep(1)
        left = self.latest()
        require("checkpoint" not in left and left["wallet"]["coins"] == 75, "Back after recovery.")
        self.test_two_fingers()
        print("PASS Android emulator smoke and paid recovery", flush=True)


def blocked_arrow(row, removed):
    arrows = [a for a in row["arrows"] if a["id"] != removed]
    occupied = {tuple(point) for a in arrows for point in a["path"]}
    for arrow in arrows:
        (px, py), (x, y) = arrow["path"][-2:]
        dx, dy = x - px, y - py
        while 0 <= x + dx < row["width"] and 0 <= y + dy < row["height"]:
            x, y = x + dx, y + dy
            if (x, y) in occupied:
                return arrow["id"]
    raise RuntimeError("No blocked arrow.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--serial", required=True)
    parser.add_argument("--server-port", default=5037, type=int)
    args = parser.parse_args()
    Emulator(args.adb, args.serial, args.server_port).exercise()
