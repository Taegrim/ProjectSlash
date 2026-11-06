## 게임 흐름 (Main) — 코스·플레이어·카메라·UI 를 잇고, 사망·게임 오버·재시작과 일시정지를 처리한다.
##
## 사망 조건 (§8 [확정]): 하단 판정선 아래로 추락, 위험 장애물 접촉. 일반 건물·적 접촉은 감속일 뿐 사망이 아니다.
## 사망 판정은 다른 전환보다 먼저 본다 (§9.2 [MVP 제안] 우선순위).
## 재시작 (§4 R [MVP 제안], §13.2-16): 씬을 다시 불러와 위치·속도·와이어·돌진 타깃·적·점수를 모두 처음으로 되돌린다.
## 거리 점수는 '최대 도달 X' 기준 (§11 [MVP 제안]) — v0.1 은 표시만.
## 코스 클리어 (Phase 4): 살아서 결승선을 넘으면 세계를 멈추고 시간·거리·처치 수를 보여 준다. R 로 바로 다시 시작.
## 입력 처리는 함수(toggle_pause, restart, ...)로 나눠 두어 테스트와 터치 UI 가 같은 경로를 쓴다.
## 터치·화면 (v0.2-6): 모바일이거나 터치가 들어오면 터치 모드(일시정지 버튼·탭 재시작·조준 고리 숨김), 실제 마우스를 움직이면 해제.
## 화면이 세로가 되면 '가로로 돌려 주세요' 덮개를 띄우고 자동으로 멈췄다가 가로가 되면 다시 움직인다. F11 = 전체 화면 (데스크톱).
extends Node2D

@onready var course: CourseBase = _find_course()
@onready var player: PlayerController = $Player
@onready var camera: CourseCamera = $CourseCamera
@onready var ui: GameUI = $GameUI

var start_x := 0.0
var max_x := 0.0
var debug_visible := true
var game_over := false
var game_over_reason := ""
var finished := false
## 플레이 시간 (s) — 일시정지·게임 오버·클리어 뒤에는 멈춘다
var elapsed := 0.0
## 점수·콤보 (v0.2-2)
var score: ScoreKeeper
## 시각 효과·효과음 (v0.2-3)
var fx: FX
var sfx: SFX
## 터치 모드 (v0.2-6)
var touch_mode := false
## 게임 오버·클리어 뒤 탭으로 재시작하기까지 기다리는 시간 (ms) — 플레이 중 누르던 손가락에 바로 재시작되지 않게
var restart_tap_delay_ms := 500
## 마지막 터치 뒤 이 시간 안의 마우스 움직임은 터치 모드를 끄지 않는다 (ms)
var touch_mouse_grace_ms := 1000
## 세로 화면 때문에 자동으로 멈췄는지 (가로가 되면 이것만 풀어 준다)
var paused_by_orientation := false
var _ended_at_ms := 0
var _last_touch_ms := -1000000


