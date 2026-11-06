## 스윙 실험실 (개발용 — tests/ 는 웹 빌드에서 제외). 진자 궤적 시연: 아래에서 솟은 건물은 시계 방향,
## 공중 구조물(밑면에 건다)은 반시계 방향으로 돈다 (Phase 2 리뷰 10번).
## 에디터에서 이 씬을 열고 F6 으로 실행하면 마우스로 직접 해 볼 수 있다. 화면 밖으로 나가거나 R 을 누르면 처음으로.
## 지나온 길을 선(Trail)으로 남겨 원 궤적이 보이게 한다. 돌진 실험실(tests/dash_lab.tscn)도 이 스크립트를 쓴다.
extends Node2D

const START := Vector2(120, 300)
const TRAIL_POINTS := 150
const OUT_OF_LAB := Rect2(-200, -600, 2200, 1700)

## false 면 화면 밖으로 나가도 처음으로 돌리지 않는다 (탐색 스크립트용)
@export var auto_reset := true

@onready var player: PlayerController = $Player
@onready var trail: Line2D = $Trail
@onready var info: Label = $UI/Info


func _ready() -> void:
	_reset()


func _physics_process(_delta: float) -> void:
	if auto_reset and not OUT_OF_LAB.has_point(player.global_position):
		_reset()
		return
	trail.add_point(player.global_position)
	while trail.get_point_count() > TRAIL_POINTS:
		trail.remove_point(0)
	info.text = "%s   WIRE %s   DASH %s" % [player.get_state_name(), player.grapple.describe(), player.dash.describe()]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		_reset()


func _reset() -> void:
	player.grapple.force_release("reset")
	player.dash.cancel("reset")
	if player.state != PlayerController.State.AIRBORNE:
		player.set_state(PlayerController.State.AIRBORNE)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		(enemy as Enemy).revive()
	player.global_position = START
	player.velocity = Vector2(player.movement.auto_forward_speed, 0.0)
	trail.clear_points()
