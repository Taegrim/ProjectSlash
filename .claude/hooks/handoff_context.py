"""SessionStart 훅 (startup / clear / compact) — HANDOFF.md 를 컨텍스트에 자동으로 넣는다.

compact 나 /clear 로 이전 대화가 요약·삭제돼도, 작업 인계 문서를 읽어야 한다는 사실을 기억할
필요 없이 바로 현재 상태·결정 사항·다음 할 일을 이어받게 하는 것이 목적이다.

HANDOFF.md 위치 (먼저 찾은 것 사용)
  1) 프로젝트 상위 폴더   (저장소 밖, 기본)
  2) 프로젝트 루트
파일이 없으면 아무것도 하지 않는다. 출력 JSON 은 ASCII 이스케이프라 콘솔 인코딩 영향이 없다.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CANDIDATES = [ROOT.parent / "HANDOFF.md", ROOT / "HANDOFF.md"]
MAX_CHARS = 12_000
REASONS = {
    "compact": "컨텍스트가 compact 되어 이전 대화가 요약되었습니다",
    "clear": "컨텍스트가 비워졌습니다",
    "startup": "새 세션이 시작되었습니다",
    "resume": "세션을 이어서 시작했습니다",
}


def main() -> int:
    try:
        payload = json.loads(sys.stdin.buffer.read().decode("utf-8") or "{}")
    except (json.JSONDecodeError, UnicodeDecodeError):
        payload = {}
    handoff = next((p for p in CANDIDATES if p.is_file()), None)
    if handoff is None:
        return 0

    text = handoff.read_text(encoding="utf-8")
    if len(text) > MAX_CHARS:
        text = text[:MAX_CHARS] + f"\n\n…(길어서 잘림 — 전체는 {handoff} 를 Read 로 확인)"
    reason = REASONS.get(str(payload.get("source", "")), "세션이 시작되었습니다")
    context = (
        f"[HANDOFF 자동 주입] {reason}. 아래는 작업 인계 문서 {handoff} 의 내용이다.\n"
        "1) 이것을 기준으로 현재 상태·사용자 결정·다음 할 일을 파악한다. 이미 정해진 것은 다시 묻지 않는다.\n"
        "2) '진행 중' 항목이 있으면 git status / git log 와 실제 파일로 어디까지 됐는지 대조한 뒤 이어서 한다.\n"
        "3) 문서와 실제 상태가 다르면 실제 상태를 따르고 HANDOFF.md 를 고친다.\n\n"
        + text
    )
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": context}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
