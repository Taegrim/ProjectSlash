## Phase 3 — 돌진 베기: 자동 타기팅, 고속 돌진, 적 처치, 종료 후 속도 정책, 와이어→돌진 전환
## (기획서 §7, §9.2, §13.2-7·8·9·10·11, Phase 3 완료 기준, CLAUDE.md 지침 10 회귀).
## '실험실' 테스트는 메인 씬과 멀리 떨어진 좌표에 플레이어·건물·적만 따로 놓고 확인한다.
extends "res://tests/test_case.gd"

const MAIN_SCENE := preload("res://scenes/main.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const BUILDING_SCENE := preload("res://scenes/building.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const DEFAULT_MOVEMENT := preload("res://resources/default_movement.tres")
const FLOAT := {"gravity": 0.0, "auto_forward_speed": 0.0}


# --- §7.2, §13.2-7 전방에서 가장 가까운 적을 자동 선택 ---

func test_picks_nearest_enemy_ahead() -> void:
	var o := Vector2(200000, 0)
	var player := _lab_player(o, Vector2.ZERO, FLOAT)
	_lab_enemy(o + Vector2(-40, 0), "Behind")  # 가장 가깝지만 뒤쪽
	_lab_enemy(o + Vector2(300, 0), "Far")
	_lab_enemy(o + Vector2(200, -150), "SameAheadHigh")
	var expected := _lab_enemy(o + Vector2(200, 60), "SameAheadNear")  # 전방 거리 동률 → 실제 거리가 짧은 쪽
	await physics_frames(2)
	var found: Dictionary = player.dash.find_target()
	check(found.enemy == expected, "전방 거리가 가장 짧고, 동률이면 실제 거리가 짧은 적 (%s)" %
			(found.enemy.name if found.enemy else "없음"))


# --- §13.2-8 범위 밖/후방 적에게는 돌진하지 않는다 ---

func test_no_dash_to_enemies_behind_or_out_of_range() -> void:
	var o := Vector2(210000, 0)
	var player := _lab_player(o, Vector2.ZERO, FLOAT)
	_lab_enemy(o + Vector2(-150, 0), "Behind")
	_lab_enemy(o + Vector2(player.dash_tuning.dash_range + 60.0, 0), "OutOfRange")
	await physics_frames(2)
	player.dash.request_dash()
	check_eq(player.get_state_name(), "AIRBORNE", "후보가 없으면 상태를 바꾸지 않음")
	check(player.dash.last_request.begins_with("no target"), "이유 표시 (%s)" % player.dash.last_request)


func test_enemy_behind_building_is_not_targeted() -> void:
	# §7.2 [MVP 제안] 건물을 가로지르는 돌진은 허용하지 않는다
	var o := Vector2(220000, 0)
	var player := _lab_player(o, Vector2.ZERO, FLOAT)
	_lab_building(o + Vector2(100, -200), Vector2(60, 400), 80.0)
	_lab_enemy(o + Vector2(260, 0), "Hidden")
	await physics_frames(2)
	var found: Dictionary = player.dash.find_target()
	check(found.enemy == null and found.reason == "blocked by building", "건물 뒤 적은 후보에서 제외 (%s)" % found.reason)


# --- §9.2, §13.2-9 와이어 중 유효 적에게 돌진하면 와이어가 풀리고 돌진이 시작된다 ---

func test_dash_from_grapple_releases_wire_without_boost() -> void:
	var o := Vector2(230000, 300)
	var player := _lab_player(o, Vector2(320, 0), {})
	_lab_building(o + Vector2(200, -260), Vector2(240, 900), 120.0)
	await physics_frames(2)
	player.grapple.request_attach(o + Vector2(204, -250))
	check(player.grapple.is_attached, "준비: 와이어 연결 (%s)" % player.grapple.last_request)
	await physics_frames(20)
	var enemy := _lab_enemy(player.global_position + Vector2(160, 0), "Target")  # 적이 사거리 안에 들어온 상황
	await physics_frames(1)
	player.dash.request_dash()
	check(not player.grapple.is_attached, "와이어 해제")
	check_eq(player.get_state_name(), "DASHING", "돌진 시작")
	check_eq(player.grapple.boost_count, 0, "돌진 전환 해제에는 도약이 없음")
	check(player.dash.target == enemy, "타깃 고정")


# --- §7.3, §7.4, §13.2-10 적을 베고 적 뒤쪽에 도달, 돌진 중 재돌진·와이어 불가 ---

func test_dash_kills_enemy_and_ends_behind_it() -> void:
	var o := Vector2(240000, 0)
	var player := _lab_player(o, Vector2.ZERO, FLOAT)
	var enemy := _lab_enemy(o + Vector2(150, 0), "Target")
	var bystander := _lab_enemy(o + Vector2(215, 0), "Bystander")  # 타깃 뒤 돌진 경로 위: 관통만, 추가 타기팅 없음
	_lab_building(o + Vector2(100, -400), Vector2(200, 300), 300.0)  # 경로 위쪽 건물 (연결 시도용)
	await physics_frames(2)
	player.dash.request_dash()
	check_eq(player.get_state_name(), "DASHING", "돌진 시작 (%s)" % player.dash.last_request)
	check(player.dash.target == enemy, "전방에서 가장 가까운 적이 타깃")
	await physics_frames(1)
	player.dash.request_dash()
	check(player.dash.last_request.begins_with("dash ignored"), "돌진 중 재돌진 불가")
	player.grapple.request_attach(o + Vector2(104, -300))
	check(not player.grapple.is_attached, "돌진 중 와이어 연결 불가 (§9.2)")
	var frames := 0
	while player.state == PlayerController.State.DASHING and frames < 60:
		await physics_frames(1)
		frames += 1
	check_eq(player.get_state_name(), "AIRBORNE", "돌진이 끝나면 일반 체공")
	check(not enemy.alive, "타깃 처치")
	check(bystander.alive and player.dash.kill_count == 1, "경로 위 다른 적은 관통만 하고 베지 않음 (§7.2-6)")
	check(player.global_position.x > bystander.global_position.x, "다른 적에 막히지 않고 지나감")
	var expected_x := enemy.global_position.x + player.dash_tuning.dash_end_offset * 0.9
	check(player.global_position.x > expected_x, "적 뒤쪽까지 진행 (x %.0f > %.0f)" % [player.global_position.x, expected_x])
	check_eq(player.collision_mask, 6, "돌진이 끝나면 적과의 충돌을 다시 켬")


func test_dash_does_not_pass_through_building() -> void:
	# 적 바로 뒤에 건물이 있으면 끝점이 건물 안이 된다 → 건물에 막혀 그 자리에서 끝남 (관통·박힘 없음)
	var o := Vector2(250000, 0)
	var player := _lab_player(o, Vector2.ZERO, FLOAT)
	var enemy := _lab_enemy(o + Vector2(200, 0), "Target")
	var wall := _lab_building(o + Vector2(250, -300), Vector2(200, 600), 80.0)
	await physics_frames(2)
	player.dash.request_dash()
	var max_step := 0.0
	var inside := 0
	var previous := player.global_position
	for _i in 40:
		await physics_frames(1)
		max_step = maxf(max_step, player.global_position.distance_to(previous))
		previous = player.global_position
		if _inside(player.global_position, wall):
			inside += 1
	check(not enemy.alive, "적은 처치")
	check_eq(player.get_state_name(), "AIRBORNE", "건물에 막혀 돌진 종료")
	check(player.dash.last_request.begins_with("dash blocked"), "종료 이유 (%s)" % player.dash.last_request)
	check_eq(inside, 0, "건물 관통 없음")
	check(max_step <= player.dash_tuning.dash_speed / 60.0 + 2.0, "순간이동 없음 (최대 %.1fpx/프레임)" % max_step)
	check(player.bump_count >= 1, "건물 충돌은 감속으로 처리 (사망 아님)")


func test_dash_ends_at_max_duration() -> void:
	var o := Vector2(260000, 0)
	var player := _lab_player(o, Vector2.ZERO, FLOAT)
	player.dash.tuning = player.dash_tuning.duplicate()
	player.dash.tuning.max_dash_duration = 0.05
	var enemy := _lab_enemy(o + Vector2(400, 0), "Far")
	await physics_frames(2)
	player.dash.request_dash()
	await physics_frames(5)
	check_eq(player.get_state_name(), "AIRBORNE", "최대 시간이 지나면 종료")
	check(player.dash.last_request.begins_with("dash timeout"), "종료 이유 (%s)" % player.dash.last_request)
	check(enemy.alive, "닿지 못한 적은 살아 있음")


# --- §7.3, §13.2-11 돌진 종료 후 체공 속도 상한 (즉시 / 점진 감속) ---

func test_post_dash_speed_policies() -> void:
	for policy in [DashTuning.PostDashVelocityPolicy.IMMEDIATE_CAP, DashTuning.PostDashVelocityPolicy.GRADUAL_DECELERATION]:
		var o := Vector2(270000 + 2000 * policy, 0)
		var player := _lab_player(o, Vector2.ZERO, {"gravity": 0.0})
		player.dash.tuning = player.dash_tuning.duplicate()
		player.dash.tuning.post_dash_velocity_policy = policy
		_lab_enemy(o + Vector2(200, 0), "Target")
		await physics_frames(2)
		player.dash.request_dash()
		while player.state == PlayerController.State.DASHING:
			await physics_frames(1)
		var cap := player.movement.max_air_horizontal_speed
		var right_after := absf(player.velocity.x)
		if policy == DashTuning.PostDashVelocityPolicy.IMMEDIATE_CAP:
			check(right_after <= cap + 0.5, "즉시 상한(A안): 끝나자마자 체공 상한 이하 (vx %.0f)" % right_after)
		else:
			check(right_after > cap + 100.0, "점진 감속(B안): 끝나자마자 잘리지 않음 (vx %.0f)" % right_after)
		await physics_frames(60)
		check(absf(player.velocity.x) <= cap + 0.5, "1초 뒤에는 체공 상한 이하 (vx %.0f)" % absf(player.velocity.x))


# --- CLAUDE.md 지침 10 회귀: 스윙 해제 → 돌진 → 재연결 ---

func test_swing_release_then_dash_then_reattach() -> void:
	var o := Vector2(280000, 300)
	var player := _lab_player(o, Vector2(320, 0), {})
	var first := _lab_building(o + Vector2(200, -260), Vector2(240, 900), 120.0)
	await physics_frames(2)
	player.grapple.request_attach(o + Vector2(204, -250))
	await physics_frames(30)
	player.grapple.request_release()
	check_eq(player.get_state_name(), "AIRBORNE", "스윙 해제")
	first.queue_free()  # 스윙은 끝났다. 뒤의 재연결 조준선을 가리지 않게 치운다 (상태 흐름만 확인)
	var enemy := _lab_enemy(player.global_position + Vector2(220, 20), "Target")
	await physics_frames(1)
	player.dash.request_dash()
	check_eq(player.get_state_name(), "DASHING", "해제 직후 돌진 (%s)" % player.dash.last_request)
	while player.state == PlayerController.State.DASHING:
		await physics_frames(1)
	check(not enemy.alive, "적 처치")
	# 돌진이 끝난 위치 앞쪽에 다음 건물이 나타난 상황: 바로 다시 와이어를 걸 수 있어야 한다
	var next := _lab_building(player.global_position + Vector2(260, -120), Vector2(240, 900), 120.0)
	await physics_frames(1)
	player.grapple.request_attach(next.global_position + Vector2(4, 30))
	check(player.grapple.is_attached, "돌진 직후 다음 건물에 재연결 (%s)" % player.grapple.last_request)
	check_eq(player.get_state_name(), "GRAPPLING", "와이어 → 돌진 → 와이어 흐름이 이어짐")


# --- Phase 3 완료 기준: 코스에서 와이어 → 적 돌진 → 다음 구간 흐름이 끊기지 않는다 ---

func test_course_flow_wire_dash_dash_continues() -> void:
	var main := add_node(MAIN_SCENE.instantiate())
	var player: PlayerController = main.get_node("Player")
	var course: TestCourse = main.get_node("TestCourse")
	var buildings := course.get_buildings()
	var e: Building = main.get_node("TestCourse/BuildingE")
	var goal := e.position.x + e.size.x + 30.0
	var plan := {62: Vector2(626, 430), 112: null, 146: Vector2(1186, 200), 176: null}  # A·B 를 넘는 탐색 조합
	var violations := 0
	var max_step := player.dash_tuning.dash_speed / 60.0 + 2.0
	var previous := player.global_position
	var dashes := 0
	var crossed := false
	for f in 900:
		if plan.has(f):
			if plan[f] == null:
				player.grapple.request_release()
			else:
				player.grapple.request_attach(plan[f])
		if f > 176 and player.state == PlayerController.State.AIRBORNE and player.dash.find_target().enemy != null:
			player.dash.request_dash()  # 타깃이 잡히면 바로 우클릭
			dashes += 1
		await physics_frames(1)
		var position := player.global_position
		if position.distance_to(previous) > max_step or _inside_any(position, buildings):
			violations += 1
		previous = position
		if player.state == PlayerController.State.DEAD:
			break
		if position.x > goal:
			crossed = true
			break
	check_eq(player.dash.kill_count, 2, "적 C, D 를 돌진으로 처치 (돌진 %d 회)" % dashes)
	check(crossed, "E 너머까지 끊김 없이 진행 (끝 위치 %s, %s)" % [player.global_position.round(), player.get_state_name()])
	check_eq(violations, 0, "관통·순간이동 없음")


# --- 도우미 ---

func _lab_player(pos: Vector2, vel: Vector2, overrides: Dictionary) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.movement = DEFAULT_MOVEMENT.duplicate()
	for key in overrides:
		player.movement.set(key, overrides[key])
	player.position = pos
	player.velocity = vel
	add_node(player)
	return player


func _lab_building(pos: Vector2, size: Vector2, band: float) -> Building:
	var building: Building = BUILDING_SCENE.instantiate()
	building.position = pos
	building.size = size
	building.attach_band_depth = band
	add_node(building)
	return building


func _lab_enemy(pos: Vector2, label: String) -> Enemy:
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	enemy.name = label
	enemy.position = pos
	add_node(enemy)
	return enemy


func _inside(center: Vector2, building: Building) -> bool:
	var rect := building.get_rect()
	var closest := Vector2(clampf(center.x, rect.position.x, rect.end.x), clampf(center.y, rect.position.y, rect.end.y))
	return center.distance_to(closest) < PlayerController.RADIUS - 2.0


func _inside_any(center: Vector2, buildings: Array) -> bool:
	for building in buildings:
		if is_instance_valid(building) and _inside(center, building):
			return true
	return false
