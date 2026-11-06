## 와이어 발사 · 자동 스윙 · 해제 도약 튜닝값 (기획서 §6, §12).
## 모든 숫자는 [튜닝] 임시값이며 Phase 2 에서 사용·조정한다. 자동 보정은 '보조'일 뿐, 충돌을 무시하거나
## 순간이동시키는 데 쓰지 않는다 (§6.3, §15-5).
class_name GrappleTuning
extends Resource

## 로프 길이를 어떻게 다룰지 — RopeLengthPolicy
enum RopeLengthPolicy {
	FIXED_AT_ATTACH, ## 연결 순간 거리로 고정
	REEL_ASSIST, ## 연결 거리가 max_swing_radius 보다 길면 그 길이까지 제한적으로 감는다 (§6.3 ReelAssist)
}

@export_group("와이어 발사")
## 최대 연결 거리 (px) — GrappleMaxRange. Phase 2 리뷰(걸 수 있는 범위가 짧음)로 520 → 720
@export var grapple_max_range: float = 720.0
## 연결점이 플레이어보다 최소 이만큼 위에 있어야 한다 (px) — MinValidAttachHeight. 음수면 그만큼 아래여도 걸린다.
## Phase 2 수정 리뷰 16번 "살짝만 위에 있어도 안 걸림" → 40 에서 -80 으로 (플레이어가 띠보다 80px 위까지는 걸림).
## 제한을 아예 없애면 A 를 넘은 높이에서 B 의 띠를 내려다보고 걸어 긴 로프의 원으로 넘어가 B 가 너무 쉬워진다 (§6.2)
@export var min_valid_attach_height: float = -80.0
@export var rope_length_policy: RopeLengthPolicy = RopeLengthPolicy.REEL_ASSIST
## 연결 가능한 표면 허용 각도 (도): 표면 법선과 위쪽 방향 사이 각이 이 값 이하일 때만 연결.
## 180 이면 모든 면 허용 (공중 구조물은 밑면에 걸어 반시계로 스윙), 100 이면 밑면 제외 — AllowedSurfaceAngle
@export_range(0.0, 180.0) var allowed_surface_angle: float = 180.0
## 로프를 감아도 이보다 짧아지지 않는다 (px). §12 에 없어 추가한 값
@export var min_rope_length: float = 48.0

@export_group("자동 스윙")
## 진자 회전 방향으로 더하는 접선 보조 가속 (px/s², 목표 각에 닿을 때까지) — SwingAssistStrength
@export var swing_assist_strength: float = 600.0
## 목표 각에 닿기 전까지 스윙 속도가 이보다 느려지지 않게 한다 (px/s). 진자 궤적이 멈추지 않게 — §12 에 없어 추가
@export var min_swing_speed: float = 300.0
## 진자 반지름 상한 (px). 이보다 먼 곳에 걸면 감아서 이 길이로 맞춘다 (긴 로프의 거대한 회전 방지) — §12 에 없어 추가
@export var max_swing_radius: float = 220.0
## 보조를 어디서 멈출지 (0~1) — SwingTargetForwardBias. 보조는 진행 방향이 '전방 위 45°×(1-값)'이 되는 지점까지:
## 0 이면 45° 위로 솟는 지점, 1 이면 수평으로 나아가는 지점(시계 방향은 연결점 바로 위)에서 멈춘다
@export_range(0.0, 1.0) var swing_target_forward_bias: float = 0.6
## 제한적인 로프 당김 세기 (px/s²) — ReelAssistStrength
@export var reel_assist_strength: float = 300.0
## 로프가 줄어드는 최대 속도 (px/s) — MaxReelRate
@export var max_reel_rate: float = 220.0
## 원을 도는 최대 각속도 (도/초). 짧은 로프에서 빙글빙글 너무 빨리 돌지 않게 한다 (수정 리뷰 16번) — §12 에 없어 추가
@export var max_swing_angular_speed: float = 200.0
## 스윙 중 최대 속력 (px/s) — MaxSwingSpeed
@export var max_swing_speed: float = 1000.0

@export_group("해제 도약")
## 해제 시 위쪽으로 더하는 속도 (px/s) — ReleaseUpImpulse
@export var release_up_impulse: float = 380.0
## 도약 보너스를 받기 위한 최소 연결 시간 (s) — MinAttachDuration
@export var min_attach_duration: float = 0.25
## 도약 보너스를 받기 위한 로프 팽팽 유지 시간 (s) — MinTautDuration
@export var min_taut_duration: float = 0.15
## 해제 후 위쪽 속도 상한 (px/s). 도약 보너스를 더해도, 진자가 위로 솟는 중에 놓아도 이보다 빠르게 솟지 않는다 (§6.4)
## — MaxReleaseVerticalSpeed. Phase 2 에서 650 → 450 (650 이면 A 에서 지붕보다 360px 위까지 솟아 B 까지 공짜로 넘는 수준)
@export var max_release_vertical_speed: float = 450.0
