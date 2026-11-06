## 게임 흐름 (Main) — 코스·플레이어·카메라·UI 를 잇고, 사망·게임 오버·재시작과 일시정지를 처리한다.
##
## 사망 조건 (§8 [확정]): 하단 판정선 아래로 추락, 위험 장애물 접촉. 일반 건물·적 접촉은 감속일 뿐 사망이 아니다.
## 사망 판정은 다른 전환보다 먼저 본다 (§9.2 [MVP 제안] 우선순위).
## 재시작 (§4 R [MVP 제안], §13.2-16): 씬을 다시 불러와 위치·속도·와이어·돌진 타깃·적·점수를 모두 처음으로 되돌린다.
## 거리 점수는 '최대 도달 X' 기준 (§11 [MVP 제안]) — v0.1 은 표시만.
## 코스 클리어 (Phase 4): 살아서 결승선을 넘으면 세계를 멈추고 시간·거리·처치 수를 보여 준다. R 로 바로 다시 시작.
## 입력 처리는 함수(toggle_pause, restart, ...)로 나눠 두어 테스트와 이후 터치 UI 가 같은 경로를 쓴다.
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
	elif player.global_position.x >= course.get_finish_x():
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()
	elif event.is_action_pressed("restart"):
		restart()
	elif event.is_action_pressed("toggle_debug"):
		toggle_debug()
	elif event.is_action_pressed("toggle_overview"):
		toggle_overview()


func _process(_delta: float) -> void:
	if debug_visible:
		ui.set_debug_text(_debug_text())
	var combo_ratio := score.combo_time_left / score.tuning.combo_window
	ui.hud.show_values(get_score(), get_distance() / score.tuning.px_per_meter, score.combo,
			score.multiplier_for(score.combo), score.last_bonus, combo_ratio)


func toggle_pause() -> void:
	if game_over or finished:
		return
	get_tree().paused = not get_tree().paused
	ui.set_paused(get_tree().paused)


## 즉시 재시작 — 씬을 다시 불러와 모든 상태를 초기화한다. 게임 오버가 아니어도 동작한다.
func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


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
		"FALL   y > %.0f = game over" % course.get_fall_limit_y(),
		"CAM    y %.0f  (lowest %.0f)%s" % [camera.global_position.y, camera.get_lowest_y(),
				"  overview" if camera.overview else ""],
		"FPS    %d" % Engine.get_frames_per_second(),
	] + ([] if course.describe().is_empty() else ["COURSE %s" % course.describe()]))
