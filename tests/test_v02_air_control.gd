## v0.2-4 — 공중 좌우 조작 A/B (기획서 §4 [확정]: 방향키 없는 A안 우선, 좌우로 공중 속도를 미세 조정하는 B안 비교).
extends "res://tests/test_case.gd"

const MAIN_SCENE := preload("res://scenes/main.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const DEFAULT_MOVEMENT := preload("res://resources/default_movement.tres")


func after_each() -> void:
	PlayerController.air_control_override = -1  # 다른 테스트에 남지 않게


func test_mode_a_ignores_arrows() -> void:
	var player := _lab_player(Vector2(500000, 0), MovementTuning.AirControlMode.NONE)
	player.debug_air_input = 1.0
	await physics_frames(60)
	check_near(player.velocity.x, player.movement.auto_forward_speed, 0.5, "A안: 오른쪽을 눌러도 기본 전진 속도 그대로")
	check(InputMap.has_action("move_left") and InputMap.has_action("move_right"), "좌우 입력 액션이 있음 (A/D, 방향키)")
	PlayerController.air_control_override = -1


func test_mode_b_fine_tunes_forward_speed_without_stopping() -> void:
	var player := _lab_player(Vector2(510000, 0), MovementTuning.AirControlMode.FINE)
	var m := player.movement
	player.debug_air_input = 1.0
	await physics_frames(60)
	check_near(player.velocity.x, minf(m.auto_forward_speed + m.air_control_speed_offset, m.max_air_horizontal_speed), 0.5,
			"B안 오른쪽: 더 빠르게 (vx %.0f)" % player.velocity.x)
	player.debug_air_input = -1.0
	await physics_frames(90)
	check_near(player.velocity.x, maxf(m.auto_forward_speed - m.air_control_speed_offset, m.air_control_min_speed), 0.5,
			"B안 왼쪽: 느리게, 하지만 멈추거나 뒤로 가지 않음 (vx %.0f)" % player.velocity.x)
	check(player.velocity.x > 0.0, "자동 전진 유지")
	player.debug_air_input = 0.0
	await physics_frames(90)
	check_near(player.velocity.x, m.auto_forward_speed, 0.5, "손을 떼면 기본 전진 속도로 돌아감")
	PlayerController.air_control_override = -1


func test_toggle_switches_mode_and_survives_restart() -> void:
	tree.change_scene_to_packed(MAIN_SCENE)
	await physics_frames(2)
	var main: Node = tree.current_scene
	var player: PlayerController = main.get_node("Player")
	check_eq(player.get_air_control_mode(), MovementTuning.AirControlMode.NONE, "기본은 A안 (기획서 §4)")
	main.toggle_air_control()
	check_eq(player.get_air_control_mode(), MovementTuning.AirControlMode.FINE, "F2 → B안")
	check((main.get_node("GameUI/HintLabel") as Label).text.ends_with("B (A/D)"), "안내 줄에 현재 방식 표시")
	main.restart()
	await physics_frames(3)
	var fresh: PlayerController = tree.current_scene.get_node("Player")
	check_eq(fresh.get_air_control_mode(), MovementTuning.AirControlMode.FINE, "재시작해도 고른 방식 유지 (비교하기 편하게)")
	PlayerController.air_control_override = -1
	tree.current_scene.queue_free()
	tree.current_scene = null
	await physics_frames(1)


func _lab_player(pos: Vector2, mode: MovementTuning.AirControlMode) -> PlayerController:
	PlayerController.air_control_override = mode
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.movement = DEFAULT_MOVEMENT.duplicate()
	player.movement.gravity = 0.0
	player.position = pos
	player.velocity = Vector2(player.movement.auto_forward_speed, 0)
	add_node(player)
	return player
