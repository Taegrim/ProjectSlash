## v0.2-5 — 한 버튼 조작 (사용자 결정: 좌클릭 하나로 와이어·돌진. 조준이 건물 연결 띠 위면 와이어, 아니면 돌진).
## 실제 입력 경로(_unhandled_input)에 마우스 이벤트를 넣어 확인한다. 조준점은 debug_aim_override 로 정한다.
extends "res://tests/test_case.gd"

const MAIN_SCENE := preload("res://scenes/main.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const BUILDING_SCENE := preload("res://scenes/building.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const DEFAULT_MOVEMENT := preload("res://resources/default_movement.tres")
const FLOAT := {"gravity": 0.0, "auto_forward_speed": 0.0}
const SKY := Vector2(0, -600)  # 연결할 것이 없는 빈 하늘 (플레이어 기준)


func after_each() -> void:
	PlayerController.one_button_override = -1  # 다른 테스트에 남지 않게


func test_default_is_one_button() -> void:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	check(player.one_button_default, "기본 = 한 버튼 (v0.2-5 사용자 결정)")
	check(player.is_one_button(), "덮어쓰기 없으면 기본값")
	player.free()


func test_aim_on_band_attaches_wire_even_with_enemy_in_range() -> void:
	var o := Vector2(600000, 300)
	var player := _lab_player(o, FLOAT)
	_lab_building(o + Vector2(200, -260), Vector2(240, 900), 120.0)
	_lab_enemy(o + Vector2(150, 40), "InRange")  # 돌진할 적도 있지만 조준이 띠 위면 와이어가 우선
	await physics_frames(2)
	check(player.dash.find_target().enemy != null, "준비: 돌진 가능한 적이 있음")
	_click(player, o + Vector2(204, -250), true)
	check_eq(player.get_state_name(), "GRAPPLING", "띠 조준 → 와이어 (%s)" % player.grapple.last_request)
	_click(player, o + Vector2(204, -250), false)
	check_eq(player.get_state_name(), "AIRBORNE", "놓으면 와이어 해제 (예전과 같음)")


func test_aim_elsewhere_dashes_to_auto_target() -> void:
	var o := Vector2(610000, 300)
	var player := _lab_player(o, FLOAT)
	var enemy := _lab_enemy(o + Vector2(220, 30), "Target")
	await physics_frames(2)
	_click(player, o + SKY, true)
	check_eq(player.get_state_name(), "DASHING", "띠가 아닌 곳 조준 → 돌진 (%s)" % player.dash.last_request)
	check(player.dash.target == enemy, "돌진 대상은 조준과 무관한 자동 타기팅 (§7.2)")
	_click(player, o + SKY, false)
	check_eq(player.get_state_name(), "DASHING", "버튼을 놓아도 돌진은 계속 (와이어가 아니므로)")


func test_aim_elsewhere_without_enemy_does_nothing() -> void:
	var o := Vector2(620000, 300)
	var player := _lab_player(o, FLOAT)
	await physics_frames(2)
	_click(player, o + SKY, true)
	check_eq(player.get_state_name(), "AIRBORNE", "대상 없음 → 상태 그대로 (§9.2)")
	check(player.dash.last_request.begins_with("no target"), "돌진 요청 기록 (%s)" % player.dash.last_request)
	_click(player, o + SKY, false)
	check_eq(player.get_state_name(), "AIRBORNE", "놓아도 아무 일 없음")


func test_two_button_scheme_keeps_old_mapping() -> void:
	PlayerController.one_button_override = 0
	var o := Vector2(630000, 300)
	var player := _lab_player(o, FLOAT)
	_lab_enemy(o + Vector2(220, 30), "Target")
	await physics_frames(2)
	check(not player.is_one_button(), "F3 로 두 버튼")
	_click(player, o + SKY, true)
	_click(player, o + SKY, false)
	check_eq(player.get_state_name(), "AIRBORNE", "두 버튼: 좌클릭은 와이어만 (빈 곳이면 아무 일 없음)")
	_click(player, o + SKY, true, MOUSE_BUTTON_RIGHT)
	check_eq(player.get_state_name(), "DASHING", "두 버튼: 우클릭 돌진")


func test_right_click_still_dashes_in_one_button() -> void:
	var o := Vector2(640000, 300)
	var player := _lab_player(o, FLOAT)
	_lab_enemy(o + Vector2(220, 30), "Target")
	await physics_frames(2)
	_click(player, o + SKY, true, MOUSE_BUTTON_RIGHT)
	check_eq(player.get_state_name(), "DASHING", "한 버튼에서도 우클릭 돌진은 남겨 둠")


func test_one_button_release_dash_reattach() -> void:
	# CLAUDE.md 10번 회귀: 스윙 해제 → 돌진 → 재연결 을 좌클릭 하나로
	var o := Vector2(650000, 300)
	var player := _lab_player(o, {})
	player.velocity = Vector2(320, 0)
	var first := _lab_building(o + Vector2(200, -260), Vector2(240, 900), 120.0)
	await physics_frames(2)
	_click(player, o + Vector2(204, -250), true)
	check_eq(player.get_state_name(), "GRAPPLING", "좌클릭(띠) → 와이어")
	await physics_frames(30)
	_click(player, o + Vector2(204, -250), false)
	check_eq(player.get_state_name(), "AIRBORNE", "놓기 → 스윙 해제")
	first.queue_free()  # 스윙은 끝났다. 뒤의 조준선을 가리지 않게 치운다 (상태 흐름만 확인)
	var enemy := _lab_enemy(player.global_position + Vector2(220, 20), "Target")
	await physics_frames(1)
	_click(player, player.global_position + SKY, true)
	check_eq(player.get_state_name(), "DASHING", "좌클릭(빈 곳) → 돌진 (%s)" % player.dash.last_request)
	_click(player, player.global_position + SKY, false)
	while player.state == PlayerController.State.DASHING:
		await physics_frames(1)
	check(not enemy.alive, "적 처치")
	var next := _lab_building(player.global_position + Vector2(260, -120), Vector2(240, 900), 120.0)
	await physics_frames(1)
	_click(player, next.global_position + Vector2(4, 30), true)
	check_eq(player.get_state_name(), "GRAPPLING", "좌클릭(띠) → 재연결 (%s)" % player.grapple.last_request)


func test_toggle_switches_scheme_and_survives_restart() -> void:
	tree.change_scene_to_packed(MAIN_SCENE)
	await physics_frames(2)
	var main: Node = tree.current_scene
	var hint := main.get_node("GameUI/HintLabel") as Label
	check(hint.text.begins_with("LMB = wire on yellow band"), "안내 줄: 한 버튼 설명 (%s)" % hint.text)
	main.toggle_input_scheme()
	check(not main.get_node("Player").is_one_button(), "F3 → 두 버튼")
	check(hint.text.contains("RMB dash"), "안내 줄: 두 버튼 설명")
	main.restart()
	await physics_frames(3)
	check(not tree.current_scene.get_node("Player").is_one_button(), "재시작해도 고른 방식 유지")
	check(InputMap.has_action("toggle_input_scheme"), "F3 입력 액션")
	PlayerController.one_button_override = -1
	tree.current_scene.queue_free()
	tree.current_scene = null
	await physics_frames(1)


## 마우스 버튼 이벤트를 플레이어 입력 처리에 직접 넣는다 (조준점은 debug_aim_override)
func _click(player: PlayerController, aim: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	player.debug_aim_override = aim
	player.aim_point = aim
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.device = -1
	player._unhandled_input(event)


func _lab_player(pos: Vector2, overrides: Dictionary) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.movement = DEFAULT_MOVEMENT.duplicate()
	for key in overrides:
		player.movement.set(key, overrides[key])
	player.position = pos
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
