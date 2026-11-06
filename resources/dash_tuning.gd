## 돌진 베기 튜닝값 (기획서 §7, §12). 모든 숫자는 [튜닝] 임시값이며 Phase 3 에서 사용·조정한다.
## 돌진 속도는 일반 체공 최고 속도와 별개의 값이다 (§5.1, §15-8).
class_name DashTuning
extends Resource

## 돌진이 끝난 뒤 속도를 체공 상한으로 되돌리는 방식 — PostDashVelocityPolicy (§5.2, §7.3)
enum PostDashVelocityPolicy {
	GRADUAL_DECELERATION, ## B안: 짧은 시간에 걸쳐 감속 (§16 '점진 감속 우선 시험')
	IMMEDIATE_CAP, ## A안: 종료 즉시 체공 상한 적용
}

@export_group("돌진")
## 자동 타기팅 사거리 (px) — DashRange
@export var dash_range: float = 480.0
## 돌진 중 속도 (px/s) — DashSpeed. Phase 3 리뷰 5번 "너무 빠르고 멀리 날아가 다음 구조물을 인지하기 어려움" → 1800 → 1200
## (일반 체공 상한 520 의 약 2.3배로 속도감은 유지). 끝난 뒤 상한까지 줄어드는 거리도 약 600px → 240px 로 줄어든다
@export var dash_speed: float = 1200.0
## 적 뒤쪽에서 멈추는 거리 (px). §7.1 [MVP 제안] 적 뒤쪽 종료 — DashEndOffset
@export var dash_end_offset: float = 90.0
## 돌진 최대 시간 (s) — MaxDashDuration. 사거리 480 + 적 뒤 90 을 1200px/s 로 가려면 0.48초 → 0.45 에서 0.6 으로
@export var max_dash_duration: float = 0.6
## 지금은 IMMEDIATE_CAP (Phase 4 리뷰 7번: "돌진 후 감속을 천천히 말고 바로"). 점진 감속 코드는 그대로 남아 있어
## 이 값 하나만 바꾸면 된다: 에디터에서 resources/default_dash.tres 를 열고 인스펙터의 Post Dash Velocity Policy 를
## Gradual Deceleration 으로 고르면 점진 감속(아래 post_dash_deceleration 사용)으로 돌아간다. 코드 수정 필요 없음
@export var post_dash_velocity_policy: PostDashVelocityPolicy = PostDashVelocityPolicy.IMMEDIATE_CAP
## 돌진이 끝날 때 위로 솟는 속도 상한 (px/s). 아래에서 위의 적을 베면 그 기세로 너무 높이 올라가던 문제
## (v0.2-3 리뷰: "아래서 위로 돌진할 때 너무 높이 올라감") — 체공 전체 상한(1100)만으로는 위로 900 넘게 남았다
@export var max_exit_up_speed: float = 300.0
## 점진 감속(GRADUAL_DECELERATION)일 때만 쓰는 감속도 (px/s²) — PostDashDeceleration
@export var post_dash_deceleration: float = 2400.0
