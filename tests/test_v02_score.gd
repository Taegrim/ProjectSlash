## v0.2-2 — 거리 점수·콤보 (기획서 §11): 의미 있는 액션만 콤보, 시간 안 연속 성공 시 보너스, 연타로 못 올림, HUD 배치.
extends "res://tests/test_case.gd"

const MAIN_SCENE := preload("res://scenes/main.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const BUILDING_SCENE := preload("res://scenes/building.tscn")
const DEFAULT_MOVEMENT := preload("res://resources/default_movement.tres")
const DEFAULT_SCORE := preload("res://resources/default_score.tres")


func test_only_meaningful_actions_build_combo() -> void:
	# v0.2-2 리뷰 2번: 와이어는 건물에 연결할 때 세되, 같은 건물에는 한 번만
	var player := _lab_player(Vector2(300000, 0))
	var score := _keeper(player)
	var first: Building = add_node(BUILDING_SCENE.instantiate())
	var second: Building = add_node(BUILDING_SCENE.instantiate())
	player.grapple.released.emit(true)
	check_eq(score.combo, 0, "와이어 해제 자체는 세지 않음 (건물 연결로 센다)")
	player.grapple.attached.emit(Vector2.ZERO, first)
	check_eq(score.combo, 1, "새 건물에 와이어 연결 = 콤보 1")
	check_eq(score.combo_points, 0, "콤보 1 에는 보너스 없음 (연속 성공부터)")
	player.grapple.attached.emit(Vector2.ZERO, first)
	player.grapple.attached.emit(Vector2.ZERO, first)
	check_eq(score.combo, 1, "같은 건물에 다시 걸어도(걸었다 놓기 반복·연타) 오르지 않음")
	player.grapple.attached.emit(Vector2.ZERO, second)
	check_eq(score.combo, 2, "다른 건물에 연결 → 콤보 2")
	check_eq(score.last_bonus, DEFAULT_SCORE.combo_base_points, "콤보 2 보너스 = 기본 점수")
	player.dash.dash_hit.emit(null)
	check_eq(score.combo, 3, "돌진 처치 → 콤보 3")
	check(score.last_bonus > DEFAULT_SCORE.combo_base_points, "콤보가 늘수록 보너스 배율 증가 (%d)" % score.last_bonus)
	first.set_pooled(false)
	first.set_pooled(true)  # 무한 코스 풀에서 다시 배치된 건물 = 새 건물
	player.grapple.attached.emit(Vector2.ZERO, first)
	check_eq(score.combo, 4, "풀에서 다시 배치된 건물은 새 건물로 셈")


func test_combo_breaks_after_window_and_on_death() -> void:
	var player := _lab_player(Vector2(310000, 0))
	var score := _keeper(player)
	player.dash.dash_hit.emit(null)
	player.dash.dash_hit.emit(null)
	check_eq(score.combo, 2, "준비: 콤보 2")
	await physics_frames(int(DEFAULT_SCORE.combo_window * 60.0) + 2)
	check_eq(score.combo, 0, "콤보 시간(%.1f초)이 지나면 끊김" % DEFAULT_SCORE.combo_window)
	var kept := score.combo_points
	player.dash.dash_hit.emit(null)
	check_eq(score.combo, 1, "끊긴 뒤에는 다시 1 부터")
	check_eq(score.combo_points, kept, "이미 얻은 보너스는 유지")
	player.dash.dash_hit.emit(null)
	check_eq(score.combo, 2, "준비: 다시 콤보 2")
	player.bumped.emit(null)
	check_eq(score.combo, 0, "몸 충돌하면 콤보 끊김 (리뷰 3번)")
	player.dash.dash_hit.emit(null)
	player.die("fall")
	check_eq(score.combo, 0, "사망하면 콤보 끊김")


func test_score_is_distance_plus_combo_bonus_in_game() -> void:
	var main := add_node(MAIN_SCENE.instantiate())
	await physics_frames(60)
	var distance: float = main.get_distance()
	check_eq(main.get_score(), int(distance * DEFAULT_SCORE.points_per_px), "콤보가 없으면 점수 = 거리 점수")
	main.score.combo_points = 500
	check_eq(main.get_score(), int(distance * DEFAULT_SCORE.points_per_px) + 500, "총점 = 거리 점수 + 콤보 보너스")
	(main.get_node("Player") as PlayerController).die("fall")
	var text: String = (main.get_node("GameUI/GameOverLabel") as Label).text
	check(text.contains("score"), "게임 오버 화면에 점수 표시 (%s)" % text.replace("\n", " / "))


func test_hud_layouts_stay_on_screen() -> void:
	var main := add_node(MAIN_SCENE.instantiate())
	await physics_frames(2)
	var hud: ScoreHUD = (main.get_node("GameUI") as GameUI).hud
	var view := hud.get_viewport_rect()  # 헤드리스 뷰포트는 실제 창과 크기가 달라 실제 뷰포트 기준으로 본다
	for layout in ScoreHUD.Layout.values():
		hud.apply_layout(layout)
		hud.show_values(123456, 1234.0, 3, 1.5, 150, 0.6)
		await physics_frames(2)
		var rect := hud.get_box_rect()
		check(view.encloses(rect), "%s 배치가 화면 안 (%s)" % [ScoreHUD.Layout.keys()[layout], rect])


func _keeper(player: PlayerController) -> ScoreKeeper:
	var score := ScoreKeeper.new()
	add_node(score)
	score.setup(player, DEFAULT_SCORE)
	return score


func _lab_player(pos: Vector2) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.movement = DEFAULT_MOVEMENT.duplicate()
	player.movement.gravity = 0.0
	player.position = pos
	add_node(player)
	return player
