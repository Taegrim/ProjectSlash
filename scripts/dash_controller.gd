## 돌진 베기 컨트롤러 — 적 자동 타기팅, 고속 돌진, 적 처치, 종료 후 속도 정책 (기획서 §7, §9.2).
##
## 지켜야 할 확정 규칙 (기획서 §7, §15):
## - 적에게만 쓴다. 조준 없이 우클릭으로 범위 안의 적을 자동으로 고른다.
## - 타깃 우선순위 (§7.2): 살아 있음 → 전방(+X) → 사거리 안 → 전방에서 가장 가까운 적(전방 거리, 같으면 실제 거리).
##   후보가 없으면 돌진하지 않고 상태도 바꾸지 않는다 (§9.2 [MVP 제안]).
## - 돌진은 공격이자 이동 수단이며 적을 관통해 전방으로 진행한다. 돌진 중 추가 타기팅·재돌진은 없다.
## - 와이어 중이면 와이어를 도약 없이 해제하고 돌진으로 전환한다 (§6.5, §9.2).
## - 돌진 속도는 일반 체공 최고 속도와 별개이며, 돌진 뒤 상한 초과 속도가 영구 유지되지 않는다 (PostDashVelocityPolicy).
## - 건물을 가로지르는 돌진은 허용하지 않는다 (§7.2 [MVP 제안]): 건물에 막힌 적은 후보에서 뺀다.
##
## 이동 방식: 돌진 중에도 속도만 정하고 실제 이동은 플레이어의 move_and_slide(건물 충돌 검사)가 한다 (§7.3 [MVP 제안]).
## 적을 관통해야 하므로 돌진 중에만 플레이어 충돌 마스크에서 적 레이어를 뺀다. 건물에 부딪히면 그 자리에서 끝낸다.
class_name DashController
extends Node

signal dash_started(target: Enemy)
signal dash_hit(target: Enemy)
signal dash_ended(reason: String)

const ENEMY_GROUP := "enemies"
const BUILDING_MASK := 2
const ENEMY_LAYER_BIT := 4
## 끝점에 이만큼 가까우면 도착으로 본다 (px)
const ARRIVE_EPSILON := 2.0
## 경로 검사용 원 반지름 = 플레이어 반지름 − 이 값 (지붕에 닿아 미끄러지는 중에도 돌진할 수 있게)
const PROBE_MARGIN := 2.0

var player: PlayerController
var tuning: DashTuning
## 지금 돌진 중인 대상 (돌진 중이 아니면 null)
var target: Enemy
var direction := Vector2.RIGHT
var end_point := Vector2.ZERO
var elapsed := 0.0
var hit := false
## 처치한 적 수 (디버그·테스트용)
var kill_count := 0
## 디버그 표시용 마지막 입력 요청 / 결과
var last_request := "-"

var _active := false
var _saved_mask := 0
var _previous_position := Vector2.ZERO
var _probe_shape := CircleShape2D.new()


func setup(owner_player: PlayerController, dash_tuning: DashTuning) -> void:
	player = owner_player
	tuning = dash_tuning


## 지금 우클릭하면 돌진할 적을 고른다. {enemy, reason} — 후보가 없으면 enemy 는 null
func find_target() -> Dictionary:
	var origin := player.global_position
	var best: Enemy = null
	var best_forward := INF
	var best_distance := INF
	var reason := "no enemy ahead in range"
	for node in player.get_tree().get_nodes_in_group(ENEMY_GROUP):
		var enemy := node as Enemy
		if enemy == null or not enemy.alive:
			continue
		var offset := enemy.global_position - origin
		if offset.x <= 0.0 or offset.length() > tuning.dash_range:
			continue  # 전방(+X)·사거리 안만
		var distance := offset.length()
		if offset.x > best_forward or (offset.x == best_forward and distance >= best_distance):
			continue
		if not _path_clear(origin, enemy):
			reason = "blocked by building"
			continue
		best = enemy
		best_forward = offset.x
		best_distance = distance
	return {"enemy": best, "reason": "" if best else reason}


## 우클릭: 유효 타깃이 있으면 돌진, 없으면 아무것도 하지 않는다 (와이어 상태 유지).
func request_dash() -> void:
	if player.state == PlayerController.State.DEAD or player.state == PlayerController.State.DASHING:
		last_request = "dash ignored (%s)" % player.get_state_name()
		return
	var found := find_target()
	if found.enemy == null:
		last_request = "no target: %s" % found.reason
		return
	if player.state == PlayerController.State.GRAPPLING:
		player.grapple.force_release("dash")  # 돌진 전환: 도약 없이 해제 (§6.5 [MVP 제안])
	_start(found.enemy)


