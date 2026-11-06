## 플레이어 — CharacterBody2D 기반 상태 기계 (기획서 §9: AIRBORNE / GRAPPLING / DASHING / DEAD).
##
## CharacterBody2D 를 쓰는 이유 (§6.6 [권장]): 자동 전진·중력·로프 구속·접선 보정·돌진 전환을 한 물리 흐름에서
## 직접 제어하고, 모든 이동을 move_and_slide 의 충돌 검사로 통과시켜 건물 관통·순간이동을 막기 위해서다.
## RigidBody2D + PinJoint2D 는 연결·해제·돌진 전환을 예측 가능하게 제어하기 어렵다.
## 공중 체공이 기본이고 바닥 개념이 없어 motion_mode 는 FLOATING 으로 둔다 (player.tscn).
##
## 입력은 _unhandled_input 한 곳에서 '의도'(조준 지점, 와이어 연결/해제, 돌진)로 바꿔 하위 컨트롤러에 넘긴다.
## 모바일 터치 입력은 나중에 같은 request_* 함수를 부르면 된다 (입력과 핵심 게임플레이 분리).
## 좌클릭 하나로 와이어·돌진 (§4 [확정]): 누른 순간 조준이 건물 연결 띠 위면 와이어, 아니면 돌진. 돌진 대상은 조준과 무관한 자동 타기팅.
##
## Phase 1: AIRBORNE 이동(자동 전진·중력·속도 상한), 충돌 감속, 사망.
## Phase 2: GRAPPLING (와이어 스윙 — 속도 계산은 GrappleController, 이동·충돌은 여기서).
## Phase 3: DASHING (돌진 베기 — 속도·종료 판정은 DashController, 이동·충돌은 여기서).
class_name PlayerController
extends CharacterBody2D

signal state_changed(previous: State, current: State)
## 건물·적 등에 새로 부딪혔을 때 (감속 적용 직후)
signal bumped(collider: Object)
## 사망했을 때. reason = "fall" | "hazard"
signal died(reason: String)

enum State { AIRBORNE, GRAPPLING, DASHING, DEAD }

## player.tscn 의 CircleShape2D 반지름과 같아야 한다
const RADIUS := 16.0
## 같은 물체에 이 프레임 수 안에 다시 닿으면 새 접촉이 아니라 계속 닿아 있는 것으로 본다 (약 0.1초)
const CONTACT_MEMORY_FRAMES := 6
const STATE_COLORS := {
	State.AIRBORNE: Color(0.55, 0.9, 1.0),
	State.GRAPPLING: Color(0.98, 0.85, 0.35),
	State.DASHING: Color(1.0, 0.45, 0.35),
	State.DEAD: Color(0.45, 0.45, 0.5),
}

@export var movement: MovementTuning
@export var grapple_tuning: GrappleTuning
@export var dash_tuning: DashTuning

var state: State = State.AIRBORNE
## 디버그 그리기 (조준선, 속도 벡터). F1 로 토글
var debug_draw := true
## 마우스 조준 지점 (전역 좌표) — 와이어 전용
var aim_point := Vector2.ZERO
## 지금까지 새로 부딪힌 횟수 (디버그·테스트용)
var bump_count := 0
var death_reason := ""
## 조준점 연결 가능 여부 미리보기 (GrappleController.evaluate 결과)
var aim_preview := {}
## 공중 좌우 조작 방식 (A/B). 게임 중 바꾼 값을 재시작해도 유지하려고 static 으로 둔다. -1 이면 튜닝 기본값
static var air_control_override := -1
## 이번 프레임 좌우 입력 (-1 ~ 1). B안일 때만 읽는다. 테스트·봇은 debug_air_input 으로 넣는다
var air_input := 0.0
var debug_air_input := NAN
## 한 버튼 방식 기본값 (v0.2-5 사용자 결정: 좌클릭 하나로 와이어·돌진). false = 예전 두 버튼 (좌 와이어 / 우 돌진)
@export var one_button_default := true
## 게임 중 F3 로 바꾼 입력 방식 (재시작해도 유지하려고 static). -1 = one_button_default, 1 = 한 버튼, 0 = 두 버튼
static var one_button_override := -1
## 지금 돌진하면 벨 대상 {enemy, reason} (표시용)
var dash_preview := {}
## 캡처·테스트용: 유한한 값이면 마우스 대신 이 지점을 조준점으로 쓴다
var debug_aim_override := Vector2.INF

## 충돌체 id → 마지막으로 닿은 물리 프레임
var _contacts := {}
## 체공 상한을 넘어도 되는 남은 여유 (해제·돌진 직후 관성 보존용, 시간이 지나며 0 으로 줄어든다)
var _extra_horizontal := 0.0
var _extra_total := 0.0
var _extra_deceleration := 900.0

@onready var grapple: GrappleController = $GrappleController
@onready var dash: DashController = $DashController


