## 분석 (v0.2-4 리뷰 3번): 좌클릭 와이어 / 우클릭 돌진을 버튼 하나로 합치면 문제가 생길 상황이 얼마나 자주 오는지.
## 합친 규칙 후보: "누르는 순간 돌진할 적이 있으면 돌진, 없으면 와이어". 게임은 바꾸지 않고 자동 조작 봇으로 무한 코스를 돌며 센다.
##   godot --headless --path . --fixed-fps 60 -s res://tests/analysis_one_button.gd
## 세는 것: 체공 중 '와이어도 돌진도 가능'한 프레임 비율(합치면 와이어를 고를 수 없는 순간), 와이어 중 돌진 전환 횟수
## (합치면 놓기 = 해제 도약이 먼저 일어남), 우선순위를 와이어 쪽으로 바꾼 봇의 생존 거리 비교.
extends SceneTree

const S := preload("res://scenes/endless.tscn")
const SEEDS := [101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for cfg in [[false, 0], [false, 12], [true, 12]]:
		var prefer_wire: bool = cfg[0]
		var stats := {"dashes": 0, "conversions": 0, "attaches": 0}
		var both := 0
		var dash_only := 0
		var wire_only := 0
		var distances: Array = []
		for seed in SEEDS:
			var main: Node = S.instantiate()
			(main.get_node("Course") as EndlessCourse).seed = seed
			root.add_child(main)
			var p: PlayerController = main.get_node("Player")
			var bot := CourseBot.new()
			bot.setup(p, main.get_node("Course"))
			bot.prefer_wire = prefer_wire
			bot.reaction_frames = cfg[1]
			p.dash.dash_started.connect(func(_e: Enemy) -> void:
				stats.dashes += 1
				if p.grapple.is_attached:
					stats.conversions += 1)
			p.grapple.attached.connect(func(_a: Vector2, _b: Building) -> void: stats.attaches += 1)
			for f in 3600:
				if p.state == PlayerController.State.AIRBORNE:
					var can_dash := p.dash.find_target().enemy != null
					var can_wire := bot.find_anchor() != null
					if can_dash and can_wire:
						both += 1
					elif can_dash:
						dash_only += 1
					elif can_wire:
						wire_only += 1
				bot.step()
				await physics_frame
				await process_frame
				if main.game_over:
					break
			distances.append(int(main.get_distance()))
			bot.free()  # 트리에 넣지 않은 노드라 직접 지운다
			main.queue_free()
			await process_frame
		distances.sort()
		var any := both + dash_only + wire_only
		print("%s: 체공 중 선택 가능 프레임 %d — 둘 다 %d (%.0f%%), 돌진만 %d, 와이어만 %d | 와이어→돌진 전환 %d / 돌진 %d, 연결 %d | 생존 중앙값 %d, 8000px 이상 %d/16" % [
				("와이어 우선" if prefer_wire else "돌진 우선(합친 규칙)") + " 반응 %d프레임" % cfg[1], any, both,
				100.0 * both / maxf(any, 1), dash_only, wire_only, stats.conversions, stats.dashes, stats.attaches, distances[8],
				distances.filter(func(d: int) -> bool: return d > 8000).size()])
	quit(0)