func _ready() -> void:
	# Main 은 일시정지 중에도 ESC·R 을 받아야 하고, 게임 세계는 일시정지에 멈춰야 한다.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for node: Node in [course, player, camera]:
		node.process_mode = Node.PROCESS_MODE_PAUSABLE

	player.global_position = course.get_spawn_position()
	player.velocity = Vector2(player.movement.auto_forward_speed, 0.0)  # 시작부터 바로 전진 (§5.1)
	player.died.connect(_on_player_died)
	for hazard in course.get_hazards():
		watch_hazard(hazard)
	start_x = player.global_position.x
	max_x = start_x

	camera.overview_rect = course.get_bounds()
	camera.configure(player, player.movement, course.get_spawn_position().y)
	_apply_debug_visible()
	score = ScoreKeeper.new()
	score.process_mode = Node.PROCESS_MODE_PAUSABLE  # 일시정지 중에는 콤보 시간도 멈춘다
	add_child(score)
	score.setup(player, load("res://resources/default_score.tres"))
	Engine.time_scale = 1.0  # 히트스톱 도중 재시작돼도 원래 속도로
	fx = FX.new()
	fx.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(fx)
	fx.setup(player, camera)
	sfx = SFX.new()
	add_child(sfx)
	sfx.setup(player, score)
	ui.set_air_control(player.get_air_control_mode())
	ui.set_input_scheme(player.is_one_button())
	ui.pause_pressed.connect(toggle_pause)
	ui.restart_pressed.connect(restart)
	set_touch_mode(OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"))
	get_viewport().size_changed.connect(_check_orientation)
	_check_orientation()
	WebSelfTest.attach_if_requested(self)  # 개발용: 웹 빌드를 ?selftest 로 열 때만 (tools/web_build.py --check)


func _physics_process(delta: float) -> void:
	if game_over or finished or get_tree().paused:
		return
	elapsed += delta
	# 거리는 사망 판정 전에 갱신해야 게임 오버 표시와 디버그 값이 일치한다
	max_x = maxf(max_x, player.global_position.x)
	course.update_course(player.global_position.x)
	if player.global_position.y > course.get_fall_limit_y():
		player.die("fall")
	elif player.global_position.y < course.get_ceiling_y():
		player.die("ceiling")
	elif player.global_position.x >= course.get_finish_x():
		_finish()


## 입력 장치 감지 (GUI 버튼이 먹는 입력도 보도록 _input 에서)
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_last_touch_ms = Time.get_ticks_msec()
		if not touch_mode:
			set_touch_mode(true)
	elif touch_mode and event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION 			and Time.get_ticks_msec() - _last_touch_ms >= touch_mouse_grace_ms:
		set_touch_mode(false)


func _unhandled_input(event: InputEvent) -> void:
	if (game_over or finished) and event is InputEventScreenTouch and event.pressed 			and Time.get_ticks_msec() - _ended_at_ms >= restart_tap_delay_ms:
		restart()  # 터치: 게임 오버·클리어 화면을 탭하면 재시작
	elif event.is_action_pressed("pause"):
		toggle_pause()
	elif event.is_action_pressed("restart"):
		restart()
	elif event.is_action_pressed("toggle_debug"):
		toggle_debug()
	elif event.is_action_pressed("toggle_overview"):
		toggle_overview()
	elif event.is_action_pressed("toggle_air_control"):
		toggle_air_control()
	elif event.is_action_pressed("toggle_input_scheme"):
		toggle_input_scheme()
	elif event.is_action_pressed("toggle_fullscreen"):
		toggle_fullscreen()


func _process(_delta: float) -> void:
	if debug_visible:
		ui.set_debug_text(_debug_text())
	var combo_ratio := score.combo_time_left / score.tuning.combo_window
	ui.hud.show_values(get_score(), get_distance() / score.tuning.px_per_meter, score.combo,
			score.multiplier_for(score.combo), score.last_bonus, combo_ratio)


func toggle_pause() -> void:
	if game_over or finished:
		return
	paused_by_orientation = false
	get_tree().paused = not get_tree().paused
	ui.set_paused(get_tree().paused)


## 즉시 재시작 — 씬을 다시 불러와 모든 상태를 초기화한다. 게임 오버가 아니어도 동작한다.
func restart() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


## 공중 좌우 조작 A/B 전환 (F2). 재시작해도 유지된다
func toggle_air_control() -> void:
	var next := MovementTuning.AirControlMode.FINE if player.get_air_control_mode() == MovementTuning.AirControlMode.NONE 			else MovementTuning.AirControlMode.NONE
	PlayerController.air_control_override = next
	ui.set_air_control(next)


## 입력 방식 전환 (F3): 한 버튼(좌클릭 = 띠 조준이면 와이어, 아니면 돌진) ↔ 두 버튼(좌 와이어 / 우 돌진). 재시작해도 유지
func toggle_input_scheme() -> void:
	var one := not player.is_one_button()
	PlayerController.one_button_override = 1 if one else 0
	ui.set_input_scheme(one)


## 터치 모드 켜기/끄기. 켤 때는 디버그 표시를 숨긴다 (휴대폰에는 F1 이 없고 화면을 가림)
func set_touch_mode(enabled: bool) -> void:
	touch_mode = enabled
	player.touch_mode = enabled
	player.queue_redraw()
	ui.set_touch_mode(enabled)
	if enabled and debug_visible:
		debug_visible = false
		_apply_debug_visible()


## 화면이 세로인지 확인 (창 크기가 바뀔 때마다)
func _check_orientation() -> void:
	var size := get_viewport().get_visible_rect().size
	apply_orientation(size.x < size.y)


## 세로면 덮개 + 자동 일시정지, 가로로 돌아오면 자동으로 멈춘 경우에만 다시 움직인다
func apply_orientation(portrait: bool) -> void:
	ui.set_rotate_overlay(portrait)
	if portrait and not get_tree().paused and not game_over and not finished:
		get_tree().paused = true
		paused_by_orientation = true
	elif not portrait and paused_by_orientation:
		get_tree().paused = false
		paused_by_orientation = false


## 전체 화면 전환 (F11, 데스크톱). 웹은 브라우저의 전체 화면(F11)을 쓴다
func toggle_fullscreen() -> void:
	if OS.has_feature("web"):
		return
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)