func _ready() -> void:
	grapple.setup(self, grapple_tuning)
	dash.setup(self, dash_tuning)


func _physics_process(delta: float) -> void:
	aim_point = debug_aim_override if debug_aim_override.is_finite() else get_global_mouse_position()
	aim_preview = grapple.evaluate(aim_point) if state == State.AIRBORNE else {}
	air_input = 0.0
	if get_air_control_mode() == MovementTuning.AirControlMode.FINE:
		air_input = debug_air_input if not is_nan(debug_air_input) else Input.get_axis("move_left", "move_right")
	dash_preview = dash.find_target() if state in [State.AIRBORNE, State.GRAPPLING] else {}
	match state:
		State.AIRBORNE:
			_step_airborne(delta)
		State.GRAPPLING:
			grapple.apply_swing(delta)
			if state == State.GRAPPLING:
				move_and_slide()
				_apply_contact_penalty()
				grapple.after_move(delta)
		State.DASHING:
			dash.apply_dash(delta)
			if state == State.DASHING:
				move_and_slide()
				dash.after_move(delta)
		State.DEAD:
			pass  # §9.1 DEAD: 물리 액션 중지
		_:
			pass
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if state == State.DEAD:
		return
	if event.is_action_pressed("grapple"):
		press_action(aim_point if debug_aim_override.is_finite() else get_global_mouse_position())
	elif event.is_action_released("grapple"):
		grapple.request_release()
	elif event.is_action_pressed("dash"):
		dash.request_dash()


## 좌클릭(주 버튼) 누름. 한 버튼 방식(v0.2-5)이면 조준이 건물 연결 띠 위일 때만 와이어, 아니면 돌진(자동 타기팅).
## 두 버튼 방식이면 언제나 와이어 (돌진은 우클릭). 우클릭 돌진은 두 방식 모두 그대로 쓸 수 있다.
## 반환: "wire" | "dash" (요청 결과는 각 컨트롤러의 last_request 에 남는다)
func press_action(at: Vector2) -> String:
	if is_one_button() and not grapple.evaluate(at).get("ok", false):
		dash.request_dash()
		return "dash"
	grapple.request_attach(at)
	return "wire"


## 지금 한 버튼 방식인지 (게임 중 F3 로 바꾼 값이 우선)
func is_one_button() -> bool:
	return one_button_default if one_button_override < 0 else one_button_override == 1


## 일반 체공: 중력 + 기본 전진 속도로 접근(느리면 가속, 빠르면 감속) + 속도 상한 → 충돌 검사 이동 → 새 접촉이면 감속
## (§5.1, §8). 해제·돌진 직후의 상한 초과분은 over_cap_deceleration 으로 점차 줄인다.
func _step_airborne(delta: float) -> void:
	velocity.y += movement.gravity * delta
	# 목표 전진 속도: A안은 기본 전진 속도, B안은 좌우 입력만큼 올리고 내린다 (최소 속도 아래로는 안 감)
	var target := movement.auto_forward_speed
	var rate := movement.air_acceleration if velocity.x < target else movement.air_deceleration
	if air_input != 0.0:
		target = maxf(target + air_input * movement.air_control_speed_offset, movement.air_control_min_speed)
		rate = movement.air_control_acceleration
	velocity.x = move_toward(velocity.x, target, rate * delta)
	var decay := _extra_deceleration * delta
	_extra_horizontal = maxf(0.0, _extra_horizontal - decay)
	_extra_total = maxf(0.0, _extra_total - decay)
	velocity = cap_speed(velocity, movement, _extra_horizontal, _extra_total)
	move_and_slide()
	_apply_contact_penalty()


## 지금 속도가 체공 상한을 넘는 몫을 '여유'로 기억한다 (와이어 해제·돌진 종료 때 호출).
## 이후 체공 상한은 이 여유만큼 높게 시작해 deceleration(기본 over_cap_deceleration)으로 원래 상한까지 내려온다.
func carry_over_cap(deceleration := -1.0) -> void:
	_extra_horizontal = maxf(0.0, absf(velocity.x) - movement.max_air_horizontal_speed)
	_extra_total = maxf(0.0, velocity.length() - movement.max_air_total_speed)
	_extra_deceleration = deceleration if deceleration > 0.0 else movement.over_cap_deceleration


## 체공 상한을 즉시 적용한다 (돌진 종료 A안 IMMEDIATE_CAP, §7.3).
func apply_speed_cap_now() -> void:
	_extra_horizontal = 0.0
	_extra_total = 0.0
	velocity = cap_speed(velocity, movement)


