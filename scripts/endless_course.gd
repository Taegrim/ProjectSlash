## 패턴 무한 코스 (v0.2 작업 1) — 비트(건물 / 적)를 이어 붙여 앞쪽을 계속 만들고, 지나간 것은 회수해 다시 쓴다.
##
## 배치 규칙 (사용자 결정 2026-11-06, 기획서 §10.1 의 '건물→건물→적→적→건물'은 예시):
##   건물과 적이 최대한 번갈아 나오되 연달아 나와도 된다. 같은 종류가 길게(6~7번) 이어지지만 않으면 된다
##   → 매 비트 switch_chance 확률로 종류를 바꾸고, 같은 종류는 max_same_kind 번까지만 잇는다.
## 비트 종류:
##   건물 비트 — 솟은 건물 1채, 또는 (aerial_chance, 솟은 건물 바로 뒤일 때만) 위험 구역 위 공중 구조물
##   적 비트   — 적 1~2명 (2명이면 연속 돌진)
## 통과 가능성 (§10.3): 높이·간격은 직전 비트의 높이(lane)를 기준으로 좁은 범위에서만 고른다. 자동 조작 봇으로 여러 시드를 돌려
##   얼마나 오래 살아남는지 확인한다 (tests/test_v02_endless.gd, tests/course_bot.gd).
## 오브젝트 풀링: 건물·적·위험 구역을 시작할 때 미리 만들어 두고, 플레이 중에는 위치·크기만 바꿔 다시 쓴다 (생성·삭제 없음).
##   플레이어보다 recycle_behind 이상 뒤로 지나간 것은 숨기고 충돌을 꺼 풀로 돌려보낸다.
class_name EndlessCourse
extends CourseBase

