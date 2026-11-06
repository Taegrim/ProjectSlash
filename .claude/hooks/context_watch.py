"""컨텍스트 사용량 감시 훅 — autocompact 전에 HANDOFF.md 를 갱신하게 하고, 단계가 끝날 때까지 autocompact 를 보류한다.

흐름 (비율은 전체 컨텍스트 창 기준, autocompact 자체는 settings.local.json 의
CLAUDE_CODE_AUTO_COMPACT_WINDOW 로 약 80% 에 오도록 설정)
  78%   PostToolUse/UserPromptSubmit → "지금 HANDOFF 갱신, 현재 단계만 마무리, 끝나면 ready 표시" 지시
  79%   그때까지 HANDOFF.md 가 안 바뀌었으면 한 번 더 강하게 지시
  80%~  PreCompact(auto) → ready 표시가 없으면 autocompact 보류 (exit 2). Claude 에게 단계 마무리 지시
  88%   안전 상한: 표시와 상관없이 autocompact 허용 (컨텍스트가 넘치지 않게)
  ready 표시: 단계를 끝낸 Claude 가 `python .claude/hooks/context_watch.py ready` 실행,
              또는 78% 이상에서 응답이 끝나면(Stop = 자연스러운 단계 경계) 자동으로 표시
  수동 /compact 는 막지 않는다 (PreCompact matcher 를 auto 로만 등록).

사용량: transcript_path(JSONL)의 마지막 메인 대화 assistant 응답 usage 합계 (+ 방금 도구 결과 추정치).
기록 파일은 비동기로 쓰여 한두 메시지 늦을 수 있으므로 78~80% 사이 여유로 흡수한다.
조정: 환경 변수 CONTEXT_WINDOW_TOKENS(기본 1000000), HANDOFF_SAVE_PCT(78), HANDOFF_URGENT_PCT(79),
      COMPACT_TRIGGER_PCT(80), COMPACT_HARD_CAP_PCT(88)
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HANDOFF_CANDIDATES = [ROOT.parent / "HANDOFF.md", ROOT / "HANDOFF.md"]
STATE_DIR = Path(tempfile.gettempdir())
READY_MARKER = STATE_DIR / "projectslash-compact-ready"
READY_COMMAND = "python .claude/hooks/context_watch.py ready"
TAIL_CHUNK = 1 << 20  # 기록 파일을 뒤에서부터 1MB 씩 읽는다


def env_float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return default


WINDOW = env_float("CONTEXT_WINDOW_TOKENS", 1_000_000)
SAVE_PCT = env_float("HANDOFF_SAVE_PCT", 78)
URGENT_PCT = env_float("HANDOFF_URGENT_PCT", 79)
TRIGGER_PCT = env_float("COMPACT_TRIGGER_PCT", 80)
HARD_CAP_PCT = env_float("COMPACT_HARD_CAP_PCT", 88)


def last_usage(transcript: Path) -> int | None:
    """마지막 메인 대화 assistant 응답 기준 컨텍스트 토큰 수 (서브에이전트 기록 제외)."""
    try:
        size = transcript.stat().st_size
        with transcript.open("rb") as fh:
            end, carry = size, b""
            while end > 0:
                start = max(0, end - TAIL_CHUNK)
                fh.seek(start)
                lines = (fh.read(end - start) + carry).split(b"\n")
                carry = lines[0] if start > 0 else b""
                for raw in reversed(lines[1:] if start > 0 else lines):
                    if b'"assistant"' not in raw or b'"usage"' not in raw:
                        continue
                    try:
                        entry = json.loads(raw)
                    except json.JSONDecodeError:
                        continue
                    if entry.get("type") != "assistant" or entry.get("isSidechain"):
                        continue
                    usage = (entry.get("message") or {}).get("usage") or {}
                    if usage:
                        thinking = (usage.get("output_tokens_details") or {}).get("thinking_tokens", 0)
                        return (usage.get("input_tokens", 0) + usage.get("cache_read_input_tokens", 0)
                                + usage.get("cache_creation_input_tokens", 0)
                                + max(0, usage.get("output_tokens", 0) - thinking))
                end = start
    except OSError:
        return None
    return None


def handoff_mtime() -> float:
    return next((p.stat().st_mtime for p in HANDOFF_CANDIDATES if p.is_file()), 0.0)


def state_file(session_id: str) -> Path:
    safe = "".join(c for c in session_id if c.isalnum() or c in "-_") or "default"
    return STATE_DIR / f"projectslash-context-watch-{safe}.json"


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def write_err(text: str) -> None:
    sys.stderr.buffer.write((text + "\n").encode("utf-8"))


def inject(event: str, text: str) -> None:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": event, "additionalContext": text}}))


def on_progress(event: str, pct: float, used: int, state: dict) -> None:
    """PostToolUse / UserPromptSubmit: 78·79·80% 에서 한 번씩 지시를 넣는다."""
    stage = state.get("stage", 0)
    left = max(0, int(WINDOW * TRIGGER_PCT / 100 - used))
    if pct >= TRIGGER_PCT and stage < 3 and not READY_MARKER.exists():
        state["stage"] = 3
        inject(event, (
            f"[컨텍스트 {pct:.1f}% — autocompact 보류 중] 현재 단계가 끝날 때까지 compact 를 미뤄 두었다 "
            f"({HARD_CAP_PCT:.0f}% 에서는 강제로 진행). 새 단계는 시작하지 말고 지금 단계만 마친 뒤, "
            f"HANDOFF.md 를 최신으로 고치고 `{READY_COMMAND}` 를 실행하라. 그러면 다음 요청에서 compact 된다."))
    elif pct >= URGENT_PCT and stage < 2 and handoff_mtime() <= state.get("reminded_at", 0):
        state["stage"] = 2
        inject(event, (
            f"[컨텍스트 {pct:.1f}% — compact 직전, 여유 약 {left:,} 토큰] HANDOFF.md 가 아직 갱신되지 않았다. "
            "다른 일을 멈추고 지금 즉시 HANDOFF.md '1. 지금 상태 > 진행 중'을 갱신하라."))
    elif pct >= SAVE_PCT and stage < 1:
        state.update(stage=1, reminded_at=time.time())
        inject(event, (
            f"[컨텍스트 {pct:.1f}% — 곧 autocompact({TRIGGER_PCT:.0f}%), 여유 약 {left:,} 토큰] 지금 바로 HANDOFF.md 를 "
            "갱신하라: '1. 지금 상태 > 진행 중'에 현재 작업, 끝낸 하위 단계, 바로 다음 하위 단계, 관련 파일, 미확인 사항을 "
            "compact 뒤 이어서 할 수 있을 만큼 구체적으로 적는다. 그 뒤 현재 단계만 마무리하고 새 큰 단계는 시작하지 않는다. "
            f"단계를 마치면 HANDOFF.md 를 한 번 더 고치고 `{READY_COMMAND}` 를 실행해 compact 를 허용한다."))


def on_precompact(payload: dict, pct: float) -> int:
    """PreCompact(auto): 단계가 끝났다는 표시가 없으면 보류. 상한을 넘으면 허용."""
    if payload.get("trigger", "auto") != "auto":
        return 0
    if READY_MARKER.exists() or pct >= HARD_CAP_PCT:
        READY_MARKER.unlink(missing_ok=True)
        return 0
    write_err(f"[autocompact 보류] 컨텍스트 {pct:.1f}% — 현재 단계를 마치고 HANDOFF.md 를 갱신한 뒤 "
              f"`{READY_COMMAND}` 를 실행하면 compact 된다 ({HARD_CAP_PCT:.0f}% 에서는 강제 진행).")
    return 2


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "ready":
        READY_MARKER.write_text(str(time.time()), encoding="utf-8")
        sys.stdout.buffer.write("compact 허용 표시함 — 다음 요청에서 autocompact 가 진행됩니다.\n".encode("utf-8"))
        return 0
    try:
        payload = json.loads(sys.stdin.buffer.read().decode("utf-8") or "{}")
    except (json.JSONDecodeError, UnicodeDecodeError):
        return 0
    event = payload.get("hook_event_name", "")
    transcript = Path(payload.get("transcript_path") or "")
    used = last_usage(transcript) if transcript.is_file() else None
    if used is None:
        return 0
    if event == "PostToolUse":
        used += len(json.dumps(payload.get("tool_response", ""), ensure_ascii=False)) // 3
    pct = used / WINDOW * 100

    if event == "PreCompact":
        return on_precompact(payload, pct)

    spath = state_file(str(payload.get("session_id", "")))
    state = load_json(spath)
    if pct < SAVE_PCT - 5:  # compact 뒤처럼 사용량이 충분히 내려가면 초기화
        state = {}
        READY_MARKER.unlink(missing_ok=True)

    if event == "Stop":
        if pct >= SAVE_PCT:  # 응답이 끝남 = 단계 경계 → 다음 요청에서 compact 허용
            READY_MARKER.write_text(str(time.time()), encoding="utf-8")
    elif event in ("PostToolUse", "UserPromptSubmit"):
        on_progress(event, pct, used, state)

    try:
        spath.write_text(json.dumps(state), encoding="utf-8")
    except OSError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
