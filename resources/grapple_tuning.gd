## 와이어 발사 · 자동 스윙 · 해제 도약 튜닝값 (기획서 §6, §12).
## 모든 숫자는 [튜닝] 임시값이며 Phase 2 에서 사용·조정한다. 자동 보정은 '보조'일 뿐, 충돌을 무시하거나
## 순간이동시키는 데 쓰지 않는다 (§6.3, §15-5).
class_name GrappleTuning
extends Resource

## 로프 길이를 어떻게 다룰지 — RopeLengthPolicy
enum RopeLengthPolicy {
	FIXED_AT_ATTACH, ## 연결 순간 거리로 고정
	REEL_ASSIST, ## 연결 거리에서 시작해 제한적으로 감는다 (§6.3 ReelAssist)
}

@export_group("와이어 발사")
## 최대 연결 거리 (px) — GrappleMaxRange
@export var grapple_max_range: float = 520.0
## 연결점이 플레이어보다 최소 이만큼 위에 있어야 한다 (px). 스윙할 수 없는 낮은 연결 제외 (§6.2) — MinValidAttachHeight
@export var min_valid_attach_height: float = 40.0
@export var rope_length_policy: RopeLengthPolicy = RopeLengthPolicy.REEL_ASSIST
## 연결 가능한 표면 허용 각도 (도). 정확한 기준은 Phase 2 에서 정한다 — AllowedSurfaceAngle
@export_range(0.0, 180.0) var allowed_surface_angle: float = 100.0

@export_group("자동 스윙")
## 전방 진행을 돕는 접선 방향 보조 가속 (px/s²) — SwingAssistStrength
@export var swing_assist_strength: float = 600.0
## 보조 방향을 전방(+X)으로 얼마나 치우칠지 (0~1) — SwingTargetForwardBias
@export_range(0.0, 1.0) var swing_target_forward_bias: float = 0.6
## 제한적인 로프 당김 세기 (px/s²) — ReelAssistStrength
@export var reel_assist_strength: float = 300.0
## 로프가 줄어드는 최대 속도 (px/s) — MaxReelRate
@export var max_reel_rate: float = 220.0
## 스윙 중 최대 속력 (px/s) — MaxSwingSpeed
@export var max_swing_speed: float = 1000.0

@export_group("해제 도약")
## 해제 시 위쪽으로 더하는 속도 (px/s) — ReleaseUpImpulse
@export var release_up_impulse: float = 380.0
## 도약 보너스를 받기 위한 최소 연결 시간 (s) — MinAttachDuration
@export var min_attach_duration: float = 0.25
## 도약 보너스를 받기 위한 로프 팽팽 유지 시간 (s) — MinTautDuration
@export var min_taut_duration: float = 0.15
## 해제 도약 후 위쪽 속도 상한 (px/s). 연타로 무한 상승하지 않게 한다 (§6.4) — MaxReleaseVerticalSpeed
@export var max_release_vertical_speed: float = 650.0
