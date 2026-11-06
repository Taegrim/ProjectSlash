## 와이어(그래플) 컨트롤러 — 건물 유효 표면 연결, 진자 궤적 자동 스윙, 해제 도약 (기획서 §6).
##
## 확정 규칙 (§6, §15):
## - 건물의 유효 표면(Building.get_attach_rect)에만 연결한다. 적에는 걸 수 없다.
## - 스윙형이며 방향키 없이 장애물 위로 진행하도록 자동 보정한다. 보정은 '보조'일 뿐 충돌을 무시하거나
##   순간이동시키지 않는다 — 여기서는 속도만 정하고, 실제 이동은 플레이어의 move_and_slide(충돌 검사)가 한다.
## - 좌클릭 해제 시 수평 관성을 유지하고 조건부로 위로 도약한다.
## - 유효한 돌진이 시작되면 와이어를 해제한다 (이때 도약 보너스 없음, §6.5 [MVP 제안]) → force_release().
##
## 스윙 방식 — 진자 궤적 (Phase 2 리뷰 10번, 사용자 요청: "물리와 상관없이 진자를 그리는 게 좋다"):
## 연결점을 중심으로 반지름 rope_length 인 원을 따라 돈다. 매 프레임 '원 위의 다음 지점'으로 가는 속도를 정하고
## move_and_slide 로 움직이므로, 막히면 그 자리에서 멈출 뿐 벽을 통과하거나 건너뛰지 않는다 (§6.3, §15-5).
##   - 회전 방향: 건물 종류로 정한다 (Building.aerial). 아래에서 솟은 건물 = 시계 방향 (왼쪽 → 위 → 지붕 쪽),
##                공중 구조물 = 반시계 방향 (아래 → 오른쪽 → 위). 플레이어 위치와 관계없다 (수정 리뷰 10번).
##   - 회전 속도: 원을 도는 각속도에 상한을 둔다 (짧은 로프에서 빙글빙글 돌지 않게, 수정 리뷰 16번).
##   - 자동 보조: 목표 각(진행 방향이 전방 위로 향하는 지점)에 닿을 때까지 접선 가속 + 최소 스윙 속도 보장.
##     목표를 지나면 보조를 끄고 중력만 받는 진자로 둔다 (놓지 않으면 자연스럽게 되돌아온다).
##   - 로프 길이: 최대 스윙 반지름보다 길게 걸면 그 길이까지 제한된 속도로 감는다 (긴 로프의 거대한 회전 방지).
##   - 해제: 원의 접선 속도를 그대로 넘기고(관성), 조건을 채웠으면 위로 도약한다 (상한 있음, 연타 무한 상승 불가).
## 실제로 넘을 수 없는 배치(낮은 연결점, 막힌 궤적)에서는 궤적이 막혀 안전 해제될 뿐 자동 성공시키지 않는다 (§6.3-6).
class_name GrappleController
extends Node

signal attached(anchor: Vector2, building: Building)
signal released(boosted: bool)

## 레이캐스트가 맞히는 대상: 건물(2) + 적(3, 맞으면 연결 실패 처리)
const RAY_MASK := 2 | 4
## 한 프레임 이동 속도 상한 = 최대 스윙 속도 + 이 값 (px/s). 궤적에서 밀려난 뒤 되돌아가는 보정도 이 안에서만
const RETURN_SPEED_MARGIN := 100.0
## 속도가 바뀌는 최대 가속 (px/s²). 연결 순간 진행 방향이 원의 회전 방향과 반대여도 '탁' 꺾이지 않고 몇 프레임에
## 걸쳐 둥글게 돌아 원 궤적에 들어간다. 원운동 자체(v²/R)는 대부분 이 안이라 궤적 모양에는 영향이 없다
const MAX_TURN_ACCEL := 9000.0
## 궤적이 막혔다고 보는 기준: 실제 이동이 의도한 이동의 이 비율 미만인 상태가 SAFETY_TIME 넘게 이어짐 (§6.5 안전 해제)
const BLOCKED_RATIO := 0.3
## 로프 길이보다 이만큼 이상 멀어진 상태가 SAFETY_TIME 넘게 이어져도 안전 해제
const SAFETY_STRETCH := 120.0
const SAFETY_TIME := 0.2
## 목표 각까지 남은 회전이 이 범위 안일 때만 보조한다 (범위 밖 = 이미 지남)
const ASSIST_MIN_REMAINING := deg_to_rad(3.0)
const ASSIST_MAX_REMAINING := deg_to_rad(250.0)
## 보조가 멈추는 지점의 진행 방향 최대 고도각 (도). 실제 고도각 = 이 값 × (1 - swing_target_forward_bias)
const TARGET_MAX_ELEVATION := 45.0

