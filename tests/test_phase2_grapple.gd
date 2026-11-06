## Phase 2 — 와이어: 연결 대상, 보정형 스윙, 해제 도약, 비관통 (기획서 §6, §13.2-2·3·4·5·6, Phase 2 완료 기준).
## '실험실' 테스트는 메인 씬과 멀리 떨어진 좌표에 플레이어·건물·적만 따로 놓고 확인한다.
extends "res://tests/test_case.gd"

const MAIN_SCENE := preload("res://scenes/main.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const BUILDING_SCENE := preload("res://scenes/building.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const DEFAULT_MOVEMENT := preload("res://resources/default_movement.tres")
## 한 프레임 이동 거리 상한 (순간이동 판정): 스윙 최고 속도 1000px/s ÷ 60 ≈ 16.7px 에 여유
const MAX_STEP := 20.0


# --- §6.2, §13.2-2 와이어는 건물 유효 표면에만 걸리고 적에는 걸리지 않는다 ---

func test_wire_attaches_only_inside_building_band() -> void:
	var building := _lab_building(Vector2(50000, 0), Vector2(200, 600), 80.0)
	var player := _lab_player(Vector2(49800, 300), Vector2.ZERO, {"gravity": 0.0, "auto_forward_speed": 0.0})
	await physics_frames(2)
	var high: Dictionary = player.grapple.evaluate(Vector2(50005, 20))
	check(high.ok, "연결 띠를 조준하면 연결 가능 (%s)" % high.reason)
	check(building.get_attach_rect().grow(0.5).has_point(high.point), "연결점은 띠 안의 레이캐스트 적중 지점")
	var low: Dictionary = player.grapple.evaluate(Vector2(50005, 300))
	check(not low.ok and low.reason == "outside attach band", "띠 아래 벽면은 연결 불가 (%s)" % low.reason)
	var far := _lab_player(Vector2(49000, 300), Vector2.ZERO, {"gravity": 0.0, "auto_forward_speed": 0.0})
	await physics_frames(1)
	var out_of_range: Dictionary = far.grapple.evaluate(Vector2(50005, 20))
	check(not out_of_range.ok and out_of_range.reason == "no surface in range", "사거리 밖은 연결 불가")


func test_wire_does_not_attach_to_enemy() -> void:
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	enemy.position = Vector2(51000, 200)
	add_node(enemy)
	_lab_building(Vector2(51200, 0), Vector2(200, 600), 300.0)  # 적 뒤에 건물이 있어도
	var player := _lab_player(Vector2(50800, 400), Vector2.ZERO, {"gravity": 0.0, "auto_forward_speed": 0.0})
	await physics_frames(2)
	var result: Dictionary = player.grapple.evaluate(enemy.global_position)
	check(not result.ok and String(result.reason).begins_with("enemy"), "적을 조준하면 연결 불가 (%s)" % result.reason)
	player.grapple.request_attach(enemy.global_position)
	check(not player.grapple.is_attached, "요청해도 연결되지 않음")


func test_anchor_can_be_level_or_slightly_below_player() -> void:
	# 수정 리뷰 16번: 플레이어가 띠보다 살짝 위(연결점이 80px 이내로 아래)여도 걸린다. 훨씬 위에서 내려다보고는 안 걸린다
	var building := _lab_building(Vector2(52000, 0), Vector2(300, 600), 80.0)
	var beside := _lab_player(Vector2(51800, 30), Vector2.ZERO, {"gravity": 0.0, "auto_forward_speed": 0.0})
	var slightly_above := _lab_player(Vector2(52150, -60), Vector2.ZERO, {"gravity": 0.0, "auto_forward_speed": 0.0})
	var far_above := _lab_player(Vector2(52150, -140), Vector2.ZERO, {"gravity": 0.0, "auto_forward_speed": 0.0})
	await physics_frames(2)
	var level: Dictionary = beside.grapple.evaluate(Vector2(52005, 40))
	check(level.ok, "띠와 같은 높이에서 연결 가능 (%s)" % level.reason)
	var near: Dictionary = slightly_above.grapple.evaluate(Vector2(52150, 10))
	check(near.ok and building.get_attach_rect().grow(0.5).has_point(near.point), "60px 아래 띠(지붕)도 연결 가능 (%s)" % near.reason)
	var far: Dictionary = far_above.grapple.evaluate(Vector2(52150, 10))
	check(not far.ok and String(far.reason).begins_with("too low"), "140px 아래는 연결 불가 (%s)" % far.reason)


func test_failed_attach_does_not_retry_while_held() -> void:
	# §4 [MVP 제안] 누른 순간 1회만 시도, 실패 상태로 누르고 있어도 자동 재발사하지 않음
	_lab_building(Vector2(53000, 0), Vector2(200, 600), 80.0)
	var player := _lab_player(Vector2(52800, 300), Vector2.ZERO, {"gravity": 0.0, "auto_forward_speed": 0.0})
	await physics_frames(2)
	player.grapple.request_attach(Vector2(53005, 400))  # 띠 아래 → 실패
	check(not player.grapple.is_attached, "잘못 조준하면 실패")
	player.debug_aim_override = Vector2(53005, 20)  # 누른 채 유효한 곳으로 조준을 옮겨도
	await physics_frames(20)
	check(not player.grapple.is_attached, "새로 누르기 전에는 다시 시도하지 않음")


# --- §6.3, §13.2-3 방향키 없이 전방 위쪽으로 진행하도록 자동 보정 ---

func test_holding_wire_assists_up_and_over() -> void:
	var main := add_node(MAIN_SCENE.instantiate())
	var player: PlayerController = main.get_node("Player")
	var a: Building = main.get_node("TestCourse/BuildingA")
	await physics_frames(62)
	player.grapple.request_attach(a.global_position + Vector2(6, 10))
	check(player.grapple.is_attached, "A 연결 (%s)" % player.grapple.last_request)
	var attach_y := player.global_position.y
	var assisted_frames := 0
	var lowest := INF
	for _i in 50:
		await physics_frames(1)
		if player.grapple.last_assist != Vector2.ZERO:
			assisted_frames += 1
		lowest = minf(lowest, player.global_position.y)
	check(assisted_frames > 10, "누르고 있는 동안 보조 가속이 걸림 (%d 프레임)" % assisted_frames)
	check(lowest < attach_y - 60.0, "입력 없이도 위로 끌어올려짐 (%.0f → %.0f)" % [attach_y, lowest])


# --- Phase 2 리뷰 10번: 진자 궤적 — 솟은 건물은 시계 방향, 공중 구조물은 반시계 방향 ---

func test_rising_building_swings_clockwise_over_the_anchor() -> void:
	var building := _lab_building(Vector2(130000, 0), Vector2(240, 900), 170.0)
	var player := _lab_player(Vector2(129850, 260), Vector2(320, 100), {})
	await physics_frames(2)
	player.grapple.request_attach(Vector2(130004, 100))
	check(player.grapple.is_attached, "연결 (%s)" % player.grapple.last_request)
	check_eq(player.grapple.swing_dir, 1, "아래에서 솟은 건물은 시계 방향")
	var arc := await _watch_arc(player, [building], 90)
	check(arc.early_step.x < 0.0 and arc.early_step.y < 0.0, "방향을 둥글게 바꾼 뒤 왼쪽 위로 (벽에서 떨어져 원을 그림) %s" % arc.early_step)
	check(arc.max_radius_error < 3.0, "부딪히기 전까지 연결점 둘레의 원을 따라감 (반지름 오차 %.1fpx)" % arc.max_radius_error)
	check(arc.passed_over, "연결점 위를 지나 지붕 쪽으로 넘어감")
	check(arc.inside == 0 and arc.max_step <= MAX_STEP, "관통·순간이동 없음 (최대 %.1fpx/프레임)" % arc.max_step)


func test_aerial_structure_swings_counterclockwise_under_the_anchor() -> void:
	var platform := _lab_building(Vector2(140000, 0), Vector2(240, 40), 40.0)  # 공중 구조물: 밑면에 건다
	platform.aerial = true
	var player := _lab_player(Vector2(139900, 200), Vector2(320, 0), {})
	await physics_frames(2)
	player.grapple.request_attach(Vector2(140100, 40))
	check(player.grapple.is_attached, "밑면 연결 (%s)" % player.grapple.last_request)
	check_eq(player.grapple.swing_dir, -1, "공중 구조물은 반시계 방향")
	var arc := await _watch_arc(player, [platform], 90)
	check(arc.early_step.x > 0.0 and arc.early_step.y > 0.0, "처음에는 오른쪽 아래로 %s" % arc.early_step)
	check(arc.max_radius_error < 3.0, "부딪히기 전까지 연결점 둘레의 원을 따라감 (반지름 오차 %.1fpx)" % arc.max_radius_error)
	check(arc.passed_under, "연결점 아래를 지나감")
	check(arc.rose_on_right, "연결점 오른쪽에서 다시 올라감")
	check(arc.inside == 0 and arc.max_step <= MAX_STEP, "관통·순간이동 없음 (최대 %.1fpx/프레임)" % arc.max_step)


func test_aerial_direction_does_not_depend_on_player_height() -> void:
	# 수정 리뷰 10번: 떨어지기 직전(플레이어가 밑면보다 위)에 걸어도 공중 구조물이면 반시계 방향
	var block := _lab_building(Vector2(150000, 0), Vector2(200, 160), 160.0)
	block.aerial = true
	var player := _lab_player(Vector2(149880, 60), Vector2(320, 0), {})
	await physics_frames(2)
	check(player.global_position.y < block.get_rect().end.y, "준비: 플레이어가 밑면보다 위")
	player.grapple.request_attach(Vector2(150004, 20))
	check(player.grapple.is_attached, "연결 (%s)" % player.grapple.last_request)
	check_eq(player.grapple.swing_dir, -1, "공중 구조물은 플레이어 높이와 관계없이 반시계 방향")
	var arc := await _watch_arc(player, [block], 30)
	check(arc.early_step.y > 0.0, "아래로 내려가며 돎 %s" % arc.early_step)
	check(arc.inside == 0 and arc.max_step <= MAX_STEP, "관통·순간이동 없음")


# --- §6.3-5, §13.2-4 낮은/높은 연결 위치에서도 관통·순간이동 없음 ---

func test_no_penetration_or_teleport_for_high_and_low_anchor() -> void:
	for anchor_y in [10.0, 160.0]:  # 띠(0~170)의 위쪽 / 아래쪽
		var building := _lab_building(Vector2(60000, 0), Vector2(240, 900), 170.0)
		var player := _lab_player(Vector2(59800, 400), Vector2(320, 0), {})
		await physics_frames(2)
		player.grapple.request_attach(Vector2(60004, anchor_y))
		check(player.grapple.is_attached, "연결 y=%.0f (%s)" % [anchor_y, player.grapple.last_request])
		var report := await _watch_motion(player, [building], 120)
		player.grapple.request_release()
		var after := await _watch_motion(player, [building], 60)
		check(report.inside == 0 and after.inside == 0, "연결 y=%.0f: 건물 관통 없음" % anchor_y)
		check(report.max_step <= MAX_STEP and after.max_step <= MAX_STEP,
				"연결 y=%.0f: 순간이동 없음 (최대 %.1fpx/프레임)" % [anchor_y, maxf(report.max_step, after.max_step)])
		player.queue_free()
		building.queue_free()
		await physics_frames(1)


# --- §6.4, §13.2-5 짧은 연결·해제 반복만으로 무한 상승하지 않음 ---

func test_rapid_attach_release_gives_no_boost_and_no_climb() -> void:
	# 짧게 걸었다 놓으면 올라가는 속도를 얻지 못하고(연결 전보다 위로 빠르지 않음), 연결점은 플레이어보다 40px 이상
	# 위여야 하므로 연타로는 높이가 쌓이지 않는다. 60번 연타를 20번씩 나눠, 중간과 마지막 구간의 최고 높이가 같은지
	# (계속 올라가지 않음) 보고, 최고 높이가 '띠 위끝 + 한 번 연결하는 동안 최고 속도로 움직인 거리'를 넘지 않는지 본다.
	var building := _lab_building(Vector2(70000, 0), Vector2(240, 900), 170.0)
	var player := _lab_player(Vector2(69800, 300), Vector2(320, 0), {})
	await physics_frames(2)
	var highest := [INF, INF, INF]
	for i in 60:
		player.grapple.request_attach(Vector2(70004, 60))
		await physics_frames(6)  # 0.1초 — 최소 연결 시간(0.25초)보다 짧다
		player.grapple.request_release()
		await physics_frames(3)
		highest[i / 20] = minf(highest[i / 20], player.global_position.y)
	check_eq(player.grapple.boost_count, 0, "짧은 연결 반복에는 해제 도약이 없음")
	check(highest[2] > highest[1] - 10.0,
			"연타를 계속해도 더 높이 오르지 않음 (21~40번 최고 y %.0f, 41~60번 %.0f)" % [highest[1], highest[2]])
	var bound := building.global_position.y - player.grapple_tuning.max_swing_speed * 0.1
	var top: float = highest.min()
	check(top > bound, "최고 높이에 상한이 있음 (최고 y %.0f, 한계 %.0f)" % [top, bound])


func test_repeated_valid_releases_stay_bounded() -> void:
	# 조건을 채운 해제를 반복해도 상승 높이에 상한이 있다 (도약 상한 + 연결점은 플레이어보다 위여야 함)
	var building := _lab_building(Vector2(80000, 0), Vector2(240, 900), 170.0)
	var player := _lab_player(Vector2(79800, 300), Vector2(320, 0), {})
	await physics_frames(2)
	var highest := player.global_position.y
	for _i in 20:
		player.grapple.request_attach(Vector2(80004, 60))
		await physics_frames(24)
		player.grapple.request_release()
		await physics_frames(12)
		highest = minf(highest, player.global_position.y)
		if player.global_position.y > 2000.0:
			break
	# 상한 = 띠 위끝 − (최대 스윙 반지름 + 해제 상향 속도 상한으로 솟는 높이) − 여유 50. 연결점이 아래면 도약이 없어 쌓이지 않는다
	var tuning := player.grapple_tuning
	var rise := tuning.max_release_vertical_speed ** 2 / (2.0 * player.movement.gravity)
	var ceiling := building.global_position.y - (tuning.max_swing_radius + rise + 50.0)
	check(highest > ceiling, "반복 해제로도 상한을 넘지 못함 (최고 y %.0f, 상한 %.0f)" % [highest, ceiling])


# --- §6.4, §13.2-6 해제 시 수평 관성 유지 + 조건부 상향 도약 ---

func test_release_keeps_horizontal_inertia_and_boosts_up() -> void:
	_lab_building(Vector2(90000, 0), Vector2(240, 900), 170.0)
	var player := _lab_player(Vector2(89800, 300), Vector2(0, 300), {})  # 아래로 떨어지며 로프가 팽팽해지는 상황
	await physics_frames(2)
	player.grapple.request_attach(Vector2(90004, 60))
	check(player.grapple.is_attached, "연결 (%s)" % player.grapple.last_request)
	for _i in 120:
		await physics_frames(1)
		if player.grapple.attached_time >= player.grapple_tuning.min_attach_duration \
				and player.grapple.taut_time >= player.grapple_tuning.min_taut_duration:
			break
	check(player.grapple.attached_time >= player.grapple_tuning.min_attach_duration, "최소 연결 시간 충족")
	check(player.grapple.taut_time >= player.grapple_tuning.min_taut_duration, "로프 팽팽 시간 충족")
	var before := player.grapple.release_velocity
	var rope := player.global_position - player.grapple.anchor
	check(absf(before.normalized().dot(rope.normalized())) < 0.05, "놓을 때 속도는 원의 접선 방향 (진자 궤적)")
	player.grapple.request_release()
	check_eq(player.grapple.boost_count, 1, "조건을 채운 해제는 도약")
	check_near(player.velocity.x, before.x, 0.01, "해제 순간 수평 속도는 그대로")
	var tuning := player.grapple_tuning
	var expected_y := maxf(before.y - tuning.release_up_impulse, -tuning.max_release_vertical_speed)
	check_near(player.velocity.y, expected_y, 0.01, "위쪽으로 도약 (상향 속도 상한 %.0f 안에서)" % tuning.max_release_vertical_speed)
	check(player.velocity.y < before.y, "도약은 위쪽 방향")


func test_fast_release_is_not_clamped_instantly_but_decays_to_cap() -> void:
	# §6.4 [확정] 관성 보존 vs §5.2 [확정] 상한 초과 속도가 영구 유지되지 않음
	var player := _lab_player(Vector2(100000, -5000), Vector2.ZERO, {"gravity": 0.0})
	_lab_building(Vector2(100200, -5300), Vector2(240, 900), 170.0)
	await physics_frames(2)
	player.grapple.request_attach(Vector2(100204, -5250))
	check(player.grapple.is_attached, "연결 (%s)" % player.grapple.last_request)
	player.grapple.release_velocity = Vector2(900, 0)  # 테스트 준비: 스윙으로 체공 상한(520)보다 빨라진 상황
	player.grapple.force_release("test")
	await physics_frames(2)
	check(player.velocity.x > player.movement.max_air_horizontal_speed + 100.0,
			"해제 직후에는 상한으로 바로 잘리지 않음 (vx %.0f)" % player.velocity.x)
	await physics_frames(120)
	check(player.velocity.x <= player.movement.max_air_horizontal_speed + 0.5,
			"2초 뒤에는 체공 상한 이하로 돌아옴 (vx %.0f)" % player.velocity.x)


func test_short_hold_gives_no_boost() -> void:
	_lab_building(Vector2(110000, 0), Vector2(240, 900), 170.0)
	var player := _lab_player(Vector2(109800, 300), Vector2(320, 0), {})
	await physics_frames(2)
	var vy_at_attach := player.velocity.y
	player.grapple.request_attach(Vector2(110004, 60))
	await physics_frames(6)
	var arc_velocity := player.grapple.release_velocity
	check(arc_velocity.y < vy_at_attach, "준비: 0.1초 사이 원을 따라 위로 움직이는 중 (vy %.0f)" % arc_velocity.y)
	player.grapple.request_release()
	check_eq(player.grapple.boost_count, 0, "0.1초 연결 후 해제는 도약 없음")
	check_near(player.velocity.x, arc_velocity.x, 0.01, "수평 속도는 원의 접선 속도 그대로")
	check_near(player.velocity.y, maxf(arc_velocity.y, vy_at_attach), 0.01,
			"짧게 걸면 올라가는 속도를 얻지 못함 (연결 전 세로 속도 %.0f)" % vy_at_attach)


func test_death_releases_wire() -> void:
	_lab_building(Vector2(120000, 0), Vector2(240, 900), 170.0)
	var player := _lab_player(Vector2(119800, 300), Vector2(320, 0), {})
	await physics_frames(2)
	player.grapple.request_attach(Vector2(120004, 60))
	check(player.grapple.is_attached, "연결")
	player.die("hazard")
	check(not player.grapple.is_attached, "사망하면 와이어 즉시 해제 (§6.5)")
	check(not (player.get_node("RopeLine") as Line2D).visible, "로프 표시도 사라짐")


# --- Phase 2 완료 기준: 두 높이의 건물(A, B)을 스윙과 해제로 넘을 수 있다 (§10.3 통과 경로 존재) ---

func test_building_a_can_be_crossed_with_swing_and_release() -> void:
	var result := await _find_a_plan()
	check(result.found > 0, "A 를 넘는 연결·해제 조합이 있음 (%d / %d)" % [result.found, result.tried])
	check(result.violations == 0, "탐색한 모든 경로에서 관통·순간이동 없음 (위반 %d)" % result.violations)


func test_buildings_a_then_b_can_be_crossed() -> void:
	# A 를 넘는 조합마다 B 격자를 시도해, A → B 를 이어서 넘는 경로가 하나라도 있는지 본다.
	# (A 에서 너무 일찍 놓아 높이 솟으면 B 의 띠를 지나쳐 버리므로, A 조합에 따라 B 경로가 없을 수 있다)
	var a_result := await _find_a_plan()
	check(a_result.found > 0, "A 통과 조합")
	if a_result.found == 0:
		return
	var probe: Node = MAIN_SCENE.instantiate()
	var b: Building = probe.get_node("TestCourse/BuildingB")
	var aim_b := b.position + Vector2(6, b.attach_band_top + 20)  # 띠 위쪽 (B 의 띠는 지붕보다 아래에서 시작)
	var goal_b := b.position.x + b.size.x + 30.0
	probe.free()
	var found := 0
	var tried := 0
	var violations := 0
	for plan_a in a_result.plans:
		var release_a: int = plan_a[1][0]
		for offset in range(10, 60, 8):
			for hold in [30, 50, 70]:
				var plan: Array = plan_a + [[release_a + offset, "attach", aim_b], [release_a + offset + hold, "release"]]
				var run := await _run_plan(plan, goal_b, 600)
				tried += 1
				violations += run.violations
				if run.ok:
					found += 1
		if found > 0:
			break
	check(found > 0, "A 다음 B 까지 넘는 조합이 있음 (%d / %d)" % [found, tried])
	check(violations == 0, "탐색한 모든 경로에서 관통·순간이동 없음 (위반 %d)" % violations)


# --- 도우미 ---

## A 를 넘는 조합을 찾는다: 연결 프레임 × 유지 프레임 격자 (plans = 넘은 조합 전부, 찾은 순서)
func _find_a_plan() -> Dictionary:
	var probe: Node = MAIN_SCENE.instantiate()
	var a: Building = probe.get_node("TestCourse/BuildingA")
	var aim_a := a.position + Vector2(6, 10)
	var goal_a := a.position.x + a.size.x + 30.0
	probe.free()
	var result := {"found": 0, "tried": 0, "violations": 0, "plans": []}
	for attach_frame in [53, 59, 65]:
		for hold in [30, 50, 70]:
			var plan := [[attach_frame, "attach", aim_a], [attach_frame + hold, "release"]]
			var run := await _run_plan(plan, goal_a, 360)
			result.tried += 1
			result.violations += run.violations
			if run.violations > 0:
				print("    위반 att%d hold%d: %s" % [attach_frame, hold, run.first_violation])
			if run.ok:
				result.found += 1
				result.plans.append(plan)
	return result


## 메인 씬을 새로 만들어 계획대로 연결·해제하고, goal_x 를 넘으면 성공. 매 프레임 관통·순간이동을 센다.
func _run_plan(plan: Array, goal_x: float, max_frames: int) -> Dictionary:
	var main: Node = MAIN_SCENE.instantiate()
	add_node(main)
	var player: PlayerController = main.get_node("Player")
	var buildings: Array[Building] = (main.get_node("TestCourse") as TestCourse).get_buildings()
	var out := {"ok": false, "violations": 0, "first_violation": ""}
	var previous := player.global_position
	for frame in max_frames:
		for step in plan:
			if step[0] == frame:
				if step[1] == "attach":
					player.grapple.request_attach(step[2])
				else:
					player.grapple.request_release()
		await physics_frames(1)
		var position := player.global_position
		var step_length := position.distance_to(previous)
		var inside := _inside_any(position, buildings)
		if step_length > MAX_STEP or inside:
			out.violations += 1
			if String(out.first_violation).is_empty():
				out.first_violation = "f%d %s pos(%.1f, %.1f) step %.1f inside %s v(%.0f, %.0f) %s" % [frame,
						player.get_state_name(), position.x, position.y, step_length, inside, player.velocity.x,
						player.velocity.y, player.grapple.last_request]
		previous = position
		if player.state == PlayerController.State.DEAD:
			break
		if position.x > goal_x:
			out.ok = true
			break
	main.queue_free()
	await physics_frames(1)
	return out


## 플레이어를 n 프레임 지켜보며 관통 횟수와 최대 프레임 이동 거리를 잰다
func _watch_motion(player: PlayerController, buildings: Array, frames: int) -> Dictionary:
	var report := {"inside": 0, "max_step": 0.0}
	var previous := player.global_position
	for _i in frames:
		await physics_frames(1)
		var position := player.global_position
		report.max_step = maxf(report.max_step, position.distance_to(previous))
		if _inside_any(position, buildings):
			report.inside += 1
		previous = position
	return report


## 와이어를 건 채 n 프레임 지켜보며 궤적 모양을 잰다. 반지름 오차는 원 궤적에 들어선 뒤(연결 후 12프레임, 진행 방향을
## 둥글게 바꾸는 구간 제외)부터 첫 충돌 전·로프 감기가 없을 때만 센다.
func _watch_arc(player: PlayerController, buildings: Array, frames: int) -> Dictionary:
	var grapple := player.grapple
	var anchor := grapple.anchor
	var report := {"early_step": Vector2.ZERO, "max_radius_error": 0.0, "passed_over": false, "passed_under": false,
			"rose_on_right": false, "inside": 0, "max_step": 0.0}
	var bumps := player.bump_count
	var previous := player.global_position
	var previous_y := previous.y
	for i in frames:
		await physics_frames(1)
		if not grapple.is_attached:
			break
		var position := player.global_position
		var step := position - previous
		if i == 8:  # 진행 방향을 둥글게 바꾸는 몇 프레임 뒤
			report.early_step = step
		report.max_step = maxf(report.max_step, step.length())
		if _inside_any(position, buildings):
			report.inside += 1
		if i >= 12 and player.bump_count == bumps and grapple.reel_speed == 0.0:
			report.max_radius_error = maxf(report.max_radius_error, absf(position.distance_to(anchor) - grapple.rope_length))
		var rel := position - anchor
		if absf(rel.x) < 30.0 and rel.y < -0.7 * grapple.rope_length:
			report.passed_over = true
		if absf(rel.x) < 30.0 and rel.y > 0.7 * grapple.rope_length:
			report.passed_under = true
		if report.passed_under and rel.x > 0.5 * grapple.rope_length and position.y < previous_y:
			report.rose_on_right = true
		previous = position
		previous_y = position.y
	return report


## 플레이어 원이 건물과 2px 넘게 겹치면 관통으로 본다 (원-사각형 최단 거리 — 모서리에서 각진 판정 오류 없음)
func _inside_any(center: Vector2, buildings: Array) -> bool:
	for building in buildings:
		if not is_instance_valid(building):
			continue
		var rect := (building as Building).get_rect()
		var closest := Vector2(clampf(center.x, rect.position.x, rect.end.x), clampf(center.y, rect.position.y, rect.end.y))
		if center.distance_to(closest) < PlayerController.RADIUS - 2.0:
			return true
	return false


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
