## 와이어(그래플) 컨트롤러 — 본 구현은 Phase 2.
##
## 지켜야 할 확정 규칙 (기획서 §6, §15):
## - 건물의 유효 표면(Building.get_attach_rect)에만 연결한다. 적에는 걸 수 없다.
## - 스윙형이며, 방향키 없이 전방 장애물 위로 진행하도록 자동 보정한다. 보정은 '보조'일 뿐 충돌을 무시하거나
##   순간이동시키지 않는다. 실제 이동은 언제나 move_and_slide 충돌 검사를 거친다.
## - 좌클릭 해제 시 수평 관성을 유지하고 조건부로 위로 도약한다.
## - 유효한 돌진이 시작되면 와이어를 해제한다 (이때 해제 도약 보너스는 주지 않음, §6.5 [MVP 제안]).
##
## 로프 구속 계획 (Phase 2): 로프 방향 바깥으로 향하는 속도 성분을 제거하고 접선 보조 가속을 더한 뒤
## move_and_slide 로 움직인다. 위치를 직접 보정해야 할 때도 충돌 검사로 막히면 보정하지 않는다.
##
## Phase 0: 입력이 들어오는 자리만 있다. 마지막 요청을 디버그 표시에 보여 준다.
class_name GrappleController
extends Node

var player: PlayerController
var tuning: GrappleTuning
var is_attached := false
## 디버그 표시용 마지막 입력 요청
var last_request := "-"


func setup(owner_player: PlayerController, grapple_tuning: GrappleTuning) -> void:
	player = owner_player
	tuning = grapple_tuning


## 좌클릭을 누른 순간 1회 연결을 시도한다 (§4 [MVP 제안]: 실패해도 누르고 있는 동안 자동 재발사하지 않음).
func request_attach(aim_point: Vector2) -> void:
	last_request = "attach at (%.0f, %.0f) - Phase 2" % [aim_point.x, aim_point.y]


## 좌클릭을 뗐을 때: 와이어 해제 + 조건부 해제 도약.
func request_release() -> void:
	last_request = "release - Phase 2"