var player: PlayerController
var tuning: GrappleTuning
var is_attached := false
var anchor := Vector2.ZERO
var building: Building
## 진자 반지름 (px)
var rope_length := 0.0
var attached_time := 0.0
## 로프가 팽팽했던 시간 — 원 궤적은 연결 중 항상 팽팽하므로 attached_time 과 같다 (해제 도약 조건용)
var taut_time := 0.0
var is_taut := false
var reel_speed := 0.0
## 회전 방향: +1 = 시계(화면 기준 각도 증가), -1 = 반시계
var swing_dir := 1
## 원을 따라 도는 속력 (px/s, 부호 있음: + 는 swing_dir 방향)
var swing_speed := 0.0
## 이번 프레임 접선 보조 가속 (디버그 표시용)
var last_assist := Vector2.ZERO
## 지금까지 해제 도약을 준 횟수 (디버그·테스트용)
var boost_count := 0
## 디버그 표시용 마지막 입력 요청 / 결과
var last_request := "-"

## 지금 놓으면 넘겨줄 속도 = 원의 접선 속도 (도약 보너스 전, 읽기 전용으로 쓴다)
var release_velocity := Vector2.ZERO

var _target_reached := false
var _attach_velocity_y := 0.0
var _anchor_was_above := true
var _pre_move_pos := Vector2.ZERO
var _intended_move := 0.0
var _bumps_before := 0
var _blocked_time := 0.0
var _overstretch_time := 0.0
var _rope_line: Line2D


func setup(owner_player: PlayerController, grapple_tuning: GrappleTuning) -> void:
	player = owner_player
	tuning = grapple_tuning
	_rope_line = owner_player.get_node_or_null("RopeLine")


## 조준점으로 연결할 수 있는지 판정한다. {ok, point, normal, building, reason}
## 플레이어에서 조준 방향으로 최대 사거리까지 레이캐스트해 처음 맞은 표면을 본다 (§6.2 [MVP 제안]).
func evaluate(aim_point: Vector2) -> Dictionary:
	var result := {"ok": false, "point": Vector2.ZERO, "normal": Vector2.ZERO, "building": null, "reason": ""}
	var origin := player.global_position
	var direction := aim_point - origin
	if direction.length() < 1.0:
		result.reason = "aim too close"
		return result
	var query := PhysicsRayQueryParameters2D.create(origin, origin + direction.normalized() * tuning.grapple_max_range,
			RAY_MASK, [player.get_rid()])
	var hit := player.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		result.reason = "no surface in range"
		return result
	result.point = hit.position
	result.normal = hit.normal
	if hit.collider is Enemy:
		result.reason = "enemy (wire is building-only)"
		return result
	if not hit.collider is Building:
		result.reason = "not attachable"
		return result
	var target := hit.collider as Building
	if not target.get_attach_rect().grow(0.5).has_point(hit.position):
		result.reason = "outside attach band"
		return result
	if hit.position.y > origin.y - tuning.min_valid_attach_height:
		result.reason = "too low (anchor %.0fpx+ below)" % -tuning.min_valid_attach_height if tuning.min_valid_attach_height < 0.0 \
				else "too low (anchor must be above)"
		return result
	if rad_to_deg(hit.normal.angle_to(Vector2.UP)) > tuning.allowed_surface_angle:
		result.reason = "surface angle"
		return result
	result.ok = true
	result.building = target
	return result


## 좌클릭을 누른 순간 1회 연결을 시도한다 (§4 [MVP 제안]: 실패해도 누르고 있는 동안 자동 재발사하지 않음).
## 돌진 중·사망 중에는 연결하지 않는다 (§9.2 [MVP 제안]).
func request_attach(aim_point: Vector2) -> void:
	if is_attached:
		return
	if player.state != PlayerController.State.AIRBORNE:
		last_request = "attach ignored (%s)" % player.get_state_name()
		return
	var result := evaluate(aim_point)
	if not result.ok:
		last_request = "miss: %s" % result.reason
		return
	_attach(result.point, result.building)


