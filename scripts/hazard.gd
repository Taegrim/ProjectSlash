## 위험 장애물 — 와이어·돌진 불가, 닿으면 즉시 게임 오버 (기획서 §8 [확정], 유형은 추후 결정).
## v0.1 은 눈에 띄는 붉은 사각형 1종 (§8 [MVP 제안]). 원점 = 왼쪽 위 모서리.
## 플레이어가 들어오면 player_touched 를 보낸다. 게임 오버 처리는 Phase 1 의 게임 흐름에서 연결한다.
@tool
class_name Hazard
extends Area2D

signal player_touched(hazard: Hazard)

const FILL_COLOR := Color(0.9, 0.18, 0.2, 0.85)
const STRIPE_COLOR := Color(1.0, 0.55, 0.5, 0.9)

@export var size := Vector2(160, 160):
	set(value):
		size = value.max(Vector2(10, 10))
		_sync_collider()
		queue_redraw()
@export var debug_label := "":
	set(value):
		debug_label = value
		queue_redraw()

var _collider: CollisionShape2D


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_collider = CollisionShape2D.new()
	_collider.shape = RectangleShape2D.new()
	add_child(_collider)
	_sync_collider()
	body_entered.connect(_on_body_entered)


## 오브젝트 풀 (무한 코스): 끄면 숨기고 감지를 멈춘다
func set_pooled(active: bool) -> void:
	visible = active
	set_deferred("monitoring", active)


func get_rect() -> Rect2:
	return Rect2(global_position, size)


func _on_body_entered(body: Node2D) -> void:
	if body is PlayerController:
		player_touched.emit(self)


func _sync_collider() -> void:
	if _collider == null:
		return
	(_collider.shape as RectangleShape2D).size = size
	_collider.position = size / 2.0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), FILL_COLOR)
	var step := 28.0
	var x := 0.0
	while x < size.x + size.y:  # 사선 줄무늬로 일반 건물과 구분
		draw_line(Vector2(maxf(0.0, x - size.y), minf(size.y, x)), Vector2(minf(x, size.x), maxf(0.0, x - size.x)),
				STRIPE_COLOR, 3.0)
		x += step
	if not debug_label.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(4, -10), debug_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, FILL_COLOR)
