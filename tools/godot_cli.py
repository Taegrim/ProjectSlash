"""ProjectSlash 하네스 공용 모듈 — Godot 실행 파일 탐색과 헤드리스 실행.

Godot 실행 파일 탐색 순서
  1) 환경 변수 GODOT_BIN
     머신마다 경로가 다르므로 .claude/settings.local.json 의 "env" 에 두고 커밋하지 않는다.
     Windows 에서는 콘솔 출력을 받을 수 있도록 *_console.exe 를 지정한다.
  2) PATH 의 godot / godot4

직접 실행하면 인자를 그대로 Godot 에 넘긴다 (작업 폴더 = 프로젝트 루트):
  python tools/godot_cli.py --version
  python tools/godot_cli.py --headless --path . --import
  python tools/godot_cli.py --path . -e            # 에디터 열기

표준 라이브러리만 사용한다.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent

_ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
# Godot 오류 줄 머리말: ERROR:, SCRIPT ERROR:, USER ERROR:, USER SCRIPT ERROR: (WARNING: 은 제외)
_ERROR_HEAD = re.compile(r"^\s*(?:USER )?(?:SCRIPT )?ERROR:")


class GodotNotFound(RuntimeError):
    pass


def use_utf8_stdio() -> None:
    """Windows 파이프/콘솔에서 한글이 깨지지 않도록 표준 출력을 UTF-8 로 고정한다."""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass


def find_godot() -> str | None:
    env = os.environ.get("GODOT_BIN", "").strip().strip('"')
    if env:
        return env if Path(env).is_file() else None
    for name in ("godot", "godot4"):
        found = shutil.which(name)
        if found:
            return found
    return None


def require_godot() -> str:
    exe = find_godot()
    if exe:
        return exe
    env = os.environ.get("GODOT_BIN", "").strip()
    if env:
        raise GodotNotFound(f"GODOT_BIN 경로에 파일이 없습니다: {env}")
    raise GodotNotFound(
        "Godot 실행 파일을 찾지 못했습니다. 환경 변수 GODOT_BIN 에 *_console.exe 경로를 지정하세요 "
        "(.claude/settings.local.json 의 env)."
    )


def strip_ansi(text: str) -> str:
    return _ANSI.sub("", text)


def run_godot(args: list[str], timeout: float = 300) -> tuple[int, str]:
    """프로젝트 루트에서 Godot 를 실행하고 (종료 코드, ANSI 를 제거한 stdout+stderr) 를 돌려준다."""
    proc = subprocess.run(
        [require_godot(), *args],
        cwd=PROJECT_ROOT,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
    )
    return proc.returncode, strip_ansi(proc.stdout or "")


def error_blocks(output: str) -> list[str]:
    """오류 줄과 바로 다음의 'at:' 위치 줄을 묶어서 돌려준다."""
    lines = output.splitlines()
    blocks: list[str] = []
    for i, line in enumerate(lines):
        if _ERROR_HEAD.match(line):
            block = line.strip()
            if i + 1 < len(lines) and lines[i + 1].strip().startswith("at:"):
                block += "\n    " + lines[i + 1].strip()
            blocks.append(block)
    return blocks


if __name__ == "__main__":
    use_utf8_stdio()
    try:
        exe = require_godot()
    except GodotNotFound as exc:
        print(exc, file=sys.stderr)
        sys.exit(127)
    sys.exit(subprocess.call([exe, *sys.argv[1:]], cwd=PROJECT_ROOT))