## 좌클릭을 뗐을 때: 와이어 해제 + 조건부 해제 도약.
func request_release() -> void:
	if not is_attached:
		return
	_release(true, "released")


## 도약 없이 즉시 해제 (사망, 돌진 전환, 안전 해제).
func force_release(reason := "forced") -> void:
	if is_attached:
		_release(false, reason)


func _attach(point: Vector2, target: Building) -> void:
	is_attached = true
	anchor = point
	building = target
	var rel := player.global_position - anchor
	rope_length = maxf(rel.length(), tuning.min_rope_length)
	attached_time = 0.0
	taut_time = 0.0
	is_taut = true
	reel_speed = 0.0
	_blocked_time = 0.0
	_overstretch_time = 0.0
	_attach_velocity_y = player.velocity.y
	_anchor_was_above = anchor.y < player.global_position.y
	# 공중 구조물이면 반시계, 아래에서 솟은 건물이면 시계 방향 (건물 종류로 정함)
	swing_dir = -1 if target.aerial else 1
	var phi := atan2(rel.y, rel.x)
	_target_reached = not _in_assist_range(phi)
	if _target_reached:
		# 목표를 이미 지난 위치: 보조 없이, 지금 속도의 접선 성분 그대로 진자 운동
		swing_speed = player.velocity.dot(_tangent_at(phi))
	else:
		# 보조 구간: 지금 속력을 회전 방향으로 이어 받는다 (최소 스윙 속도 보장)
		swing_speed = clampf(player.velocity.length(), tuning.min_swing_speed, tuning.max_swing_speed)
	release_velocity = _tangent_at(phi) * swing_speed
	player.set_state(PlayerController.State.GRAPPLING)
	_update_rope_line()
	last_request = "attached (%.0f, %.0f) %s" % [anchor.x, anchor.y, "CW" if swing_dir > 0 else "CCW"]
	attached.emit(anchor, building)


func _release(allow_boost: bool, reason: String) -> void:
	# 도약 보너스는 연결점이 플레이어보다 위였을 때만 (아래 띠에 걸고 놓기를 반복해 계단처럼 오르지 못하게, §6.4)
	var boosted := allow_boost and _anchor_was_above and attached_time >= tuning.min_attach_duration 			and taut_time >= tuning.min_taut_duration
	is_attached = false
	building = null
	last_assist = Vector2.ZERO
	if _rope_line:
		_rope_line.visible = false
	if player.state == PlayerController.State.GRAPPLING:
		player.set_state(PlayerController.State.AIRBORNE)
		player.velocity = release_velocity  # 원의 접선 속도를 그대로 넘긴다 (관성 보존)
		if attached_time < tuning.min_attach_duration:
			# 짧게 걸었다 놓으면 올라가는 속도를 얻지 못한다 (§6.4 연타 무한 상승 방지): 연결 전보다 위로 빠르지 않게
			player.velocity.y = maxf(player.velocity.y, _attach_velocity_y)
	if boosted:
		player.velocity.y -= tuning.release_up_impulse
		boost_count += 1
	# 해제 후 위쪽 속도 상한 (§6.4): 진자가 위로 빠르게 솟는 중에 놓아도 이 값보다 빠르게 솟지 않는다
	player.velocity.y = maxf(player.velocity.y, -tuning.max_release_vertical_speed)
	player.carry_over_cap()  # 해제 직전 수평 관성 보존: 상한 초과분은 즉시 자르지 않고 점차 줄인다
	last_request = "%s%s" % [reason, " + boost" if boosted else (" (no boost)" if allow_boost else "")]
	_anchor_was_above = true
	released.emit(boosted)