const BUILDING_SCENE := preload("res://scenes/building.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const HAZARD_SCENE := preload("res://scenes/hazard.tscn")
## 솟은 건물이 내려가는 바닥 (판정선 아래)
const GROUND_Y := 1100.0
## 풀에 둔 물체를 치워 두는 곳
const PARKING := Vector2(-100000, -100000)
const FALL_LINE_COLOR := Color(1.0, 0.3, 0.3, 0.8)
## 공중 구조물 밑면에서 위험 구역 윗면까지 최소 거리. 멀리서(약 380px) 걸면 로프를 다 감기 전에 원이 그만큼 깊이 내려가므로
## 최대 스윙 반지름(220)이 아니라 걸 수 있는 거리 + 여유로 잡는다 (v0.2-3 2차: 260 이면 먼 연결에서 위험 구역에 닿음)
const SAFE_SWING_DEPTH := 400.0

@export var spawn := Vector2(200, 280)
@export var fall_limit_y := 1000.0
## 천장 (월드 Y): 이보다 위로 올라가면 게임 오버. 종유석 구조물이 여기에 매달린다 (v0.2-3 리뷰)
@export var ceiling_y := -220.0
## 0 이면 실행마다 무작위 (디버그 표시의 COURSE 줄에 실제 시드가 나온다)
@export var seed := 0
@export_group("배치 규칙")
## 같은 종류(건물/적) 비트를 최대 몇 번까지 잇는가
@export var max_same_kind := 3
## 매 비트 종류를 바꿀 확률
@export_range(0.0, 1.0) var switch_chance := 0.7
## 건물 비트가 '위험 구역 위 공중 구조물'일 확률
@export_range(0.0, 1.0) var aerial_chance := 0.25
## 건물 비트가 '천장에 매달린 종유석 구조물'일 확률 (높이 날 때 걸 곳, 밑에서 걸어 반시계로 돈다)
@export_range(0.0, 1.0) var hanging_chance := 0.3
## 바로 앞이 적 비트일 때의 종유석 확률 — 돌진 뒤에는 높이 떠 있어 솟은 건물에 걸기 어렵다
@export_range(0.0, 1.0) var hanging_after_enemy_chance := 0.6
## 적 비트에 적이 2명 나올 확률
@export_range(0.0, 1.0) var double_enemy_chance := 0.4
## 솟은 건물 지붕에 가시가 깔릴 확률 (그 지붕에 내려앉으면 사망, v0.2-3)
@export_range(0.0, 1.0) var roof_spike_chance := 0.2
## 솟은 건물 앞 틈에 위아래로 움직이는 위험 기둥이 설 확률 (v0.2-3)
@export_range(0.0, 1.0) var gap_pillar_chance := 0.2
## 새 위험 장애물은 이만큼의 비트가 지난 뒤부터 (처음엔 익숙해질 시간)
@export var hazard_free_beats := 4
@export_group("풀")
## 플레이어 앞쪽으로 미리 만들어 두는 거리 (px)
@export var look_ahead := 2600.0
## 플레이어보다 이만큼 뒤로 지나가면 회수 (px)
@export var recycle_behind := 1000.0
@export var building_pool := 14
@export var enemy_pool := 14
@export var hazard_pool := 10

var rng := RandomNumberGenerator.new()
## 만든 비트 종류 기록 ("B" 건물, "E" 적) — 테스트·디버그용
var history := PackedStringArray()
## 풀이 모자라 새로 만든 횟수 (0 이어야 정상 — 테스트가 확인)
var pool_misses := 0

var _buildings: Array[Building] = []
var _enemies: Array[Enemy] = []
var _hazards: Array[Hazard] = []
var _free := {"B": [], "E": [], "H": []}
var _active: Array[Node2D] = []
var _cursor_x := 0.0
var _lane_y := 420.0
var _run_kind := ""
var _run_length := 0
var _last_aerial := false


func _ready() -> void:
	if seed == 0 and OS.get_environment("COURSE_SEED") != "":
		seed = int(OS.get_environment("COURSE_SEED"))  # 개발용: 같은 코스를 다시 보기 (캡처·디버그)
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()
		seed = rng.seed
	for i in building_pool:
		_buildings.append(_add_to_pool(BUILDING_SCENE.instantiate(), "B"))
	for i in enemy_pool:
		_enemies.append(_add_to_pool(ENEMY_SCENE.instantiate(), "E"))
	for i in hazard_pool:
		_hazards.append(_add_to_pool(HAZARD_SCENE.instantiate(), "H"))
	# 첫 비트는 튜토리얼 건물 (테스트 코스의 A 와 같은 자리·높이)
	_place_building(Vector2(620, 420), 220.0, 70.0)
	_cursor_x = 840.0
	_lane_y = 420.0
	_count("B")
	update_course(spawn.x)


func get_spawn_position() -> Vector2:
	return spawn


func get_fall_limit_y() -> float:
	return fall_limit_y


func get_ceiling_y() -> float:
	return ceiling_y


func get_buildings() -> Array[Building]:
	var result: Array[Building] = []
	for node in _active:
		if node is Building:
			result.append(node)
	return result


func get_enemies() -> Array[Enemy]:
	var result: Array[Enemy] = []
	for node in _active:
		if node is Enemy:
			result.append(node)
	return result


func get_hazards() -> Array[Hazard]:
	return _hazards.duplicate()


## 지금 만들어져 있는 구간만 (출발점까지 넣으면 달릴수록 화면이 한없이 작아진다)
func get_bounds() -> Rect2:
	if _active.is_empty():
		return Rect2(spawn, Vector2.ONE)
	var bounds := _rect_of(_active[0])
	for node in _active:
		bounds = bounds.merge(_rect_of(node))
	return bounds.expand(Vector2(bounds.position.x, fall_limit_y)).grow(80.0)


func update_course(player_x: float) -> void:
	while _cursor_x < player_x + look_ahead:
		_spawn_beat()
	for i in range(_active.size() - 1, -1, -1):
		var node := _active[i]
		if _rect_of(node).end.x < player_x - recycle_behind:
			_active.remove_at(i)
			_release(node)


func describe() -> String:
	return "endless seed %d  beats %d  pool B %d/%d E %d/%d H %d/%d" % [seed, history.size(),
			_buildings.size() - _free.B.size(), _buildings.size(), _enemies.size() - _free.E.size(), _enemies.size(),
			_hazards.size() - _free.H.size(), _hazards.size()]


# --- 비트 생성 ---

func _spawn_beat() -> void:
	var kind := _next_kind()
	if kind == "B":
		# 공중 구조물(+위험 구역)은 솟은 건물 바로 뒤에만: 건물에서 위로 튀어 오른 높이로 들어가야 걸 수 있다.
		# 적 뒤에 두면 아래쪽 적을 벤 돌진이 플레이어를 아래로 보내 위험 구역에 바로 떨어진다 (봇 탐색에서 확인)
		var after_rising := _run_kind == "B" and not _last_aerial and history.size() > 1
		var hang_chance := hanging_after_enemy_chance if _run_kind == "E" else hanging_chance
		if history.size() > 1 and rng.randf() < hang_chance:
			_hanging_beat()
		elif after_rising and rng.randf() < aerial_chance:
			_aerial_beat()
		else:
			_building_beat()
	else:
		_enemy_beat()
	_count(kind)
	queue_redraw()


func _next_kind() -> String:
	var other := "E" if _run_kind == "B" else "B"
	if _run_length >= max_same_kind or rng.randf() < switch_chance:
		return other
	return _run_kind


func _count(kind: String) -> void:
	history.append(kind)
	_run_length = _run_length + 1 if kind == _run_kind else 1
	_run_kind = kind


## 솟은 건물: 직전 높이 근처의 지붕, 공중에서 닿을 만한 간격
func _building_beat() -> void:
	var gap := rng.randf_range(260.0, 380.0)
	var x := _cursor_x + gap
	var roof := clampf(_lane_y + rng.randf_range(-90.0, 70.0), 300.0, 470.0)
	var width := rng.randf_range(200.0, 260.0)
	_place_building(Vector2(x, roof), width, rng.randf_range(70.0, 120.0))
	var hazards_allowed := history.size() >= hazard_free_beats
	if hazards_allowed and rng.randf() < gap_pillar_chance:
		# 틈의 위험 기둥: 꼭대기가 띠 아래(지붕 +120 ~ +280)에서 오르내린다 — 띠에 걸고 넘어가면 닿지 않는 높이
		var pillar: Hazard = _take("H")
		pillar.size = Vector2(40.0, 700.0)
		pillar.position = Vector2(x - gap * 0.5 - 20.0, roof + 200.0)
		pillar.set_pooled(true)
		pillar.start_bob(80.0, rng.randf_range(1.8, 2.8), rng.randf_range(0.0, 2.0))
		_active.append(pillar)
	if hazards_allowed and rng.randf() < roof_spike_chance:
		# 지붕 가시: 왼쪽 30px 는 비워 둔다 (벽 띠를 노리는 조준선을 가리지 않게)
		var spikes: Hazard = _take("H")
		spikes.style = 1
		spikes.size = Vector2(width - 40.0, 14.0)
		spikes.position = Vector2(x + 30.0, roof - 14.0)
		spikes.set_pooled(true)
		_active.append(spikes)
	_cursor_x = x + width
	_lane_y = roof
	_last_aerial = false


## 천장에 매달린 종유석 구조물: 밑쪽 60px 만 띠. 밑에서 걸어 반시계로 돌며 넘는다 (돌진 뒤 높이 떠 있을 때 걸 곳)
func _hanging_beat() -> void:
	var x := _cursor_x + rng.randf_range(240.0, 360.0)
	var bottom := clampf(_lane_y - rng.randf_range(150.0, 250.0), 40.0, 260.0)
	var width := rng.randf_range(120.0, 180.0)
	var top := ceiling_y - 300.0  # 천장 위 화면 밖까지 이어지게
	var hanging := _place_building(Vector2(x, top), width, 60.0, true)
	hanging.size = Vector2(width, bottom - top)
	hanging.attach_band_top = hanging.size.y - 60.0
	hanging.attach_band_depth = 60.0
	_cursor_x = x + width
	_lane_y = clampf(bottom + 180.0, 300.0, 470.0)
	_last_aerial = false


## 위험 구역 위 공중 구조물: 밑면에 걸어 반시계로 건넌다
func _aerial_beat() -> void:
	var x := _cursor_x + rng.randf_range(240.0, 320.0)
	var y := clampf(_lane_y - rng.randf_range(120.0, 200.0), 160.0, 300.0)
	_place_building(Vector2(x, y), 220.0, 30.0, true)
	# 위험 구역 윗면은 '밑면 + 최대 스윙 반지름 + 여유' 아래: 제대로 건 진자는 위험 구역에 닿지 않는다
	var hazard_top := clampf(y + 30.0 + SAFE_SWING_DEPTH, 560.0, 820.0)
	var hazard: Hazard = _take("H")
	hazard.position = Vector2(x - 60.0, hazard_top)
	hazard.size = Vector2(340.0, GROUND_Y - hazard_top)
	hazard.set_pooled(true)
	_active.append(hazard)
	_cursor_x = x + 320.0
	_lane_y = 420.0
	_last_aerial = true


## 적 1~2명: 직전 높이보다 조금 위, 돌진 사거리 안 간격
func _enemy_beat() -> void:
	var count := 2 if rng.randf() < double_enemy_chance else 1
	var x := _cursor_x + rng.randf_range(280.0, 400.0)
	var y := clampf(_lane_y - rng.randf_range(40.0, 160.0), 180.0, 420.0)
	for i in count:
		var enemy: Enemy = _take("E")
		enemy.position = Vector2(x, y)
		enemy.debug_label = ""
		enemy.set_pooled(true)
		_active.append(enemy)
		_cursor_x = x
		x += rng.randf_range(260.0, 360.0)
		y = clampf(y + rng.randf_range(-90.0, 60.0), 180.0, 420.0)
	_lane_y = clampf(y + 120.0, 300.0, 470.0)
	_last_aerial = false


# --- 풀 ---

func _add_to_pool(node: Node2D, kind: String) -> Node2D:
	node.position = PARKING
	add_child(node)
	node.call("set_pooled", false)
	_free[kind].append(node)
	return node


func _take(kind: String) -> Node2D:
	if _free[kind].is_empty():
		# 풀이 모자람: 어쩔 수 없이 하나 더 만든다 (테스트가 0 인지 확인). 위험 구역이면 사망 신호도 연결
		pool_misses += 1
		var scene: PackedScene = {"B": BUILDING_SCENE, "E": ENEMY_SCENE, "H": HAZARD_SCENE}[kind]
		var extra := _add_to_pool(scene.instantiate(), kind)
		if extra is Building:
			_buildings.append(extra)
		elif extra is Enemy:
			_enemies.append(extra)
		else:
			_hazards.append(extra)
			if get_parent() and get_parent().has_method("watch_hazard"):
				get_parent().call("watch_hazard", extra)
	return _free[kind].pop_back()


func _release(node: Node2D) -> void:
	node.call("set_pooled", false)
	node.position = PARKING
	var kind := "B" if node is Building else ("E" if node is Enemy else "H")
	_free[kind].append(node)


func _place_building(roof_left: Vector2, width: float, band: float, aerial := false) -> Building:
	var building: Building = _take("B")
	building.aerial = aerial
	building.attach_band_top = 0.0
	building.attach_band_depth = band
	building.size = Vector2(width, band) if aerial else Vector2(width, GROUND_Y - roof_left.y)
	building.position = roof_left
	building.debug_label = ""
	building.set_pooled(true)
	_active.append(building)
	return building


func _rect_of(node: Node2D) -> Rect2:
	if node is Enemy:
		var radius: float = (node as Enemy).radius
		return Rect2(node.global_position - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
	return node.call("get_rect")


func _draw() -> void:
	draw_dashed_line(Vector2(-400.0, fall_limit_y), Vector2(_cursor_x + 400.0, fall_limit_y), FALL_LINE_COLOR, 3.0, 18.0)
	draw_dashed_line(Vector2(-400.0, ceiling_y), Vector2(_cursor_x + 400.0, ceiling_y), FALL_LINE_COLOR, 3.0, 18.0)
	draw_string(ThemeDB.fallback_font, Vector2(spawn.x, ceiling_y + 22), "CEILING (game over above)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, FALL_LINE_COLOR)
	draw_string(ThemeDB.fallback_font, Vector2(spawn.x, fall_limit_y - 10), "FALL LIMIT (game over below)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, FALL_LINE_COLOR)
