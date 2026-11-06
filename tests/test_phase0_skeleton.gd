## Phase 0 — 프로젝트 골격이 기획서 규칙과 맞는지 확인한다.
extends "res://tests/test_case.gd"

const MAIN_SCENE := preload("res://scenes/main.tscn")
const COURSE_SCENE := preload("res://scenes/test_course.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const HAZARD_SCENE := preload("res://scenes/hazard.tscn")
const ARROW_KEYS := [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]


func test_main_scene_has_core_nodes() -> void:
	var main := add_node(MAIN_SCENE.instantiate())
	await physics_frames(2)
	for path in ["TestCourse", "Player", "CourseCamera", "GameUI"]:
		check(main.has_node(path), "Main 에 %s 노드가 있어야 함" % path)


func test_course_follows_design_pattern() -> void:
	# §10.1 [확정] 건물 → 건물 → 적 → 적 → 건물 (진행 방향 +X 순서)
	var course: TestCourse = add_node(COURSE_SCENE.instantiate())
	await physics_frames(1)
	var items: Array = []
	for building in course.get_buildings():
		items.append([building.global_position.x, "B"])
	for enemy in course.get_enemies():
		items.append([enemy.global_position.x, "E"])
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var pattern := "".join(items.map(func(item: Array) -> String: return item[1]))
	check_eq(pattern, "BBEEB", "배치 순서 (B = 건물, E = 적)")
	check(course.get_hazards().size() >= 1, "위험 구간이 1개 이상 있어야 함 (§10.2-6)")
	for hazard in course.get_hazards():
		check(hazard.global_position.x > course.get_buildings()[-1].global_position.x, "위험 구간은 마지막 건물 뒤")


func test_fall_limit_is_below_everything_reachable() -> void:
	# §3 [필수 주의] 하단 사망 판정선은 코스보다 아래의 독립된 선이어야 한다
	var course: TestCourse = add_node(COURSE_SCENE.instantiate())
	await physics_frames(1)
	check(course.fall_limit_y > course.get_spawn_position().y, "스폰 위치보다 아래")
	for building in course.get_buildings():
		check(course.fall_limit_y > building.global_position.y, "%s 지붕보다 아래" % building.name)
	for enemy in course.get_enemies():
		check(course.fall_limit_y > enemy.global_position.y, "%s 보다 아래" % enemy.name)


func test_buildings_have_attach_band_inside_bounds() -> void:
	# §6.2 [MVP 제안] 건물별 유효 와이어 영역 = 지붕부터의 상단 띠
	var course: TestCourse = add_node(COURSE_SCENE.instantiate())
	await physics_frames(1)
	for building in course.get_buildings():
		var band := building.get_attach_rect()
		check(band.size.y > 0.0, "%s: 연결 띠가 있어야 함" % building.name)
		check(building.get_rect().encloses(band), "%s: 연결 띠가 건물 안에 있어야 함" % building.name)
		check_eq(band.position, building.global_position, "%s: 띠는 지붕에서 시작" % building.name)


func test_input_map_matches_design() -> void:
	# §4: 좌클릭 = 와이어, 우클릭 = 돌진 [확정] / ESC 일시정지, R 재시작 [MVP 제안]
	check(_has_mouse_button("grapple", MOUSE_BUTTON_LEFT), "grapple = 마우스 왼쪽")
	check(_has_mouse_button("dash", MOUSE_BUTTON_RIGHT), "dash = 마우스 오른쪽")
	check(_has_key("pause", KEY_ESCAPE), "pause = ESC")
	check(_has_key("restart", KEY_R), "restart = R")
	check(_has_key("toggle_debug", KEY_F1), "toggle_debug = F1")
	check(_has_key("toggle_overview", KEY_TAB), "toggle_overview = Tab")
	# §4 [확정] v0.1 은 방향키를 쓰지 않는다 — 게임 액션에 방향키가 묶여 있으면 안 됨 (Godot 기본 ui_* 제외)
	for action in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventKey and (event as InputEventKey).physical_keycode in ARROW_KEYS:
				fail("%s 에 방향키가 묶여 있음" % action)


func test_player_starts_airborne_at_spawn_with_design_collisions() -> void:
	var main := add_node(MAIN_SCENE.instantiate())
	var player: PlayerController = main.get_node("Player")
	var course: TestCourse = main.get_node("TestCourse")
	# Phase 1 부터 플레이어가 바로 움직이므로 첫 물리 프레임 전에 확인한다
	check(player.global_position.distance_to(course.get_spawn_position()) < 1.0, "스폰 위치에서 시작")
	await physics_frames(1)
	check_eq(player.state, PlayerController.State.AIRBORNE, "시작 상태 (§9.1)")
	check(player.get_collision_mask_value(2), "건물과 충돌 (관통 불가, §8)")
	check(player.get_collision_mask_value(3), "적과 충돌 (비돌진 접촉 = 감속, §8)")
	check(not player.get_collision_mask_value(4), "위험 구역과는 몸으로 부딪히지 않고 감지만 됨")
	check_eq(player.motion_mode, CharacterBody2D.MOTION_MODE_FLOATING, "공중 체공 기본 → FLOATING")


func test_camera_keeps_player_left_of_center() -> void:
	# §3 [MVP 제안] 진로가 보이도록 플레이어를 화면 중앙보다 왼쪽에 둔다
	var main := add_node(MAIN_SCENE.instantiate())
	await physics_frames(2)
	var player: PlayerController = main.get_node("Player")
	var camera: CourseCamera = main.get_node("CourseCamera")
	check(camera.global_position.x > player.global_position.x, "카메라 중심이 플레이어보다 앞(+X)")
	check_near(camera.global_position.x - player.global_position.x, player.movement.camera_forward_offset, 0.5,
			"앞쪽 여유 = camera_forward_offset")


func test_hazard_reports_player_touch() -> void:
	# §8 [확정] 위험 장애물 접촉 → 게임 오버 (연결은 Phase 1). 지금은 감지 신호가 나가는지만 확인
	var hazard: Hazard = HAZARD_SCENE.instantiate()
	hazard.position = Vector2(5000, 5000)
	hazard.size = Vector2(100, 100)
	add_node(hazard)
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.position = Vector2(5050, 5050)
	add_node(player)
	var touched := [false]
	hazard.player_touched.connect(func(_h: Hazard) -> void: touched[0] = true)
	await physics_frames(3)
	check(touched[0], "플레이어가 위험 구역 안에 있으면 player_touched 신호")


func test_tuning_resources_are_separate_and_sane() -> void:
	var movement: MovementTuning = load("res://resources/default_movement.tres")
	var grapple: GrappleTuning = load("res://resources/default_grapple.tres")
	var dash: DashTuning = load("res://resources/default_dash.tres")
	check(movement != null and grapple != null and dash != null, "튜닝 Resource 3종 로드")
	check(movement.auto_forward_speed > 0.0 and movement.gravity > 0.0, "기본 이동 값이 양수")
	check(movement.max_air_horizontal_speed >= movement.auto_forward_speed, "체공 수평 상한 ≥ 기본 전진 속도")
	# §5.1·§15-8: 돌진 속도는 일반 체공 최고 속도와 구별되는 별도 값
	check(dash.dash_speed > movement.max_air_total_speed, "돌진 속도 > 체공 전체 속력 상한 (임시값 점검)")


func _has_mouse_button(action: String, button: MouseButton) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == button:
			return true
	return false


func _has_key(action: String, key: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == key:
			return true
	return false
