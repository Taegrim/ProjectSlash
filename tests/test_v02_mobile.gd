## v0.2-6·7 — 모바일 터치·해상도: 자동 조준(아무 곳이나 누르기, v0.2-7 기본), 누른 위치 조준 + 띠 맞춤(v0.2-6, touch_auto_aim = false),
## 터치 → 마우스 에뮬레이션 경로, 터치 UI(일시정지 버튼·탭 재시작·UI 확대), 세로 화면 덮개·자동 일시정지, 화면 설정.
extends "res://tests/test_case.gd"

const MAIN_SCENE := preload("res://scenes/main.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const BUILDING_SCENE := preload("res://scenes/building.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const DEFAULT_MOVEMENT := preload("res://resources/default_movement.tres")
const FLOAT := {"gravity": 0.0, "auto_forward_speed": 0.0}
const MOUSE := 0
const TOUCH := InputEvent.DEVICE_ID_EMULATION


func after_each() -> void:
	tree.paused = false


func test_touch_near_band_snaps_to_wire_but_mouse_does_not() -> void:
	# 건물 왼쪽 위 모서리 (o+200, o−260) 바로 위를 누른다: 그 방향 광선은 지붕 위로 지나가 띠에 안 닿음
	var o := Vector2(700000, 300)
	var near := o + Vector2(190, -300)  # 띠까지 약 41px
	var mouse_player := _lab_player(o)
	mouse_player.touch_auto_aim = false  # v0.2-6 방식 (누른 위치 조준)
	_lab_building(o + Vector2(200, -260), Vector2(240, 900), 120.0)
	await physics_frames(2)
	check(not mouse_player.grapple.evaluate(near).ok, "준비: 누른 지점은 띠 밖 (%s)" % mouse_player.grapple.evaluate(near).reason)
	_press(mouse_player, near, MOUSE)
	check_eq(mouse_player.get_state_name(), "AIRBORNE", "마우스: 띠 밖이면 와이어 아님 (정확히 띠 위만)")
	_press(mouse_player, near, TOUCH)
	check_eq(mouse_player.get_state_name(), "GRAPPLING", "터치: %.0fpx 안이면 띠로 맞춰 와이어 (%s)" % [
			mouse_player.grapple_tuning.touch_snap_radius, mouse_player.grapple.last_request])


func test_touch_far_from_band_dashes() -> void:
	var o := Vector2(710000, 300)
	var player := _lab_player(o)
	player.touch_auto_aim = false
	_lab_building(o + Vector2(200, -260), Vector2(240, 900), 120.0)
	var enemy := _lab_enemy(o + Vector2(120, 60))  # 건물 앞 (가는 길이 막히지 않게)
	await physics_frames(2)
	_press(player, o + Vector2(150, -330), TOUCH)  # 띠까지 약 86px — 맞춤 범위 밖
	check_eq(player.get_state_name(), "DASHING", "터치: 띠에서 멀면 돌진 (%s)" % player.dash.last_request)
	check(player.dash.target == enemy, "돌진 대상은 자동 타기팅")


func test_snap_radius_zero_means_exact() -> void:
	var o := Vector2(720000, 300)
	var player := _lab_player(o)
	player.touch_auto_aim = false
	player.grapple_tuning = player.grapple_tuning.duplicate()
	player.grapple_tuning.touch_snap_radius = 0.0
	player.grapple.tuning = player.grapple_tuning
	_lab_building(o + Vector2(200, -260), Vector2(240, 900), 120.0)
	await physics_frames(2)
	_press(player, o + Vector2(190, -300), TOUCH)
	check_eq(player.get_state_name(), "AIRBORNE", "맞춤 반경 0 이면 터치도 정확히 띠 위만")


func test_screen_touch_goes_through_mouse_emulation() -> void:
	# 실제 경로: 화면 터치 → Godot 가 왼쪽 버튼으로 바꿔 보냄(장치 −1) → 플레이어 누름. 동시에 터치 모드로 바뀐다
	check(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true), "터치 → 마우스 에뮬레이션 켜짐")
	tree.change_scene_to_packed(MAIN_SCENE)
	await physics_frames(2)
	var main: Node = tree.current_scene
	var player: PlayerController = main.get_node("Player")
	check(not main.touch_mode, "데스크톱 시작은 마우스 모드")
	_touch(Vector2(420, 4), true)  # 플레이어 바로 위 하늘 (띠·적 없음)
	await physics_frames(1)
	check(main.touch_mode, "터치가 들어오면 터치 모드")
	check(player.last_press != "", "터치가 좌클릭 누름으로 전달됨 → 자동 조준 (%s / %s)" % [player.last_press,
			player.grapple.last_request])
	_touch(Vector2(420, 4), false)
	await physics_frames(1)
	var ui: GameUI = main.get_node("GameUI")
	check(ui.pause_button.visible, "터치 모드: 일시정지 버튼")
	check((ui.get_node("HintLabel") as Label).text.begins_with("Tap"), "터치 모드: 터치용 안내 줄")
	check(not main.debug_visible, "터치 모드: 디버그 창 숨김")
	check(player.touch_mode, "터치 모드: 조준 고리 숨김")
	main.touch_mouse_grace_ms = 0
	var motion := InputEventMouseMotion.new()
	motion.device = MOUSE
	main._input(motion)
	check(not main.touch_mode, "실제 마우스를 움직이면 마우스 모드로 돌아감")
	check(not ui.pause_button.visible, "마우스 모드: 일시정지 버튼 숨김 (ESC)")
	await _leave_main()


