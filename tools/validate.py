"""ProjectSlash 검증 하네스 — Phase 종료 전, 코어 액션 변경 후 실행한다.

  python tools/validate.py                  임포트 → 로드 검사 → 테스트
  python tools/validate.py --smoke          + 메인 씬을 헤드리스로 600프레임(10초) 실행
  python tools/validate.py --smoke 1200 --scene res://scenes/test_course.tscn
  python tools/validate.py --filter dash    파일/메서드 이름에 'dash' 가 들어간 테스트만

단계
  1. import : 에디터 헤드리스 임포트 → class_name 캐시/.uid 갱신, 임포트 오류 검출
  2. tests  : tests/run_tests.gd → 모든 .gd/.tscn/.tres 로드 검사 + tests/test_*.gd 실행
  3. smoke  : (선택) 씬을 --fixed-fps 60 으로 N프레임 실행하고 오류 출력 검출

종료 코드 0 = 실행한 모든 단계 통과.
한계: '오류 없이 로드/실행됨'과 테스트로 작성한 수치 조건까지만 보장한다.
조작감·시각·마우스 입력은 에디터에서 직접 플레이해 확인해야 한다.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import godot_cli as gc  # noqa: E402

RUNNER = "res://tests/run_tests.gd"
STEP_TIMEOUT = 600


def project_text() -> str:
    return (gc.PROJECT_ROOT / "project.godot").read_text(encoding="utf-8")


def has_main_scene() -> bool:
    return re.search(r'^run/main_scene\s*=\s*"[^"]+"', project_text(), re.M) is not None


def physics_tps() -> str:
    """--fixed-fps 를 물리 틱 레이트와 맞춰 1프레임 = 1물리틱으로 만든다 (테스트 결정성)."""
    m = re.search(r"^common/physics_ticks_per_second\s*=\s*(\d+)", project_text(), re.M)
    return m.group(1) if m else "60"


def without_banner(output: str) -> str:
    lines = [ln for ln in output.splitlines() if not ln.startswith("Godot Engine v")]
    return "\n".join(lines).strip()


def step_import() -> bool:
    code, out = gc.run_godot(["--headless", "--path", ".", "--import"], timeout=STEP_TIMEOUT)
    errors = gc.error_blocks(out)
    for e in errors:
        print(e)
    if code != 0:
        print(f"Godot 종료 코드 {code}")
    return code == 0 and not errors


def step_tests(runner_args: list[str]) -> bool:
    if not (gc.PROJECT_ROOT / "tests" / "run_tests.gd").is_file():
        print("tests/run_tests.gd 가 없습니다.")
        return False
    code, out = gc.run_godot(
        ["--headless", "--path", ".", "--fixed-fps", physics_tps(), "-s", RUNNER, "--", *runner_args],
        timeout=STEP_TIMEOUT,
    )
    print(without_banner(out))
    return code == 0


def step_smoke(frames: int, scene: str | None) -> bool:
    args = ["--headless", "--path", ".", "--fixed-fps", physics_tps(), "--quit-after", str(frames)]
    if scene:
        args.append(scene)
    elif not has_main_scene():
        print("메인 씬이 설정되지 않았습니다 (project.godot 의 run/main_scene). --scene 으로 지정하세요.")
        return False
    code, out = gc.run_godot(args, timeout=STEP_TIMEOUT)
    errors = gc.error_blocks(out)
    for e in errors:
        print(e)
    print(f"{scene or '메인 씬'} 을(를) {frames}프레임 실행, 오류 {len(errors)}건, 종료 코드 {code}")
    return code == 0 and not errors


def run_step(name: str, fn) -> bool:
    print(f"\n=== [{name}] ===", flush=True)
    started = time.perf_counter()
    try:
        ok = fn()
    except subprocess.TimeoutExpired as exc:
        print(f"시간 초과 ({exc.timeout:.0f}초)")
        ok = False
    print(f"--- [{name}] {'통과' if ok else '실패'} ({time.perf_counter() - started:.1f}초)", flush=True)
    return ok


def main() -> int:
    gc.use_utf8_stdio()
    parser = argparse.ArgumentParser(description="ProjectSlash 헤드리스 검증 하네스")
    parser.add_argument("--smoke", nargs="?", type=int, const=600, default=None, metavar="FRAMES",
                        help="씬을 헤드리스로 N프레임 실행 (기본 600 = 10초)")
    parser.add_argument("--scene", help="스모크 실행할 씬 (res://...). 기본은 메인 씬")
    parser.add_argument("--filter", help="이름에 이 문자열이 들어간 테스트만 실행")
    parser.add_argument("--skip-import", action="store_true", help="임포트 단계 생략 (빠른 반복용)")
    args = parser.parse_args()

    if not (gc.PROJECT_ROOT / "project.godot").is_file():
        print("project.godot 이 없습니다 (Phase 0 이전).")
        return 2
    try:
        exe = gc.require_godot()
    except gc.GodotNotFound as exc:
        print(exc)
        return 127
    print(f"Godot: {exe}")

    results: dict[str, bool] = {}
    if not args.skip_import:
        results["import"] = run_step("import", step_import)
    runner_args = [f"--filter={args.filter}"] if args.filter else []
    results["tests"] = run_step("tests", lambda: step_tests(runner_args))
    if args.smoke is not None:
        results["smoke"] = run_step("smoke", lambda: step_smoke(args.smoke, args.scene))

    summary = " / ".join(f"{k} {'통과' if v else '실패'}" for k, v in results.items())
    print(f"\n검증 결과: {summary}")
    return 0 if all(results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
