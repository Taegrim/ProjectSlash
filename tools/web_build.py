"""웹 빌드 도구 (개발용) — Web 내보내기, 로컬 서버로 브라우저에서 열기, 헤드리스 브라우저로 실행 확인.

    python tools/web_build.py              # 내보내기만 (build/web/index.html)
    python tools/web_build.py --serve      # 내보내기 + http://localhost:8060 서버 + 기본 브라우저로 열기 (Ctrl+C 로 종료)
    python tools/web_build.py --check [--shot 경로.png] [--wait 초]
                                           # 내보내기 + 서버 + Edge/Chrome 헤드리스로 index.html?selftest 를 연다.
                                           # 게임(scripts/web_selftest.gd)이 90 물리 프레임 뒤 자기 화면·상태를 서버로 보내면 통과
    --no-export                            # 이미 만든 build/web 을 그대로 쓴다

Godot 경로는 환경 변수 GODOT_BIN. 프리셋 이름은 export_presets.cfg 의 "Web" (스레드 없음 → 특별한 서버 헤더가 필요 없다).
내보낸 pck 에 tests/·tools/·docs/ 가 들어가지 않았는지도 확인한다.
"""

from __future__ import annotations

import argparse
import base64
import functools
import json
import http.server
import os
import shutil
import subprocess
import sys
import threading
import time
import webbrowser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "build" / "web"
PORT = 8060
BROWSERS = [
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
]


def export() -> None:
    godot = os.environ.get("GODOT_BIN")
    if not godot:
        sys.exit("GODOT_BIN 환경 변수가 없습니다 (.claude/settings.local.json 의 env)")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    started = time.time()
    result = subprocess.run([godot, "--headless", "--path", str(ROOT), "--export-release", "Web", str(OUT_DIR / "index.html")],
                            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=600)
    if result.returncode != 0 or not (OUT_DIR / "index.pck").exists():
        print(result.stdout[-3000:], result.stderr[-3000:])
        sys.exit("내보내기 실패")
    pck = (OUT_DIR / "index.pck").read_bytes()
    leaked = [folder for folder in ("tests", "tools", "docs") if f"res://{folder}/".encode() in pck]
    sizes = ", ".join(f"{p.name} {p.stat().st_size / 1e6:.1f}MB" for p in sorted(OUT_DIR.glob("index.*"))
                      if p.suffix in (".wasm", ".pck", ".js"))
    print(f"내보내기 완료 ({time.time() - started:.0f}초): {sizes}")
    if leaked:
        sys.exit(f"pck 에 개발용 폴더가 들어감: {leaked} (export_presets.cfg 의 exclude_filter 확인)")
    print("pck 에 tests/·tools/·docs/ 없음")


SELFTEST: dict = {}


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args) -> None:  # 요청 로그는 생략
        pass

    def do_POST(self) -> None:  # 게임의 자체 확인 보고 (scripts/web_selftest.gd)
        if self.path.startswith("/__selftest"):
            body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            SELFTEST.update(json.loads(body.decode("utf-8")))
        self.send_response(204)
        self.end_headers()


def start_server(port: int) -> http.server.ThreadingHTTPServer:
    """port 0 이면 빈 포트를 고른다 (--serve 로 띄운 서버가 8060 을 쓰고 있어도 --check 가 섞이지 않게).
    Windows 는 같은 포트를 두 번 열 수 있어(SO_REUSEADDR) 보고가 다른 서버로 가는 일이 있었다."""
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), functools.partial(Handler, directory=str(OUT_DIR)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def find_browser() -> str | None:
    for path in BROWSERS:
        if Path(path).exists():
            return path
    return shutil.which("msedge") or shutil.which("chrome")


def check(shot: Path, wait: float, port: int) -> bool:
    """헤드리스 브라우저로 ?selftest 페이지를 열고, 게임이 직접 보내는 화면·상태 보고를 기다린다."""
    browser = find_browser()
    if not browser:
        print("Edge/Chrome 을 찾지 못해 브라우저 확인을 건너뜀")
        return False
    SELFTEST.clear()
    args = [browser, "--headless=new", "--window-size=1280,720", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
            "--ignore-gpu-blocklist", "--autoplay-policy=no-user-gesture-required",
            f"--user-data-dir={ROOT / 'build' / 'browser-profile'}", f"http://127.0.0.1:{port}/index.html?selftest"]
    process = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    started = time.time()
    try:
        while not SELFTEST and time.time() - started < wait:
            time.sleep(0.5)
    finally:
        process.kill()
    if not SELFTEST:
        print(f"{wait:.0f}초 안에 게임의 보고가 없음 (엔진이 뜨지 않았거나 오류)")
        return False
    shot.parent.mkdir(parents=True, exist_ok=True)
    shot.write_bytes(base64.b64decode(SELFTEST.pop("png", "")))
    print(f"게임 보고 ({time.time() - started:.0f}초): {SELFTEST} — 게임 화면 저장: {shot}")
    return SELFTEST.get("frames", 0) >= 90 and SELFTEST.get("state") in ("AIRBORNE", "GRAPPLING", "DASHING")


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--serve", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--no-export", action="store_true")
    parser.add_argument("--shot", default=str(ROOT / "build" / "web_check.png"))
    parser.add_argument("--wait", type=float, default=90.0, help="게임 보고를 기다리는 최대 시간 (초)")
    args = parser.parse_args()
    if not args.no_export:
        export()
    if not (args.serve or args.check):
        return 0
    server = start_server(PORT if args.serve else 0)
    port = server.server_address[1]
    url = f"http://localhost:{port}/index.html"
    try:
        if args.check:
            ok = check(Path(args.shot), args.wait, port)
            print("브라우저 실행 확인: " + ("통과 (게임 화면이 그려짐)" if ok else "실패 또는 빈 화면"))
            if not args.serve:
                return 0 if ok else 1
        print(f"서버 실행 중: {url}  (Ctrl+C 로 종료)")
        webbrowser.open(url)
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        return 0
    finally:
        server.shutdown()


if __name__ == "__main__":
    sys.exit(main())