func test_auto_aim_tap_anywhere_wires_to_marked_band() -> void:
	var o := Vector2(730000, 300)
	var player := _lab_player(o)
	player.touch_mode = true
	var building := _lab_building(o + Vector2(200, -260), Vector2(240, 900), 120.0)
	await physics_frames(2)
	check(player.touch_auto_aim, "모바일 기본 = 자동 조준 (v0.2-7)")
	check(player.auto_preview.get("ok", false), "누르기 전에 걸릴 곳을 표시 (초록 표시)")
	check(building.get_attach_rect().grow(1.0).has_point(player.auto_preview.get("point", Vector2.INF)), "표시 지점은 앞 건물의 띠 위")
	_press(player, o + Vector2(-400, 300), MOUSE)
	check_eq(player.get_state_name(), "AIRBORNE", "마우스는 그대로 누른 위치 조준 (왼쪽 아래 빈 곳 → 아무 일 없음)")
	_press(player, o + Vector2(-400, 300), TOUCH)
	check_eq(player.get_state_name(), "GRAPPLING", "터치는 어디를 눌러도 표시한 띠에 와이어 (%s)" % player.grapple.last_request)
	check(player.grapple.building == building, "표시한 건물에 걸림")


func test_auto_aim_dashes_first_when_enemy_marked() -> void:
	var o := Vector2(740000, 300)
	var player := _lab_player(o)
	player.touch_mode = true
	_lab_building(o + Vector2(200, -260), Vector2(240, 900), 120.0)
	var enemy := _lab_enemy(o + Vector2(120, 60))
	await physics_frames(2)
	check(not player.auto_preview.get("ok", false), "적이 표시된 동안은 와이어 표시를 숨김 (누르면 돌진하므로)")
	_press(player, o + Vector2(-400, 300), TOUCH)
	check_eq(player.get_state_name(), "DASHING", "돌진할 적이 있으면 돌진 먼저")
	check(player.dash.target == enemy, "대상은 자동 타기팅")


func test_auto_aim_with_nothing_does_nothing() -> void:
	var o := Vector2(750000, 300)
	var player := _lab_player(o)
	await physics_frames(2)
	_press(player, o + Vector2(300, -300), TOUCH)
	check_eq(player.get_state_name(), "AIRBORNE", "걸 곳도 적도 없으면 아무 일 없음")
	check_eq(player.last_press, "none", "누름 기록")


func test_auto_aim_moves_on_to_next_building() -> void:
	# 낮은 A 와 그 너머 높은 B. A 에 걸고 나면 자동 조준은 B 를 고른다 (같은 건물 반복 대신 다음 건물로)
	var o := Vector2(760000, 300)
	var player := _lab_player(o)
	var a := _lab_building(o + Vector2(100, -120), Vector2(150, 900), 100.0)
	var b := _lab_building(o + Vector2(250, -350), Vector2(200, 900), 120.0)
	await physics_frames(2)
	check(player.find_auto_anchor().building == a, "처음엔 가장 앞의 A")
	_press(player, o + Vector2(-400, 300), TOUCH)
	check(player.grapple.is_attached, "A 에 연결 (%s)" % player.grapple.last_request)
	check(player.find_auto_anchor().building == b, "A 에 건 뒤에는 B")
	check(player.grapple.find_auto_anchor(a, a.serial + 1).building == a, "풀에서 다시 쓰인 건물(serial 다름)은 제외하지 않음")


