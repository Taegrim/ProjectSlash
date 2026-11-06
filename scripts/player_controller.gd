## 플레이어 — CharacterBody2D 기반 상태 기계 (기획서 §9: AIRBORNE / GRAPPLING / DASHING / DEAD).
##
## CharacterBody2D 를 쓰는 이유 (§6.6 [권장]): 자동 전진·중력·로프 구속·접선 보정·돌진 전환을 한 물리 흐름에서
## 직접 제어하고, 모든 이동을 move_and_slide 의 충돌 검사로 통과시켜 건물 관통·순간이동을 막기 위해서다.
## RigidBody2D + PinJoint2D 는 연결·해제·돌진 전환을 예측 가능하게 제어하기 어렵다.
## 공중 체공이 기본이고 바닥 개념이 없어 motion_mode 는 FLOATING 으로 둔다 (player.tscn).
##
## 입력은 _unhandled_input 한 곳에서 '의도'(조준 지점, 와이어 연결/해제, 돌진)로 바꿔 하위 컨트롤러에 넘긴다.
## 모바일 터치 입력은 나중에 같은 request_* 함수를 부르면 된다 (입력과 핵심 게임플레이 분리).
## 마우스 조준은 와이어에만 쓰고, 돌진은 조준 없이 자동 타기팅이다 (§4 [확정]).
##
## Phase 1: AIRBORNE 이동(자동 전진·중력·속도 상한), 충돌 감속, 사망. GRAPPLING/DASHING 은 Phase 2·3.
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

## 충돌체 id → 마지막으로 닿은 물리 프레임
var _contacts := {}

@onready var grapple: GrappleController = $GrappleController
@onready var dash: DashController = $DashController


func _ready() -> void:
	grapple.setup(self, grapple_tuning)
	dash.setup(self, dash_tuning)


func _physics_process(delta: float) -> void:
	aim_point = get_global_mouse_position()
	match state:
		State.AIRBORNE:
			_step_airborne(delta)
		State.DEAD:
			pass  # §9.1 DEAD: 물리 액션 중지
		_:
			pass  # GRAPPLING (Phase 2), DASHING (Phase 3)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if state == State.DEAD:
		return
	if event.is_action_pressed("grapple"):
		grapple.request_attach(get_global_mouse_position())
	elif event.is_action_released("grapple"):
		grapple.request_release()
	elif event.is_action_pressed("dash"):
		dash.request_dash()


## 일반 체공: 중력 + 기본 전진 속도로 접근 + 속도 상한 → 충돌 검사 이동 → 새 접촉이면 감속 (§5.1, §8)
func _step_airborne(delta: float) -> void:
	velocity.y += movement.gravity * delta
	velocity.x = move_toward(velocity.x, movement.auto_forward_speed, movement.air_acceleration * delta)
	velocity = cap_speed(velocity, movement)
	move_and_slide()
	_apply_contact_penalty()


## 일반 체공 속도 상한 (§5.1 [확정] 최고 속도 제한, §5.2 [중요] 수평/전체 기준을 설정으로 선택)
static func cap_speed(v: Vector2, tuning: MovementTuning) -> Vector2:
	var capped := v
	match tuning.speed_cap_mode:
		MovementTuning.SpeedCapMode.HORIZONTAL_AND_TOTAL:
			capped.x = clampf(capped.x, -tuning.max_air_horizontal_speed, tuning.max_air_horizontal_speed)
			capped = capped.limit_length(tuning.max_air_total_speed)
		MovementTuning.SpeedCapMode.HORIZONTAL_ONLY:
			capped.x = clampf(capped.x, -tuning.max_air_horizontal_speed, tuning.max_air_horizontal_speed)
		MovementTuning.SpeedCapMode.TOTAL_ONLY:
			capped = capped.limit_length(tuning.max_air_total_speed)
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


func get_state_name() -> String:
	return State.keys()[state]


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, STATE_COLORS[state])
	draw_line(Vector2.ZERO, Vector2(RADIUS + 8.0, 0.0), Color(0.05, 0.07, 0.12), 3.0)  # 진행 방향 (+X)
	if state == State.DEAD or not debug_draw:
		return
	var aim := to_local(aim_point)
	draw_line(Vector2.ZERO, aim, Color(1, 1, 1, 0.18), 1.0)  # 와이어 조준선
	draw_arc(aim, 7.0, 0.0, TAU, 16, Color(1, 1, 1, 0.6), 1.5)
	if velocity.length() > 1.0:
		draw_line(Vector2.ZERO, velocity * 0.15, Color(1.0, 0.9, 0.2), 2.0)  # 속도 벡터