## GRAPPLING 상태의 속도 계산 (이동 전): 원 위의 다음 지점으로 가는 속도. 이동은 플레이어가 move_and_slide 로 한다.
func apply_swing(delta: float) -> void:
	if not is_instance_valid(building):
		force_release("anchor lost")
		return
	attached_time += delta
	var pos := player.global_position
	var rel := pos - anchor
	if rel.length() < 0.001:
		rel = Vector2.DOWN
	var phi := atan2(rel.y, rel.x)  # 화면 좌표: 0 = 오른쪽, 90° = 아래, 180° = 왼쪽, 270° = 위
	var tangent := _tangent_at(phi)

	# 1) 원을 따라 도는 속력: 중력의 접선 성분 + (목표 각 전까지) 보조 가속과 최소 속도
	var accel := player.movement.gravity * tangent.y
	last_assist = Vector2.ZERO
	var assisting := false
	if not _target_reached:
		if _in_assist_range(phi):
			assisting = true
			accel += tuning.swing_assist_strength
			last_assist = tangent * tuning.swing_assist_strength
		else:
			_target_reached = true
	swing_speed += accel * delta
	if assisting:
		swing_speed = maxf(swing_speed, tuning.min_swing_speed)
	var speed_limit := minf(tuning.max_swing_speed, deg_to_rad(tuning.max_swing_angular_speed) * rope_length)
	swing_speed = clampf(swing_speed, -speed_limit, speed_limit)

	# 2) 로프 감기: 최대 스윙 반지름보다 길면 제한된 속도로 줄인다
	if tuning.rope_length_policy == GrappleTuning.RopeLengthPolicy.REEL_ASSIST and rope_length > tuning.max_swing_radius:
		reel_speed = minf(reel_speed + tuning.reel_assist_strength * delta, tuning.max_reel_rate)
		rope_length = maxf(rope_length - reel_speed * delta, maxf(tuning.max_swing_radius, tuning.min_rope_length))
	else:
		reel_speed = 0.0

	# 3) 원 위의 다음 지점으로 가는 속도 (궤적에서 밀려나 있으면 원으로 되돌아가는 성분 포함, 속도 상한 안에서)
	var next_phi := phi + swing_dir * swing_speed * delta / rope_length
	var target := anchor + Vector2(cos(next_phi), sin(next_phi)) * rope_length
	var desired := ((target - pos) / delta).limit_length(tuning.max_swing_speed + RETURN_SPEED_MARGIN)
	player.velocity = player.velocity.move_toward(desired, MAX_TURN_ACCEL * delta)
	release_velocity = _tangent_at(next_phi) * swing_speed
	_pre_move_pos = pos
	_intended_move = player.velocity.length() * delta
	_bumps_before = player.bump_count


## 이동 후: 충돌 감속, 궤적이 막히면 안전 해제, 로프 표시 갱신
func after_move(delta: float) -> void:
	if not is_attached:
		return
	taut_time += delta
	if player.bump_count > _bumps_before:
		# 새로 부딪히면 스윙 속도도 일반 충돌과 같은 비율로 줄인다 (§8)
		swing_speed *= player.movement.collision_speed_penalty
		release_velocity *= player.movement.collision_speed_penalty
	var moved := player.global_position.distance_to(_pre_move_pos)
	var blocked := _intended_move > 1.0 and moved < _intended_move * BLOCKED_RATIO
	_blocked_time = _blocked_time + delta if blocked else 0.0
	var stretched := player.global_position.distance_to(anchor) > rope_length + SAFETY_STRETCH
	_overstretch_time = _overstretch_time + delta if stretched else 0.0
	if _blocked_time > SAFETY_TIME or _overstretch_time > SAFETY_TIME:
		force_release("rope blocked")
		return
	_update_rope_line()


## 각 phi 에서 회전 방향(swing_dir)으로의 단위 접선
func _tangent_at(phi: float) -> Vector2:
	return Vector2(-sin(phi), cos(phi)) * swing_dir


## 보조가 멈추는 목표 각: 진행 방향이 '전방(+X) 위 elevation°'가 되는 지점.
## 시계 방향은 연결점 왼쪽 위(270° - e), 반시계 방향은 연결점 오른쪽 아래(90° - e).
func _target_angle() -> float:
	var elevation := TARGET_MAX_ELEVATION * (1.0 - tuning.swing_target_forward_bias)
	return deg_to_rad((270.0 if swing_dir > 0 else 90.0) - elevation)


func _in_assist_range(phi: float) -> bool:
	var remaining := fposmod((_target_angle() - phi) * swing_dir, TAU)
	return remaining > ASSIST_MIN_REMAINING and remaining <= ASSIST_MAX_REMAINING


func _update_rope_line() -> void:
	if _rope_line == null:
		return
	_rope_line.visible = is_attached
	_rope_line.points = PackedVector2Array([player.global_position, anchor])


## 디버그 표시용 한 줄 요약
func describe() -> String:
	if not is_attached:
		return last_request
	return "%s R %.0f  v %.0f  %s  held %.2fs  reel %.0f" % ["CW" if swing_dir > 0 else "CCW", rope_length,
			swing_speed, "free" if _target_reached else "assist", attached_time, reel_speed]
