## Phase 4 — 코스 완성·반복 플레이: 결승선, 클리어 표시, 클리어 뒤 즉시 재시작 (기획서 Phase 4 완료 기준).
## 웹 빌드 실행 확인은 tools/web_build.py --check (브라우저가 필요해 이 러너 밖에서 한다).
extends "res://tests/test_case.gd"

const MAIN_SCENE := preload("res://scenes/main.tscn")
## A·B 를 와이어로 넘는 탐색 조합 (Phase 2), 이후 타깃이 잡히면 바로 돌진(C, D),
## D 돌진이 끝나고 88 프레임 뒤(E 를 지나 내려올 때) 공중 구조물 F 밑면에 걸어 50 프레임 뒤 해제 → 위험 구간을 넘어 결승선
const PLAN := {62: Vector2(626, 430), 112: null, 146: Vector2(1186, 200), 176: null}
const F_DELAY := 88
const F_HOLD := 50


func test_finish_line_is_after_the_hazard_and_inside_bounds() -> void:
	var main := add_node(MAIN_SCENE.instantiate())
	await physics_frames(1)
	var course: TestCourse = main.get_node("TestCourse")
	for hazard in course.get_hazards():
		check(course.finish_x > hazard.get_rect().end.x, "결승선은 위험 구간 뒤")
	for building in course.get_buildings():
		check(course.finish_x > building.get_rect().end.x, "결승선은 모든 건물 뒤")
	check(course.get_bounds().has_point(Vector2(course.finish_x, course.get_spawn_position().y)), "코스 전체 보기에 결승선이 들어감")


func test_full_course_reaches_finish_and_restarts_instantly() -> void:
	tree.change_scene_to_packed(MAIN_SCENE)
	await physics_frames(2)
	var main: Node = tree.current_scene
	var player: PlayerController = main.get_node("Player")
	var f_rect: Rect2 = (main.get_node("TestCourse/AerialF") as Building).get_attach_rect()
	var aim_f := Vector2(f_rect.get_center().x, f_rect.end.y)
	var dash_end := -1
	for f in 1200:
		if PLAN.has(f):
			if PLAN[f] == null:
				player.grapple.request_release()
			else:
				player.grapple.request_attach(PLAN[f])
		if f > 176 and player.state == PlayerController.State.AIRBORNE and player.dash.find_target().enemy != null:
			player.dash.request_dash()
		if dash_end < 0 and player.dash.kill_count == 2 and player.state == PlayerController.State.AIRBORNE:
			dash_end = f
		if dash_end >= 0 and f == dash_end + F_DELAY:
			player.grapple.request_attach(aim_f)
			check(player.grapple.is_attached and player.grapple.swing_dir == -1,
					"F 에 연결, 반시계 (%s)" % player.grapple.last_request)
		if dash_end >= 0 and f == dash_end + F_DELAY + F_HOLD:
			player.grapple.request_release()
		await physics_frames(1)
		if main.finished or main.game_over:
			break
	check(main.finished, "결승선 도달 (끝 위치 %s, %s)" % [player.global_position.round(), main.game_over_reason])
	check(not main.game_over, "죽지 않고 클리어")
	check(tree.paused, "클리어하면 세계가 멈춤")
	check((main.get_node("GameUI") as GameUI).is_game_over_visible(), "클리어 표시")
	check(main.elapsed > 3.0 and main.elapsed < 20.0, "플레이 시간 기록 (%.1f s)" % main.elapsed)
	check_eq(player.dash.kill_count, 2, "C·D 처치 수 기록")
	var frozen_x := player.global_position.x
	await physics_frames(10)
	check_near(player.global_position.x, frozen_x, 0.01, "클리어 뒤 플레이어 정지")
	main.toggle_pause()
	check(tree.paused, "클리어 화면에서는 ESC 로 풀리지 않음")
	main.restart()  # R 과 같은 경로
	await physics_frames(3)
	var fresh: Node = tree.current_scene
	check(fresh != main and not fresh.finished and not tree.paused, "R 로 즉시 처음부터 다시 시작")
	check(fresh.elapsed < 0.2, "시간 초기화")
	tree.paused = false
	tree.current_scene.queue_free()
	tree.current_scene = null
	await physics_frames(1)
