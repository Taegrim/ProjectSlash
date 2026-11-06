## 코스 공통 API (기획서 §10) — game_flow·카메라·테스트가 쓰는 함수 모음.
## 고정 테스트 코스(TestCourse, 회귀 테스트용)와 패턴 무한 코스(EndlessCourse, v0.2 메인)가 구현한다.
@tool
class_name CourseBase
extends Node2D


func get_spawn_position() -> Vector2:
	return global_position


## 하단 사망 판정선 (월드 Y)
func get_fall_limit_y() -> float:
	return 1000.0


## 천장 (월드 Y). 이보다 위로 올라가면 게임 오버. 없으면 -INF (고정 테스트 코스)
func get_ceiling_y() -> float:
	return -INF


## 결승선 (월드 X). 없으면 INF (무한 코스)
func get_finish_x() -> float:
	return INF


func get_buildings() -> Array[Building]:
	var result: Array[Building] = []
	return result


func get_enemies() -> Array[Enemy]:
	var result: Array[Enemy] = []
	return result


## 위험 구역 전체 (game_flow 가 시작할 때 신호를 연결한다 — 무한 코스는 풀 전체를 돌려준다)
func get_hazards() -> Array[Hazard]:
	var result: Array[Hazard] = []
	return result


## 코스 전체 보기용 영역 (전역 좌표)
func get_bounds() -> Rect2:
	return Rect2()


## 매 물리 프레임 플레이어 위치로 코스를 갱신한다 (무한 코스: 앞쪽 생성·뒤쪽 회수). 고정 코스는 할 일 없음
func update_course(_player_x: float) -> void:
	pass


## 디버그 표시용 한 줄 (없으면 빈 문자열)
func describe() -> String:
	return ""