func test_tap_restarts_after_game_over_but_not_immediately() -> void:
	tree.change_scene_to_packed(MAIN_SCENE)
	await physics_frames(2)
	var main: Node = tree.current_scene
	main.set_touch_mode(true)
	main.get_node("Player").die("fall")
	await physics_frames(1)
	check((main.get_node("GameUI/GameOverLabel") as Label).text.ends_with("TAP  to restart"), "게임 오버 안내: 탭하면 재시작")
	main._unhandled_input(_touch_event(Vector2(640, 360), true))
	await physics_frames(2)
	check(tree.current_scene == main and main.game_over, "게임 오버 직후(%dms 안) 탭은 무시 — 누르던 손가락에 바로 재시작 안 됨" %
			main.restart_tap_delay_ms)
	main._ended_at_ms -= main.restart_tap_delay_ms
	main._unhandled_input(_touch_event(Vector2(640, 360), true))
	await physics_frames(3)
	check(tree.current_scene != main and not tree.current_scene.game_over, "잠시 뒤 탭 → 재시작")
	await _leave_main()


func test_touch_pause_buttons() -> void:
	tree.change_scene_to_packed(MAIN_SCENE)
	await physics_frames(2)
	var main: Node = tree.current_scene
	var ui: GameUI = main.get_node("GameUI")
	main.set_touch_mode(true)
	check_eq(ui.pause_button.size, Vector2(GameUI.TOUCH_BUTTON_SIZE, GameUI.TOUCH_BUTTON_SIZE), "일시정지 버튼 크기 (손가락용)")
	var score_label: Label = ui.hud._score_label
	check_eq(score_label.get_theme_font_size("font_size"), roundi(30 * GameUI.TOUCH_UI_SCALE), "모바일은 점수 UI 를 크게 (v0.2-7)")
	main.set_touch_mode(false)
	check_eq(score_label.get_theme_font_size("font_size"), 30, "PC 로 돌아오면 원래 크기")
	main.set_touch_mode(true)
	ui.pause_button.pressed.emit()
	check(tree.paused, "일시정지 버튼 → 멈춤")
	check(ui.get_node("PauseButtons").visible, "멈춘 동안 RESUME·RESTART 버튼")
	ui.resume_button.pressed.emit()
	check(not tree.paused, "RESUME → 다시 움직임")
	check(not ui.get_node("PauseButtons").visible, "버튼 숨김")
	await _leave_main()


func test_portrait_shows_overlay_and_pauses() -> void:
	tree.change_scene_to_packed(MAIN_SCENE)
	await physics_frames(2)
	var main: Node = tree.current_scene
	var ui: GameUI = main.get_node("GameUI")
	main.apply_orientation(true)
	check(tree.paused and ui.rotate_overlay.visible, "세로 → 덮개 + 자동 일시정지")
	main.apply_orientation(false)
	check(not tree.paused and not ui.rotate_overlay.visible, "가로 → 덮개 사라지고 다시 움직임")
	main.toggle_pause()
	main.apply_orientation(true)
	main.apply_orientation(false)
	check(tree.paused, "직접 멈춘 상태였다면 가로로 돌아와도 계속 멈춰 있음")
	await _leave_main()


func test_display_settings_for_screens() -> void:
	check_eq(ProjectSettings.get_setting("display/window/stretch/mode"), "canvas_items", "UI·선이 해상도에 맞춰 선명하게")
	check_eq(ProjectSettings.get_setting("display/window/stretch/aspect"), "expand", "넓은 화면은 옆을, 4:3 은 위아래를 더 보여 줌 (검은 띠 없음)")
	check_eq(ProjectSettings.get_setting("display/window/handheld/orientation"), DisplayServer.SCREEN_SENSOR_LANDSCAPE,
			"휴대폰 앱은 가로 (양방향)")
	check(InputMap.has_action("toggle_fullscreen"), "F11 전체 화면")
	tree.change_scene_to_packed(MAIN_SCENE)
	await physics_frames(2)
	var hint := tree.current_scene.get_node("GameUI/HintLabel") as Label
	check(hint.anchor_left == 0.0 and hint.anchor_right == 1.0, "안내 줄은 화면 폭 전체에 맞춰 늘어남")
	await _leave_main()


func _press(player: PlayerController, at: Vector2, device: int) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = at  # 실험실은 카메라가 없어 화면 좌표 = 전역 좌표
	event.device = device
	player._unhandled_input(event)


func _touch_event(at: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = at
	event.pressed = pressed
	return event


func _touch(at: Vector2, pressed: bool) -> void:
	Input.parse_input_event(_touch_event(at, pressed))
	Input.flush_buffered_events()


func _leave_main() -> void:
	tree.paused = false
	tree.current_scene.queue_free()
	tree.current_scene = null
	await physics_frames(1)


func _lab_player(pos: Vector2) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.movement = DEFAULT_MOVEMENT.duplicate()
	for key in FLOAT:
		player.movement.set(key, FLOAT[key])
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


func _lab_enemy(pos: Vector2) -> Enemy:
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	enemy.position = pos
	add_node(enemy)
	return enemy