## 돌진을 결과 처리 없이 멈춘다 (사망 등). 충돌 마스크만 되돌린다.
func cancel(reason := "cancel") -> void:
	if not _active:
		return
	_restore_mask()
	target = null
	last_request = "dash %s" % reason


## DASHING 상태의 속도 계산 (이동 전): 끝점(적 뒤쪽)을 향해 돌진 속도로, 끝점을 지나치지 않게.
func apply_dash(delta: float) -> void:
	elapsed += delta
	_previous_position = player.global_position
	var remaining := end_point - player.global_position
	var step := tuning.dash_speed * delta
	player.velocity = remaining / delta if remaining.length() <= step else remaining.normalized() * tuning.dash_speed


## 이동 후: 적 처치, 종료 조건 (끝점 도착 / 최대 시간 / 건물 충돌)
func after_move(_delta: float) -> void:
	if not _active:
		return
	var position := player.global_position
	if not hit and is_instance_valid(target) and target.alive:
		var closest := Geometry2D.get_closest_point_to_segment(target.global_position, _previous_position, position)
		if closest.distance_to(target.global_position) <= target.radius + PlayerController.RADIUS:
			hit = true
			kill_count += 1
			target.kill()  # §7.4 [MVP 제안] 타깃에 도달하면 즉시 제거
			dash_hit.emit(target)
	if player.get_slide_collision_count() > 0:
		_end("blocked by building", player.velocity)  # 이미 미끄러짐·충돌 감속이 반영된 속도
	elif position.distance_to(end_point) <= ARRIVE_EPSILON:
		_end("arrived", direction * tuning.dash_speed)
	elif elapsed >= tuning.max_dash_duration:
		_end("timeout", direction * tuning.dash_speed)


## 디버그 표시용 한 줄 요약
func describe() -> String:
	if _active:
		return "-> %s  %.2fs%s  kills %d" % [target.name if is_instance_valid(target) else "?", elapsed,
				"  HIT" if hit else "", kill_count]
	return "%s  kills %d" % [last_request, kill_count]


func _start(enemy: Enemy) -> void:
	_active = true
	target = enemy
	direction = (enemy.global_position - player.global_position).normalized()
	end_point = enemy.global_position + direction * tuning.dash_end_offset  # §7.1 [MVP 제안] 적 뒤쪽에서 종료
	elapsed = 0.0
	hit = false
	_saved_mask = player.collision_mask
	player.collision_mask = _saved_mask & ~ENEMY_LAYER_BIT  # 적은 관통, 건물은 그대로 막힌다
	player.set_state(PlayerController.State.DASHING)
	last_request = "dash -> %s" % enemy.name
	dash_started.emit(enemy)


func _end(reason: String, exit_velocity: Vector2) -> void:
	_restore_mask()
	target = null
	player.velocity = exit_velocity
	player.velocity.y = maxf(player.velocity.y, -tuning.max_exit_up_speed)  # 위로 솟는 기세 제한
	if player.state == PlayerController.State.DASHING:
		player.set_state(PlayerController.State.AIRBORNE)
	# 돌진 종료 후 속도 정책 (§7.3): A안 즉시 상한 / B안 짧은 시간에 걸쳐 감속
	if tuning.post_dash_velocity_policy == DashTuning.PostDashVelocityPolicy.IMMEDIATE_CAP:
		player.apply_speed_cap_now()
	else:
		player.carry_over_cap(tuning.post_dash_deceleration)
	last_request = "dash %s%s" % [reason, " (hit)" if hit else ""]
	dash_ended.emit(reason)


func _restore_mask() -> void:
	if _active:
		player.collision_mask = _saved_mask
	_active = false


## 플레이어에서 적까지 건물에 막히지 않는지 (플레이어 크기의 원을 밀어 본다)
func _path_clear(origin: Vector2, enemy: Enemy) -> bool:
	var to_enemy := enemy.global_position - origin
	var reach := maxf(to_enemy.length() - enemy.radius, 0.0)
	if reach < 1.0:
		return true
	_probe_shape.radius = PlayerController.RADIUS - PROBE_MARGIN
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _probe_shape
	params.transform = Transform2D(0.0, origin)
	params.motion = to_enemy.normalized() * reach
	params.collision_mask = BUILDING_MASK
	params.exclude = [player.get_rid()]
	var fractions := player.get_world_2d().direct_space_state.cast_motion(params)
	return fractions.is_empty() or fractions[0] >= 1.0
