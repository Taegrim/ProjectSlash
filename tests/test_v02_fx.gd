## v0.2-3 — 시각 효과·효과음 연결, 새 위험 장애물(지붕 가시·움직이는 기둥)과 풀링.
extends "res://tests/test_case.gd"

const MAIN_SCENE := preload("res://scenes/main.tscn")
const ENDLESS_SCRIPT := preload("res://scripts/endless_course.gd")


func test_actions_trigger_sounds_and_effects() -> void:
	var main := add_node(MAIN_SCENE.instantiate())
	await physics_frames(2)
	var player: PlayerController = main.get_node("Player")
	var sfx: SFX = main.sfx
	for sound in SFX.NAMES:
		check(ResourceLoader.exists("res://assets/sfx/%s.wav" % sound), "효과음 파일 있음: %s" % sound)
	player.grapple.request_attach(Vector2(626, 430))
	await physics_frames(60)
	player.grapple.request_attach(Vector2(626, 430))
	check(sfx.played.get("wire_attach", 0) >= 1 or not player.grapple.is_attached, "와이어 연결 소리")
	var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	player.dash.dash_started.emit(null)
	player.dash.dash_hit.emit((main.get_node("TestCourse") as TestCourse).get_enemies()[0])
	player.dash.dash_ended.emit("arrived")
	await physics_frames(2)
	check_eq(sfx.played.get("dash", 0), 1, "돌진 소리")
	check_eq(sfx.played.get("slash", 0), 1, "베기 소리")
	check_eq(Performance.get_monitor(Performance.OBJECT_NODE_COUNT), nodes, "효과는 미리 만든 노드를 다시 씀 (노드 수 그대로)")
	player.die("fall")
	check_eq(sfx.last_played, "death", "사망 소리")
	check_eq(Engine.time_scale, 1.0, "헤드리스에서는 히트스톱 없음 (테스트 시간 흐름 유지)")


func test_new_hazards_appear_and_are_pooled() -> void:
	var course: EndlessCourse = ENDLESS_SCRIPT.new()
	course.seed = 4242
	add_node(course)
	var spikes := 0
	var pillars := 0
	var seen := {}
	for step in 300:
		course.update_course(step * 200.0)
		for hazard in course.get_hazards():
			if hazard.visible and not seen.has(hazard.get_instance_id() * 100000 + int(hazard.position.x)):
				seen[hazard.get_instance_id() * 100000 + int(hazard.position.x)] = true
				if hazard.style == 1:
					spikes += 1
				elif hazard.bob_amplitude > 0.0:
					pillars += 1
	check(spikes > 3, "지붕 가시가 나옴 (%d)" % spikes)
	check(pillars > 3, "움직이는 기둥이 나옴 (%d)" % pillars)
	check_eq(course.pool_misses, 0, "위험 장애물 풀도 모자라지 않음")
