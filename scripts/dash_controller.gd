## 돌진 베기 컨트롤러 — 본 구현은 Phase 3.
##
## 지켜야 할 확정 규칙 (기획서 §7, §15):
## - 적에게만 쓴다. 조준 없이 우클릭으로 범위 안의 적을 자동으로 고른다.
## - 타깃 우선순위 (§7.2): 살아 있음 → 전방(+X) → 사거리 안 → 전방에서 가장 가까운 적. 후보가 없으면 돌진하지 않는다.
## - 돌진은 공격이자 이동 수단이며 적을 관통해 전방으로 진행한다. 돌진 중 추가 타기팅은 없다.
## - 와이어 중이면 와이어를 해제하고 돌진으로 전환한다.
## - 돌진 속도는 일반 체공 최고 속도와 별개이며, 돌진 뒤 상한 초과 속도가 영구 유지되지 않는다.
## - 건물을 가로지르는 돌진은 허용하지 않는다 (§7.2 [MVP 제안] 경로 확인).
##
## Phase 0: 입력이 들어오는 자리만 있다.
class_name DashController
extends Node

var player: PlayerController
var tuning: DashTuning
## 디버그 표시용 마지막 입력 요청
var last_request := "-"


func setup(owner_player: PlayerController, dash_tuning: DashTuning) -> void:
	player = owner_player
	tuning = dash_tuning


## 우클릭: 유효 타깃이 있으면 돌진, 없으면 아무것도 하지 않는다 (§4 [MVP 제안]: 와이어 상태 유지).
func request_dash() -> void:
	last_request = "dash request - Phase 3"
