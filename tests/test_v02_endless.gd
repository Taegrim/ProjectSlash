## v0.2 작업 1 — 패턴 무한 코스: 배치 규칙(번갈아, 같은 종류 장기 연속 금지), 오브젝트 풀링, 통과 가능성(자동 조작 봇).
extends "res://tests/test_case.gd"

const ENDLESS_SCENE := preload("res://scenes/endless.tscn")
const ENDLESS_SCRIPT := preload("res://scripts/endless_course.gd")
## 봇 통과 가능성 확인에 쓰는 시드들과 시드당 최대 시간 (프레임).
## v0.2-3 에서 8개 → 16개: 8개로는 운에 따라 결과가 크게 흔들렸다 (위험 장애물 추가 후 같은 설정이 4/8 ~ 14/16)
const BOT_SEEDS := [101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116]
const BOT_FRAMES := 3600


func test_pattern_alternates_without_long_runs() -> void:
	var course := _bare_course(1234)
	for step in 300:
		course.update_course(step * 200.0)
	var history := course.history
	var longest := 1
	var run := 1
	var switches := 0
	for i in range(1, history.size()):
		if history[i] == history[i - 1]:
			run += 1
		else:
			run = 1
			switches += 1
		longest = maxi(longest, run)
	var ratio := float(switches) / float(history.size() - 1)
	check(history.size() > 100, "비트를 충분히 만듦 (%d)" % history.size())
	check(longest <= course.max_same_kind, "같은 종류는 최대 %d 번까지만 연속 (가장 긴 연속 %d)" % [course.max_same_kind, longest])
	check(ratio > 0.6, "대부분 번갈아 나옴 (종류가 바뀐 비율 %.0f%%)" % (ratio * 100.0))
	check(history.has("B") and history.has("E"), "건물과 적이 모두 나옴")
	print("    비트 %d 개, 가장 긴 연속 %d, 전환 비율 %.0f%%: %s…" % [history.size(), longest, ratio * 100.0,
			"".join(history.slice(0, 40))])


func test_pooling_reuses_objects_without_creating_or_freeing() -> void:
	var course := _bare_course(99)
	await physics_frames(1)
	var children := course.get_child_count()
	var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	for step in 300:
		course.update_course(step * 200.0)  # 60000px 진행
	await physics_frames(1)
	check_eq(course.pool_misses, 0, "풀이 모자라 새로 만든 적 없음")
	check_eq(course.get_child_count(), children, "코스의 자식 노드 수 그대로 (생성·삭제 없음)")
	check_eq(Performance.get_monitor(Performance.OBJECT_NODE_COUNT), nodes, "전체 노드 수 그대로")
	var active := course.get_buildings().size() + course.get_enemies().size()
	check(active > 3 and active < course.building_pool + course.enemy_pool, "앞쪽 구간만 활성 (%d 개)" % active)
	for building in course.get_buildings():
		check(building.get_rect().end.x >= 299 * 200.0 - course.recycle_behind, "지나간 건물은 회수됨")


func test_bot_survives_long_runs_on_most_seeds() -> void:
	# §10.3 '적어도 하나의 반복 가능한 통과 경로': 단순한 봇이 여러 시드에서 오래 살아남는지 본다
	var distances: Array[float] = []
	var deaths := {}
	for seed in BOT_SEEDS:
		var result := await _run_bot(seed, BOT_FRAMES)
		distances.append(result.distance)
		if result.reason != "":
			deaths[result.reason] = deaths.get(result.reason, 0) + 1
	var sorted := distances.duplicate()
	sorted.sort()
	var median: float = sorted[sorted.size() / 2]
	print("    봇 생존 거리(px): %s  중앙값 %.0f  사망 원인 %s" % [", ".join(distances.map(func(d: float) -> String:
			return "%.0f" % d)), median, deaths])
	var long_runs := distances.filter(func(d: float) -> bool: return d > 8000.0).size()
	check(median > 15000.0, "중앙값 15000px 넘게 진행 (%.0f)" % median)
	check(long_runs >= 12, "16개 시드 중 12개 이상이 8000px 넘게 진행 (%d 개)" % long_runs)


## 자식 없이 코스만 (게임 흐름 없이 생성·회수만 확인)
func _bare_course(seed: int) -> EndlessCourse:
	var course: EndlessCourse = ENDLESS_SCRIPT.new()
	course.seed = seed
	add_node(course)
	return course


func _run_bot(seed: int, frames: int) -> Dictionary:
	var main: Node = ENDLESS_SCENE.instantiate()
	(main.get_node("Course") as EndlessCourse).seed = seed
	add_node(main)
	var player: PlayerController = main.get_node("Player")
	var bot := CourseBot.new()
	bot.setup(player, main.get_node("Course"))
	for f in frames:
		bot.step()
		await physics_frames(1)
		if main.game_over:
			break
	var result := {"distance": main.get_distance(), "reason": main.game_over_reason if main.game_over else ""}
	bot.free()  # 트리에 넣지 않은 노드라 직접 지운다 (안 지우면 종료 때 '누수' 경고)
	main.queue_free()
	await physics_frames(1)
	return result