## 일반 체공 속도 상한 (§5.1 [확정] 최고 속도 제한, §5.2 [중요] 수평/전체 기준을 설정으로 선택).
## extra_* 는 해제·돌진 직후 잠시 허용하는 상한 초과 여유.
static func cap_speed(v: Vector2, tuning: MovementTuning, extra_horizontal := 0.0, extra_total := 0.0) -> Vector2:
	var max_h := tuning.max_air_horizontal_speed + extra_horizontal
	var max_total := tuning.max_air_total_speed + extra_total
	var capped := v
	match tuning.speed_cap_mode:
		MovementTuning.SpeedCapMode.HORIZONTAL_AND_TOTAL:
			capped.x = clampf(capped.x, -max_h, max_h)
			capped = capped.limit_length(max_total)
		MovementTuning.SpeedCapMode.HORIZONTAL_ONLY:
			capped.x = clampf(capped.x, -max_h, max_h)
		MovementTuning.SpeedCapMode.TOTAL_ONLY:
			capped = capped.limit_length(max_total)
	return capped


## 건물·적에 '새로' 닿았을 때 한 번만 속도 × collision_speed_penalty (§8 [MVP 제안]).
## 지붕이나 벽에 닿은 채 미끄러지는 동안에는 반복 감속하지 않는다. 관통 방지는 move_and_slide 가 맡는다.
func _apply_contact_penalty() -> void:
	var frame := Engine.get_physics_frames()
	var first_new: Object = null
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var id := collision.get_collider_id()
		var last_seen: int = _contacts.get(id, -CONTACT_MEMORY_FRAMES - 1)
		if frame - last_seen > CONTACT_MEMORY_FRAMES and first_new == null:
			first_new = collision.get_collider()
		_contacts[id] = frame
	for id in _contacts.keys():
		if frame - int(_contacts[id]) > CONTACT_MEMORY_FRAMES:
			_contacts.erase(id)
	if first_new != null:
		velocity *= movement.collision_speed_penalty
		bump_count += 1
		bumped.emit(first_new)


## 사망 (§8: 하단 판정선 추락, 위험 장애물). 이후 물리 이동을 멈춘다.
func die(reason: String) -> void:
	if state == State.DEAD:
		return
	grapple.force_release("death")  # §6.5 플레이어 사망: 와이어 즉시 종료
	dash.cancel("death")
	death_reason = reason
	velocity = Vector2.ZERO
	set_state(State.DEAD)
	died.emit(reason)


func set_state(next: State) -> void:
	if next == state:
		return
	var previous := state
	state = next
	state_changed.emit(previous, next)
	queue_redraw()


## 지금 공중 좌우 조작 방식 (게임 중 F2 로 바꾼 값이 우선)
func get_air_control_mode() -> MovementTuning.AirControlMode:
	return movement.air_control_mode if air_control_override < 0 else air_control_override as MovementTuning.AirControlMode


func get_state_name() -> String:
	return State.keys()[state]


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, STATE_COLORS[state])
	draw_line(Vector2.ZERO, Vector2(RADIUS + 8.0, 0.0), Color(0.05, 0.07, 0.12), 3.0)  # 진행 방향 (+X)
	if state == State.DEAD:
		return
	# 조준 표시: 연결 가능한 곳을 가리키면 초록, 아니면 빨강 (§6.2 마우스가 유효 영역을 가리킬 때만 연결)
	var aim := to_local(aim_point)
	if state == State.AIRBORNE:
		var valid: bool = aim_preview.get("ok", false)
		var aim_color := Color(0.4, 1.0, 0.5, 0.9) if valid else Color(1.0, 0.4, 0.4, 0.7)
		draw_arc(aim, 8.0, 0.0, TAU, 18, aim_color, 2.0)
		if valid:
			draw_circle(to_local(aim_preview.point), 4.0, aim_color)  # 실제로 걸릴 지점
	# 돌진 타깃 미리보기: 지금 돌진하면 벨 적 (§7.2 자동 선택 결과를 보여 준다)
	var target: Enemy = dash_preview.get("enemy")
	if target != null:
		draw_arc(to_local(target.global_position), target.radius + 8.0, 0.0, TAU, 24, Color(1.0, 0.45, 0.35, 0.9), 3.0)
	if state == State.DASHING and is_instance_valid(dash.target):
		draw_line(Vector2.ZERO, to_local(dash.end_point), Color(1.0, 0.45, 0.35, 0.6), 2.0)
	if not debug_draw:
		return
	draw_line(Vector2.ZERO, aim, Color(1, 1, 1, 0.15), 1.0)  # 조준선
	if velocity.length() > 1.0:
		draw_line(Vector2.ZERO, velocity * 0.15, Color(1.0, 0.9, 0.2), 2.0)  # 속도 벡터
	if state == State.GRAPPLING:
		draw_circle(to_local(grapple.anchor), 5.0, Color(1.0, 0.85, 0.3))  # 연결점
		if grapple.last_assist != Vector2.ZERO:
			draw_line(Vector2.ZERO, grapple.last_assist * 0.08, Color(0.4, 1.0, 1.0), 3.0)  # 보조 가속 (§13.1)
