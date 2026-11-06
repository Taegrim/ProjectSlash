## 기본 이동 · 충돌 · 카메라 튜닝값 (기획서 §5, §12).
## 모든 숫자는 [튜닝] 임시값이다. Phase 1 플레이 테스트로 조정하고 결과를 docs/DECISIONS.md 에 남긴다.
## 하단 사망 높이(FallLimitY)는 코스마다 다를 수 있어 코스 데이터(TestCourse.fall_limit_y)에 둔다.
class_name MovementTuning
extends Resource

## 최고 속도를 어떤 기준으로 제한할지 (§5.2 [중요]: 두 방식을 모두 시험할 수 있어야 한다)
enum SpeedCapMode {
	HORIZONTAL_AND_TOTAL, ## 수평 속도 상한 + 과도한 전체 속력 방지 상한 (기획서 초안 권장)
	HORIZONTAL_ONLY, ## 수평 성분만 제한
	TOTAL_ONLY, ## 전체 속력만 제한
}

@export_group("기본 이동")
## 방향 입력 없이 유지·접근하는 전진 속도 (px/s) — AutoForwardSpeed
@export var auto_forward_speed: float = 320.0
## 중력 가속도 (px/s²) — Gravity. Phase 1 에서 900 → 520 (무조작 시 A 벽 충돌·감속 흐름이 보이고 체공감에 가깝게)
@export var gravity: float = 520.0
## 전진 속도보다 느릴 때 다가가는 공중 가속도 (px/s²) — AirAcceleration
@export var air_acceleration: float = 600.0
## 전진 속도보다 빠를 때 줄이는 감속도 (px/s², §5.1 '감속 강도'). 작을수록 스윙·돌진에서 얻은 관성이 오래 간다
@export var air_deceleration: float = 150.0
## 와이어 해제·돌진 직후 체공 상한을 넘는 몫을 줄이는 감속도 (px/s²). 즉시 자르지 않아 해제 시 수평 관성을
## 보존하되(§6.4 [확정]), 상한 초과 속도가 영구히 유지되지는 않게 한다(§5.2 [확정])
@export var over_cap_deceleration: float = 900.0
## 일반 체공 수평 속도 상한 (px/s) — MaxAirHorizontalSpeed
@export var max_air_horizontal_speed: float = 520.0
## 일반 체공 전체 속력 상한 (px/s) — MaxAirTotalSpeed
@export var max_air_total_speed: float = 1100.0
@export var speed_cap_mode: SpeedCapMode = SpeedCapMode.HORIZONTAL_AND_TOTAL

@export_group("충돌 · 카메라")
## 일반 건물·장애물에 닿았을 때 속도에 곱하는 비율 (0~1, 1 = 감속 없음) — CollisionSpeedPenalty
@export_range(0.0, 1.0) var collision_speed_penalty: float = 0.5
## 카메라가 플레이어보다 앞(+X)을 비추는 거리 (px). 플레이어를 화면 중앙보다 왼쪽에 둔다 — CameraForwardOffset
@export var camera_forward_offset: float = 220.0
## 카메라가 스폰 높이보다 아래로 내려갈 수 있는 최대 거리 (px). 아래로 끝없이 따라가지 않게 한다
## (§3 [필수 주의]) — CameraVerticalFollowLimit. 위쪽으로는 제한 없이 따라간다.
@export var camera_vertical_follow_limit: float = 200.0
## 카메라 Y 를 플레이어 쪽으로 옮기는 세기 (1/s, 클수록 빨리 따라감). §3 'Y 축 완만 보정' — §12 에 없어 추가한 값
@export var camera_vertical_smoothing: float = 4.0