func toggle_debug() -> void:
	debug_visible = not debug_visible
	_apply_debug_visible()


func toggle_overview() -> void:
	camera.overview_rect = course.get_bounds()  # 무한 코스는 지금 만들어진 구간
	camera.set_overview(not camera.overview)
	_apply_debug_visible()


## 메인 씬의 코스 노드 (TestCourse 또는 EndlessCourse — 둘 다 CourseBase)
func _find_course() -> CourseBase:
	for child in get_children():
		if child is CourseBase:
			return child
	return null


## 총점 = 거리 점수 + 콤보 보너스 (§11)
func get_score() -> int:
	return score.total(get_distance())


## 이동 거리 점수 기준 — 최대 도달 X (뒤로 밀려도 줄지 않음)
func get_distance() -> float:
	return max_x - start_x


func _finish() -> void:
	finished = true
	_ended_at_ms = Time.get_ticks_msec()
	get_tree().paused = true  # 세계를 멈춘다 (Main 은 계속 입력을 받아 R 로 재시작)
	ui.show_clear(elapsed, get_distance(), player.dash.kill_count)


## 위험 구역 접촉을 사망으로 연결한다 (무한 코스가 풀을 늘릴 때도 부른다)
func watch_hazard(hazard: Hazard) -> void:
	hazard.player_touched.connect(_on_hazard_touched)


func _on_hazard_touched(_hazard: Hazard) -> void:
	player.die("hazard")


func _on_player_died(reason: String) -> void:
	game_over = true
	game_over_reason = reason
	_ended_at_ms = Time.get_ticks_msec()
	ui.show_game_over(reason, get_distance(), get_score(), score.best_combo)


func _apply_debug_visible() -> void:
	# 코스 전체 보기에서는 패널이 코스 왼쪽 위(스폰 지점)를 가리므로 숨긴다
	ui.set_debug_visible(debug_visible and not camera.overview)
	player.debug_draw = debug_visible
	player.queue_redraw()


func _debug_text() -> String:
	var v := player.velocity
	return "\n".join([
		"STATE  %s%s" % [player.get_state_name(), ("  (%s)" % game_over_reason) if game_over else ""],
		"POS    (%.0f, %.0f)" % [player.global_position.x, player.global_position.y],
		"VEL    (%.0f, %.0f)   |v| %.0f" % [v.x, v.y, v.length()],
		"DIST   %.0f px  (max x)" % get_distance(),
		"TIME   %.1f s" % elapsed,
		"BUMPS  %d   (contact = slow, not death)" % player.bump_count,
		"WIRE   %s" % player.grapple.describe(),
		"AIM    %s" % ("attachable" if player.aim_preview.get("ok", false) else player.aim_preview.get("reason", "-")),
		"DASH   %s" % player.dash.describe(),
		"AIR    %s  input %+.0f" % ["A (none)" if player.get_air_control_mode() == MovementTuning.AirControlMode.NONE
				else "B (fine)", player.air_input],
		"FALL   y > %.0f = game over" % course.get_fall_limit_y(),
		"CAM    y %.0f  (lowest %.0f)%s" % [camera.global_position.y, camera.get_lowest_y(),
				"  overview" if camera.overview else ""],
		"FPS    %d" % Engine.get_frames_per_second(),
	] + ([] if course.describe().is_empty() else ["COURSE %s" % course.describe()]))
