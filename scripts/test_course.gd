## 수동 배치 테스트 코스 (기획서 §10). v0.1 은 무한 생성이 아니라 짧은 고정 코스다.
## 배치 순서 (§10.1 [확정] 건물 → 건물 → 적 → 적 → 건물, §10.2 사례):
##   A 튜토리얼 건물 → B 높은 건물(낮은 연결) → C 적 → D 적 → E 건물 → 위험 구간 위 공중 구조물 F → 결승선 (Phase 4)
## 좌표·크기는 [튜닝] 임시값이다. Phase 1~2 에서 통과 가능성(§10.3)을 확인하며 조정한다.
@tool
class_name TestCourse
extends Node2D

const FALL_LINE_COLOR := Color(1.0, 0.3, 0.3, 0.8)
const FINISH_COLOR := Color(0.45, 1.0, 0.55, 0.85)

## 하단 사망 판정선 (월드 Y). 카메라와 별개인 독립 판정선 (§3 [필수 주의]). 판정은 Phase 1.
## 코스(패턴)마다 다를 수 있어 튜닝 Resource 가 아니라 코스 데이터에 둔다.
@export var fall_limit_y := 1000.0:
	set(value):
		fall_limit_y = value
		queue_redraw()
## 결승선 (월드 X). 살아서 이 선을 넘으면 코스 클리어 (Phase 4: 반복 플레이용 끝점). 위험 구간 뒤에 둔다
@export var finish_x := 3650.0:
	set(value):
		finish_x = value
		queue_redraw()
## 판정선을 그릴 X 범위 (디버그 표시용)
@export var draw_from_x := -400.0
@export var draw_to_x := 4000.0


func get_spawn_position() -> Vector2:
	return ($PlayerSpawn as Node2D).global_position


func get_buildings() -> Array[Building]:
	var result: Array[Building] = []
	for child in get_children():
		if child is Building:
			result.append(child)
	return result


func get_enemies() -> Array[Enemy]:
	var result: Array[Enemy] = []
	for child in get_children():
		if child is Enemy:
			result.append(child)
	return result


func get_hazards() -> Array[Hazard]:
	var result: Array[Hazard] = []
	for child in get_children():
		if child is Hazard:
			result.append(child)
	return result


## 코스 전체를 감싸는 영역 (전역 좌표). 코스 전체 보기 카메라에 쓴다.
func get_bounds() -> Rect2:
	var bounds := Rect2(get_spawn_position(), Vector2.ZERO)
	for building in get_buildings():
		bounds = bounds.merge(building.get_rect())
	for enemy in get_enemies():
		bounds = bounds.merge(Rect2(enemy.global_position - Vector2.ONE * enemy.radius, Vector2.ONE * enemy.radius * 2.0))
	for hazard in get_hazards():
		bounds = bounds.merge(hazard.get_rect())
	bounds = bounds.expand(Vector2(bounds.position.x, global_position.y + fall_limit_y))
	bounds = bounds.expand(Vector2(global_position.x + finish_x + 100.0, bounds.position.y))  # 'FINISH' 글자까지
	return bounds.grow(80.0)


func _draw() -> void:
	draw_dashed_line(Vector2(draw_from_x, fall_limit_y), Vector2(draw_to_x, fall_limit_y), FALL_LINE_COLOR, 3.0, 18.0)
	var label_x := ($PlayerSpawn as Node2D).position.x if has_node("PlayerSpawn") else 0.0
	draw_string(ThemeDB.fallback_font, Vector2(label_x, fall_limit_y - 10), "FALL LIMIT (game over below)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, FALL_LINE_COLOR)
	draw_dashed_line(Vector2(finish_x, -600.0), Vector2(finish_x, fall_limit_y), FINISH_COLOR, 4.0, 24.0)
	draw_string(ThemeDB.fallback_font, Vector2(finish_x + 10, 120), "FINISH", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, FINISH_COLOR)
