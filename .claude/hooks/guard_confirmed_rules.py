"""PreToolUse 훅 — 기획서(docs/GAME_DESIGN*.md)의 확정 규칙 변경을 차단한다.

CLAUDE.md 필수 지침 1 ("[확정] 규칙을 변경하지 말 것")과 START_PROMPT 의
"새로운 기획/물리 규칙을 임의로 확정하지 말 것"을 기계적으로 보장한다.

보호 대상
  - '[확정' 이 들어간 줄 ([확정], [확정/MVP 해석], [확정 + 연결 영역 제안] 등)
  - '임의로 바꾸면 안 되는 규칙' 절(## 15)의 모든 줄
판정
  - 보호 줄의 수정·삭제   → 차단
  - 새 [확정] 줄 추가      → 차단 (새 규칙은 [MVP 제안] 등으로 기록)
  - 그 밖의 수정 ([MVP 제안]/[튜닝]/[추후 결정], 결정 기록 추가 등) → 허용
확정 규칙을 바꿔야 하면 Claude 는 작업을 멈추고 사용자에게 승인을 받는다. 수정은 사용자가 직접 한다.
"""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

TAG = "[확정"
PROTECTED_SECTION_KEY = "바꾸면 안 되는 규칙"


def is_design_doc(path: Path) -> bool:
    return path.suffix.lower() == ".md" and path.name.startswith("GAME_DESIGN")


def normalize(text: str) -> str:
    return text.replace("\r\n", "\n")


def protected_lines(text: str) -> Counter:
    result: Counter = Counter()
    in_section = False
    for raw in normalize(text).split("\n"):
        line = raw.strip()
        if line.startswith("## "):
            in_section = PROTECTED_SECTION_KEY in line
        if line and (TAG in line or in_section):
            result[line] += 1
    return result


def apply_edit(text: str, old: str, new: str, replace_all: bool) -> str | None:
    old, new = normalize(old), normalize(new)
    if not old or old not in text:
        return None
    return text.replace(old, new) if replace_all else text.replace(old, new, 1)


def main() -> int:
    try:
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass
    try:
        # Windows 기본 stdin 인코딩(cp949)이 아니라 UTF-8 로 직접 디코딩해야 한글이 깨지지 않는다.
        payload = json.loads(sys.stdin.buffer.read().decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return 0
    tool = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}
    path = Path(tool_input.get("file_path") or "")
    if not is_design_doc(path):
        return 0

    before = normalize(path.read_text(encoding="utf-8")) if path.is_file() else ""
    pairs: list[tuple[str, str]] = []
    if tool == "Write":
        pairs.append((before, tool_input.get("content", "")))
    elif tool in ("Edit", "MultiEdit"):
        edits = tool_input.get("edits") if tool == "MultiEdit" else [tool_input]
        current = before
        for edit in edits or []:
            old, new = edit.get("old_string", ""), edit.get("new_string", "")
            applied = apply_edit(current, old, new, bool(edit.get("replace_all")))
            if applied is None:
                pairs.append((old, new))  # 파일에서 못 찾으면 조각끼리 비교
            else:
                current = applied
        pairs.append((before, current))
    else:
        return 0

    removed: Counter = Counter()
    added: Counter = Counter()
    for old_text, new_text in pairs:
        old_lines, new_lines = protected_lines(old_text), protected_lines(new_text)
        removed += old_lines - new_lines
        added += new_lines - old_lines
    if not removed and not added:
        return 0

    message = [f"[차단] {path.name} 의 확정 규칙은 Claude 가 변경할 수 없습니다 (CLAUDE.md 필수 지침 1)."]
    if removed:
        message.append("수정/삭제되는 보호 줄:")
        message += [f"  - {line}" for line in removed.elements()]
    if added:
        message.append("새로 추가되는 [확정]/보호 줄:")
        message += [f"  + {line}" for line in added.elements()]
    message.append("→ 확정 줄은 원문 그대로 두고 [MVP 제안]/[튜닝]/결정 기록만 수정하세요.")
    message.append("→ 확정 규칙 변경이 꼭 필요하면 작업을 멈추고 사용자에게 이유를 설명해 승인을 받으세요. "
                   "수정은 사용자가 직접 합니다.")
    print("\n".join(message), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
