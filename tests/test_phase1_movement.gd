## Phase 1 — 이동·충돌·카메라·사망·재시작 (기획서 §3, §5, §8, §9, §13.2-1·12·13·14·16).
## '실험실' 테스트는 메인 씬과 멀리 떨어진 좌표에 플레이어와 건물만 따로 놓고 확인한다.
extends "res://tests/test_case.gd"

const MAIN_SCENE := preload("res://scenes/main.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const BUILDING_SCENE := preload("res://scenes/building.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const DEFAULT_MOVEMENT := preload("res://resources/default_movement.tres")


func after_each() -> void:
	tree.paused = false


# --- §13.2-1 무조작 시 오른쪽으로 이동하며 결국 하강 ---

func test_no_input_moves_right_and_descends() -> void:
	var main := add_node(MAIN_SCENE.instantiate())
	var player: PlayerController = main.get_node("Player")
	var start := player.global_position
	await physics_frames(30)
	check(player.global_position.x > start.x + 100.0, "0.5초 동안 오른쪽으로 전진")
	check(player.global_position.y > start.y, "중력으로 하강")
	check_near(player.velocity.x, player.movement.auto_forward_speed, 1.0, "수평 속도 = 기본 전진 속도")


# --- §5.1 [확정] 일반 체공 최고 속도 제한, §5.2 수평/전체 기준 선택 ---

func test_cap_speed_modes() -> void:
	var tuning: MovementTuning = DEFAULT_MOVEMENT.duplicate()
	tuning.max_air_horizontal_speed = 500.0
	tuning.max_air_total_speed = 1000.0
	tuning.speed_cap_mode = MovementTuning.SpeedCapMode.HORIZONTAL_AND_TOTAL
	check_near(PlayerController.cap_speed(Vector2(2000, 0), tuning).x, 500.0, 0.01, "수평+전체: 수평 상한")
	check_near(PlayerController.cap_speed(Vector2(0, 3000), tuning).length(), 1000.0, 0.01, "수평+전체: 전체 상한")
	tuning.speed_cap_mode = MovementTuning.SpeedCapMode.HORIZONTAL_ONLY
	var horizontal_only := PlayerController.cap_speed(Vector2(2000, 3000), tuning)
	check(is_equal_approx(horizontal_only.x, 500.0) and is_equal_approx(horizontal_only.y, 3000.0), "수평만: 세로는 그대로")
	tuning.speed_cap_mode = MovementTuning.SpeedCapMode.TOTAL_ONLY
	check_near(PlayerController.cap_speed(Vector2(2000, 0), tuning).x, 1000.0, 0.01, "전체만: 수평도 전체 상한까지 허용")


func test_long_fall_respects_total_speed_cap() -> void:
	var player := _lab_player(Vector2(10000, -20000), Vector2.ZERO, {})
	await physics_frames(240)  # 4초 자유 낙하
	check(player.velocity.length() <= player.movement.max_air_total_speed + 0.5, "낙하 속도도 전체 상한을 넘지 않음")


# --- §8 [확정] 건물: 관통 불가, 접촉은 감속 (사망 아님) — §13.2-12 ---

func test_fast_player_cannot_pass_through_thin_building() -> void:
	var overrides := {"gravity": 0.0, "air_acceleration": 0.0, "auto_forward_speed": 3000.0,
			"max_air_horizontal_speed": 5000.0, "max_air_total_speed": 5000.0}
	var player := _lab_player(Vector2(20000, 0), Vector2(3000, 0), overrides)  # 프레임당 50px
	var wall := _lab_building(Vector2(20100, -200), Vector2(20, 400))
	await physics_frames(30)  # 막히지 않았다면 1500px 진행
	check(player.global_position.x + PlayerController.RADIUS <= wall.global_position.x + 0.5, "얇은 건물도 관통하지 않음")
	check_eq(player.state, PlayerController.State.AIRBORNE, "건물 충돌은 사망이 아님")
	check(player.bump_count >= 1, "충돌이 기록됨")


func test_roof_landing_slows_once_and_does_not_sink() -> void:
	var player := _lab_player(Vector2(30000, -100), Vector2(320, 300), {})
	var roof := _lab_building(Vector2(29900, 0), Vector2(2000, 400))
	var speed_after_bump := [-1.0]
	player.bumped.connect(func(_c: Object) -> void: speed_after_bump[0] = player.velocity.x, CONNECT_ONE_SHOT)
	await physics_frames(60)
	check(speed_after_bump[0] >= 0.0, "지붕에 닿음")
	check(speed_after_bump[0] <= 320.0 * player.movement.collision_speed_penalty + 15.0,
			"닿는 순간 수평 속도에 감속 비율 적용 (%.0f)" % speed_after_bump[0])
	check_eq(player.bump_count, 1, "지붕 위를 미끄러지는 동안 반복 감속하지 않음")
	check(player.global_position.y <= roof.global_position.y - PlayerController.RADIUS + 1.0, "지붕을 뚫고 들어가지 않음")
	check_eq(player.state, PlayerController.State.AIRBORNE, "사망 아님")


func test_enemy_body_contact_slows_like_obstacle() -> void:
	# §8 [MVP 제안] 돌진이 아닌 몸 접촉은 일반 장애물처럼 감속
	var player := _lab_player(Vector2(40000, 0), Vector2(320, 0), {"gravity": 0.0})
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	enemy.position = Vector2(40150, 0)
	add_node(enemy)
	await physics_frames(60)
	check(player.bump_count >= 1, "적과 부딪힘")
	check_eq(player.state, PlayerController.State.AIRBORNE, "적 몸 접촉은 사망이 아님")
	check(enemy.alive, "몸 접촉으로는 적이 죽지 않음 (돌진만 처치)")
	check(player.global_position.x < enemy.global_position.x, "적을 통과하지 않음")


# --- §8 [확정] 하단 판정선·위험 장애물 = 게임 오버 — §13.2-13 ---

func test_falling_below_limit_is_game_over() -> void:
	var main := add_node(MAIN_SCENE.instantiate())
	var player: PlayerController = main.get_node("Player")
	var course: TestCourse = main.get_node("TestCourse")
	for _i in 10:
		await physics_frames(30)
		if player.state == PlayerController.State.DEAD:
			break
	check_eq(player.state, PlayerController.State.DEAD, "무조작이면 결국 추락해 사망")
	check_eq(main.game_over_reason, "fall", "사망 원인 = 추락")
	check(player.global_position.y > course.fall_limit_y, "판정선 아래에서 사망")
	var ui: GameUI = main.get_node("GameUI")
	check(ui.is_game_over_visible(), "게임 오버 표시")
	var frozen := player.global_position
	await physics_frames(10)
	check(player.global_position.distance_to(frozen) < 0.01, "사망 후 물리 이동 중지 (§9.1 DEAD)")


func test_touching_hazard_is_game_over() -> void:
	var main := add_node(MAIN_SCENE.instantiate())
	var player: PlayerController = main.get_node("Player")
	var hazard: Hazard = (main.get_node("TestCourse") as TestCourse).get_hazards()[0]
	player.global_position = hazard.get_rect().get_center()  # 테스트 준비: 위험 구역 안에 둔다
	await physics_frames(3)
	check_eq(player.state, PlayerController.State.DEAD, "위험 구역에 닿으면 사망")
	check_eq(main.game_over_reason, "hazard", "사망 원인 = 위험 장애물")


func test_building_contact_alone_is_not_game_over() -> void:
	# 무조작 비행은 A 의 벽에 부딪힌 뒤 추락한다 — 부딪힌 순간에는 살아 있어야 한다
	var main := add_node(MAIN_SCENE.instantiate())
	var player: PlayerController = main.get_node("Player")
	var state_at_bump := [-1]
	player.bumped.connect(func(_c: Object) -> void: state_at_bump[0] = player.state, CONNECT_ONE_SHOT)
	for _i in 10:
		await physics_frames(20)
		if state_at_bump[0] != -1:
			break
	check_eq(state_at_bump[0], PlayerController.State.AIRBORNE, "건물에 부딪힌 순간 살아 있음")


# --- §3 [필수 주의] 카메라가 아래로 끝없이 따라가지 않음 — §13.2-14 ---

func test_camera_does_not_follow_fall_forever() -> void:
	var main := add_node(MAIN_SCENE.instantiate())
	var player: PlayerController = main.get_node("Player")
	var camera: CourseCamera = main.get_node("CourseCamera")
	var lowest_seen := -INF
	for _i in 300:
		await physics_frames(1)
		lowest_seen = maxf(lowest_seen, camera.global_position.y)
		if player.state == PlayerController.State.DEAD:
			break
	check(lowest_seen <= camera.get_lowest_y() + 0.5, "카메라 Y 는 하한을 넘지 않음 (최대 %.0f)" % lowest_seen)
	# 헤드리스 뷰포트는 실제 창 크기와 다르므로 기준 해상도(1280×720)로 판단한다
	var view_half_height := float(ProjectSettings.get_setting("display/window/size/viewport_height")) / 2.0
	check(player.global_position.y > camera.global_position.y + view_half_height,
			"추락한 플레이어는 화면 아래로 사라진 뒤 사망 (player y %.0f, camera y %.0f, 화면 절반 %.0f)"
			% [player.global_position.y, camera.global_position.y, view_half_height])


func test_camera_follows_upward() -> void:
	var main := add_node(MAIN_SCENE.instantiate())
	var player: PlayerController = main.get_node("Player")
	var camera: CourseCamera = main.get_node("CourseCamera")
	var start_y := camera.global_position.y
	player.velocity = Vector2(300, -700)  # 위로 솟구치는 상황 (해제 도약 등)
	await physics_frames(30)
	check(camera.global_position.y < start_y - 50.0, "플레이어가 위로 올라가면 카메라도 따라 올라감")


# --- 일시정지 · 재시작 · 거리 ---

func test_pause_freezes_world() -> void:
	var main := add_node(MAIN_SCENE.instantiate())
	var player: PlayerController = main.get_node("Player")
	await physics_frames(5)
	main.toggle_pause()
	var frozen := player.global_position
	await physics_frames(20)
	check(player.global_position.distance_to(frozen) < 0.01, "일시정지 중에는 움직이지 않음")
	main.toggle_pause()
	await physics_frames(5)
	check(player.global_position.x > frozen.x, "해제하면 다시 움직임")


func test_restart_resets_everything() -> void:
	# §13.2-16: 재시작하면 물리 상태·위치·적·게임 오버가 초기화된다. 실제 재시작 경로(씬 다시 불러오기)를 쓴다.
	tree.change_scene_to_packed(MAIN_SCENE)
	await physics_frames(2)
	var first: Node = tree.current_scene
	var first_player: PlayerController = first.get_node("Player")
	first_player.die("fall")
	(first.get_node("TestCourse") as TestCourse).get_enemies()[0].kill()
	check(first.game_over, "재시작 전: 게임 오버 상태")
	first.restart()
	await physics_frames(3)
	var fresh: Node = tree.current_scene
	check(fresh != first and is_instance_valid(fresh), "새 씬으로 다시 불러옴")
	var player: PlayerController = fresh.get_node("Player")
	var course: TestCourse = fresh.get_node("TestCourse")
	check_eq(player.state, PlayerController.State.AIRBORNE, "플레이어 상태 초기화")
	check(player.global_position.distance_to(course.get_spawn_position()) < 40.0, "스폰 근처에서 다시 시작")
	check(not fresh.game_over, "게임 오버 해제")
	check(course.get_enemies().all(func(e: Enemy) -> bool: return e.alive), "적이 모두 되살아남")
	check(fresh.get_distance() < 40.0, "거리 점수 초기화")
	tree.current_scene.queue_free()
	tree.current_scene = null
	await physics_frames(1)


func test_distance_uses_max_reached_x() -> void:
	var main := add_node(MAIN_SCENE.instantiate())
	await physics_frames(30)
	var distance: float = main.get_distance()
	check(distance > 100.0, "전진한 만큼 거리 증가")
	(main.get_node("Player") as PlayerController).global_position.x -= 300.0  # 뒤로 밀린 상황
	await physics_frames(1)
	check(main.get_distance() >= distance, "뒤로 밀려도 거리 점수는 줄지 않음 (§11 최대 도달 X)")


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


func _lab_building(pos: Vector2, size: Vector2) -> Building:
	var building: Building = BUILDING_SCENE.instantiate()
	building.position = pos
	building.size = size
	add_node(building)
	return building
