## v0.2-3 2차 — 천장(넘으면 게임 오버), 천장에 매달린 종유석 구조물, 위로 돌진한 뒤 솟는 기세 제한.
extends "res://tests/test_case.gd"

const ENDLESS_SCENE := preload("res://scenes/endless.tscn")
const ENDLESS_SCRIPT := preload("res://scripts/endless_course.gd")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const DEFAULT_MOVEMENT := preload("res://resources/default_movement.tres")


func test_flying_above_ceiling_is_game_over() -> void:
	var main := add_node(ENDLESS_SCENE.instantiate())
	await physics_frames(2)
	var course: EndlessCourse = main.get_node("Course")
	var player: PlayerController = main.get_node("Player")
	check(course.get_ceiling_y() < 0.0, "무한 코스에는 천장이 있음 (y %.0f)" % course.get_ceiling_y())
	player.global_position = Vector2(player.global_position.x, course.get_ceiling_y() - 10.0)
	await physics_frames(2)
	check(main.game_over and main.game_over_reason == "ceiling", "천장 위로 올라가면 게임 오버 (%s)" % main.game_over_reason)


func test_hanging_structures_hang_from_ceiling_with_band_at_bottom() -> void:
	var course: EndlessCourse = ENDLESS_SCRIPT.new()
	course.seed = 777
	add_node(course)
	var hanging := 0
	var after_enemy := 0
	var seen := {}
	for step in 300:
		course.update_course(step * 200.0)
		for building in course.get_buildings():
			var key := building.get_instance_id() * 1000 + building.serial
			if seen.has(key) or not building.aerial or building.get_rect().position.y > course.ceiling_y:
				continue
			seen[key] = true
			hanging += 1
			var band := building.get_attach_rect()
			check(is_equal_approx(band.end.y, building.get_rect().end.y) and band.size.y <= 60.5, "띠는 밑쪽 60px")
			check(building.get_rect().end.y >= 40.0 and building.get_rect().end.y <= 260.0, "밑면 높이 40~260")
	var history := course.history
	for i in range(1, history.size()):
		if history[i] == "B" and history[i - 1] == "E":
			after_enemy += 1
	check(hanging > 10, "종유석 구조물이 충분히 나옴 (%d 개)" % hanging)
	print("    종유석 %d 개 (적 뒤 건물 비트 %d 번 중)" % [hanging, after_enemy])


func test_upward_dash_does_not_launch_too_high() -> void:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.movement = DEFAULT_MOVEMENT.duplicate()
	player.position = Vector2(400000, 500)
	add_node(player)
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	enemy.position = Vector2(400150, 150)  # 오른쪽 위로 가파르게
	add_node(enemy)
	await physics_frames(2)
	player.dash.request_dash()
	check_eq(player.get_state_name(), "DASHING", "위쪽 적으로 돌진 (%s)" % player.dash.last_request)
	while player.state == PlayerController.State.DASHING:
		await physics_frames(1)
	check(player.velocity.y >= -player.dash_tuning.max_exit_up_speed - 0.5,
			"돌진이 끝날 때 위로 솟는 속도 ≤ %.0f (vy %.0f)" % [player.dash_tuning.max_exit_up_speed, player.velocity.y])
	var top := player.global_position.y
	for _i in 60:
		await physics_frames(1)
		top = minf(top, player.global_position.y)
	var end_y := enemy.global_position.y - player.dash_tuning.dash_end_offset
	check(top > end_y - 150.0, "돌진 끝에서 150px 넘게 더 솟지 않음 (최고 y %.0f)" % top)
