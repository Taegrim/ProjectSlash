"""PostToolUse 훅 — .gd/.tscn/.tres 를 수정한 직후 Godot 헤드리스로 검사한다.

  .gd          : godot --check-only (파스/정적 타입 오류, 약 0.3초)
  .tscn/.tres  : tests/run_tests.gd --load=<경로> (리소스 로드/참조 오류)

오류가 나면 class_name 캐시가 낡았을 수 있으므로 --import 로 캐시를 갱신한 뒤 한 번 더
검사하고, 그래도 오류면 exit 2 + stderr 로 Claude 에게 오류 내용을 돌려준다.
project.godot 이 없거나 Godot 를 찾지 못하면 아무것도 막지 않는다 (exit 0).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import godot_cli as gc  # noqa: E402

CHECKED_SUFFIXES = {".gd", ".tscn", ".tres"}
RUNNER = ROOT / "tests" / "run_tests.gd"
MAX_LINES = 15


def to_res_path(file_path: str) -> str | None:
    """Godot 가 관리하는 프로젝트 내부 파일이면 res:// 경로를, 아니면 None 을 돌려준다."""
    if not file_path:
        return None
    path = Path(file_path).resolve()
    if path.suffix not in CHECKED_SUFFIXES or not path.is_file():
        return None
    try:
        rel = path.relative_to(ROOT)
    except ValueError:
        return None
    if any(part.startswith(".") for part in rel.parts[:-1]):
        return None  # 숨김 폴더 (.godot, .claude 등)
    for parent in path.parents:
        if parent == ROOT:
            break
        if (parent / ".gdignore").exists():
            return None
    return "res://" + rel.as_posix()


def check(res_path: str) -> list[str]:
    if res_path.endswith(".gd"):
        args = ["--headless", "--path", ".", "--check-only", "--script", res_path]
    elif RUNNER.is_file():
        args = ["--headless", "--path", ".", "-s", "res://tests/run_tests.gd", "--", f"--load={res_path}"]
    else:
        return []
    code, out = gc.run_godot(args, timeout=60)
    errors = gc.error_blocks(out)
    if code != 0 and not errors:
        errors = [f"Godot 종료 코드 {code}", *out.strip().splitlines()[-10:]]
    return errors


def main() -> int:
    gc.use_utf8_stdio()
    try:
        # Windows 기본 stdin 인코딩(cp949)이 아니라 UTF-8 로 직접 디코딩한다.
        payload = json.loads(sys.stdin.buffer.read().decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return 0
    res_path = to_res_path((payload.get("tool_input") or {}).get("file_path") or "")
    if res_path is None or not (ROOT / "project.godot").is_file() or gc.find_godot() is None:
        return 0

    try:
        errors = check(res_path)
        if errors:
            gc.run_godot(["--headless", "--path", ".", "--import"], timeout=180)
            errors = check(res_path)
    except Exception as exc:  # 훅 자체 문제로 작업을 막지 않는다
        print(f"[godot_check] 검사 생략: {exc}", file=sys.stderr)
        return 0

    if not errors:
        return 0
    print(f"[Godot 검사 실패] {res_path}", file=sys.stderr)
    for error in errors[:MAX_LINES]:
        print(error, file=sys.stderr)
    if len(errors) > MAX_LINES:
        print(f"... 외 {len(errors) - MAX_LINES}건", file=sys.stderr)
    print("→ 위 오류를 수정하세요. (class_name 캐시는 갱신 후 재검사한 결과입니다. "
          "여러 파일을 이어서 수정하는 중이라 예상된 오류라면 마친 뒤 python tools/validate.py 로 확인)",
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
