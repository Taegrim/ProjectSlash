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
## 돌진 중 속도 (px/s) — DashSpeed
@export var dash_speed: float = 1800.0
## 적 뒤쪽에서 멈추는 거리 (px). §7.1 [MVP 제안] 적 뒤쪽 종료 — DashEndOffset
@export var dash_end_offset: float = 90.0
## 돌진 최대 시간 (s) — MaxDashDuration
@export var max_dash_duration: float = 0.45
@export var post_dash_velocity_policy: PostDashVelocityPolicy = PostDashVelocityPolicy.GRADUAL_DECELERATION
## 점진 감속일 때의 감속도 (px/s²) — PostDashDeceleration
@export var post_dash_deceleration: float = 2400.0
