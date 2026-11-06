# Claude 작업 가이드 — ProjectSlash

## 프로젝트 목적

이 프로젝트는 2D 횡스크롤 무한 러너 액션 게임의 첫 프로토타입이다. 
`docs/GAME_DESIGN_v0.1.md`가 **게임플레이 요구사항의 단일 기준 문서**이다.

## 프로젝트 명칭

- 현재 프로젝트명은 **ProjectSlash** (임시 이름)이며, Godot 프로젝트의 `config/name`도 `ProjectSlash`로 설정한다.
- 다른 프로젝트명으로 임의 변경하지 않는다.

## 개발 환경

- 권장: Godot 4.7 안정 버전
- 스크립트: GDScript (**C# 금지: Godot 4의 웹 내보내기 제약 때문**)
- 렌더링: Compatibility
- 초기 플레이 환경: Windows PC, 마우스/키보드, 이후 Web/HTML5 내보내기
- 차후 모바일 네이티브 대응 가능성을 고려해 입력과 핵심 게임플레이를 분리

## 필수 지침

1. `docs/GAME_DESIGN_v0.1.md`의 **[확정] 규칙을 변경하지 말 것**.
2. **[MVP 제안]** 및 **[튜닝]** 항목은 바꿀 수 있으나 이유를 기록할 것.
3. 한 번에 완성 게임을 만들지 말고 Phase 0 → 1 → 2 → 3 → 4 순서로 작업할 것.
4. 각 Phase에서 **완료 기준**, 실행 방법, 남은 문제를 명시할 것.
5. 매 단계에 실제 테스트가 가능한 Godot 씬을 제공할 것. 자동 테스트를 못 했으면 테스트한 척하지 말 것.
6. 처음에는 임시 도형과 선만 사용한다. 에셋·VFX·사운드·메뉴는 최소화한다.
7. 스윙/돌진/중력/속도 제한은 조정 가능한 파라미터로 분리한다.
8. 자동 스윙이 **건물을 관통하거나 순간이동하는 문제**를 만들지 않도록 충돌 검사를 유지한다.
9. 마우스 조준은 와이어에만 사용한다. 돌진은 전방 적 자동 타기팅이다.
10. 코어 액션을 건드리는 변경 후 **스윙 해제 → 돌진 → 재연결** 회귀 테스트를 고려할 것.
11. 브라우저 내보내기 여부를 구현 초반부터 확인하고, 웹에서 동작하지 않는 기능/플러그인은 피한다.
12. 반드시 변경한 파일, 주요 의사결정, 테스트 여부를 답변에 간단히 기록한다.

## 초기 구현 권장 구조

```text
project.godot
scenes/
  main.tscn
  player.tscn
  building.tscn
  enemy.tscn
  hazard.tscn
  test_course.tscn
scripts/
  player_controller.gd
  grapple_controller.gd
  dash_controller.gd
  building.gd
  enemy.gd
  game_flow.gd
resources/
  movement_tuning.gd
  (필요할 경우 기타 튜닝 Resource)
docs/
  GAME_DESIGN_v0.1.md
  reference_grapple_action.png
  reference_grapple_sketch_original.png
```

폴더/클래스 이름은 예시이며 단순한 구조가 가능하면 과도한 추상화는 하지 않는다. `CharacterBody2D` 컨트롤러와 로프 제약 보정의 선택 이유를 짧게 설명한다.

## 참고 이미지 해석 기준

- `docs/reference_grapple_action.png`는 의도를 나타내는 **설명용 개념도**이며, 캐릭터가 건물을 통과하거나 임의의 벽면에서 무조건 넘는 기능을 의미하지 않는다.
- 기획 이미지보다 `docs/GAME_DESIGN_v0.1.md`의 충돌 및 물리 규칙을 우선한다.

## 검증 하네스

Claude가 작업 결과를 스스로 확인하기 위한 장치다. 세부 사용법은 각 파일 머리말에 있다.

| 구성 | 역할 |
|---|---|
| `python tools/validate.py` | 임포트(class_name 캐시 갱신) → 모든 `.gd/.tscn/.tres` 로드 검사 → `tests/test_*.gd` 실행. `--smoke [프레임]`으로 메인 씬 헤드리스 실행 추가, `--filter`로 일부 테스트만 |
| `tests/run_tests.gd`, `tests/test_case.gd` | 플러그인 없는 헤드리스 테스트 러너/기본 클래스. 물리·상태 전환 회귀 테스트는 `tests/test_*.gd`로 추가 |
| `.claude/hooks/godot_check.py` | (자동) `.gd/.tscn/.tres` 수정 직후 해당 파일 파스/로드 검사, 오류 시 즉시 피드백 |
| `.claude/hooks/guard_confirmed_rules.py` | (자동) 기획서의 `[확정]` 줄·15절 수정/삭제와 새 `[확정]` 추가를 차단 |

- Godot 경로는 환경 변수 `GODOT_BIN`(콘솔용 `*_console.exe`)으로 지정한다. 머신별 값이므로 `.claude/settings.local.json`의 `env`에 두고 커밋하지 않는다.
- 각 Phase 종료 전과 코어 액션 변경 후 `python tools/validate.py --smoke`를 실행하고 결과를 보고에 포함한다.
- 헤드리스 검증은 "오류 없이 로드/실행됨"과 테스트로 작성한 수치 조건까지만 보장한다. 조작감·시각·마우스 입력은 에디터 실행(F5)으로 사용자가 확인해야 하므로 보고 시 **자동 검증 / 수동 확인 필요**를 구분한다.
- `tests/`, `tools/`는 개발 전용이다. 웹 내보내기 프리셋에서 `tests/*`를 제외한다(`tools/`, `docs/`는 `.gdignore`로 Godot가 무시).
- `.uid`, `.import`, `export_presets.cfg`는 커밋 대상이다.

## 보고 형식

각 작업 단계마다 다음을 보고한다.

- **구현한 기능:** 실제로 추가한 것
- **변경 파일:** 목록
- **실행/검증 방법:** Godot 에디터, 로컬 웹 확인 등
- **테스트한 것 / 테스트하지 못한 것:** 구분
- **남은 문제와 임시 파라미터:** 간단히
- **기획 확인이 필요한 사항:** 중요한 미확정 정책만

## 작업 종료 루틴

작업 단위(각 Phase 또는 사용자가 맡긴 작업)가 끝나면 아래 순서로 마무리한다.

1. **터미널 보고**: 위 보고 형식대로 답변한다.
2. **HANDOFF 갱신**: 아래 '작업 인계' 절대로 `HANDOFF.md`의 상태·다음 할 일·결정 사항·완료 이력을 고친다.
3. **Slack 보고**: `slack-report` 스킬로 작업일지 채널에 핵심만 보낸다 (한 일 / 막힌 것 / 다음 할 일, 빌드했으면 빌드 결과). 사용자가 이 용도로 요청한 것이므로 매번 따로 묻지 않는다. 환경 변수가 없거나 전송에 실패하면 그 사실만 알리고 넘어간다(재전송 반복 금지).
4. **리뷰 페이지**: `review-gallery` 스킬로 `output/<작업>-<날짜>/index.html`을 만들어 자동으로 열고, 사용자의 「의견 복사」 내용을 다음 작업의 요구사항으로 처리한다. 볼 화면이 있으면 스크린샷/GIF를, 없으면 한 일 목록을 항목으로 넣는다. 커밋처럼 확인할 결과물이 없는 짧은 후속 작업은 생략한다.

## Git 커밋 규칙

- 커밋과 푸시는 사용자가 요청할 때만 한다.
- 제목은 Conventional Commits 형식 `<타입>: <한국어 요약>` — 타입은 `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `style` 중 하나 (예: `feat: 플레이어 자동 전진과 중력 추가`).
- 본문은 무엇을 작업했는지만 한국어로 짧게 요약한다. `Co-Authored-By` 등 서명 줄은 넣지 않는다.

## 작업 인계 (HANDOFF)

compact·/clear 뒤에도 작업을 잇기 위해 **저장소 한 단계 위 폴더의 `HANDOFF.md`**(`../HANDOFF.md`, 커밋하지 않음)에 인계 내용을 유지한다.

- 세션 시작·compact·clear 직후 `.claude/hooks/handoff_context.py`(SessionStart 훅)가 그 내용을 컨텍스트에 자동으로 넣는다. 주입된 내용이 없으면 직접 읽는다.
- 재개할 때는 HANDOFF를 기준으로 상태를 파악하되, '진행 중' 항목은 `git status`/`git log`와 실제 파일로 대조한 뒤 이어서 한다. 문서와 실제가 다르면 실제를 따르고 문서를 고친다.
- 작업 종료 루틴마다 갱신하고, 긴 작업 도중에도 큰 단계가 끝나거나 중요한 결정·발견이 생기면 바로 고친다.
- **컨텍스트 78%**: 감시 훅(`.claude/hooks/context_watch.py`)이 갱신을 지시한다. 받으면 즉시 '진행 중'을 compact 뒤 이어갈 수 있을 만큼 구체적으로 갱신하고, 현재 단계만 마무리한 뒤 한 번 더 갱신하고 `python .claude/hooks/context_watch.py ready`를 실행한다. 새 큰 단계는 시작하지 않는다.
- **autocompact(약 80%)**는 ready 표시가 있거나 응답이 끝날 때까지 보류되고, 88%에서는 강제로 진행된다. 수동 `/compact`는 막지 않는다. 시점은 `.claude/settings.local.json`의 `CLAUDE_CODE_AUTO_COMPACT_WINDOW`(833000)로 정한다.
- 사용자 결정·선호는 '다시 묻지 말 것' 절에 남긴다. 분량은 8,000자 이내로 유지하고 코드·로그는 경로로 가리킨다.

## 첫 단계

처음에는 `START_PROMPT.md`의 요청대로 Phase 0부터 진행한다. 임의로 Phase 4까지 한 번에 만들지 않는다.
