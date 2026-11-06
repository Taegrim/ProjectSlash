## 적 — 돌진 베기 대상, 와이어 불가 (기획서 §7, §8 [확정]). v0.1 은 공격하지 않는 정지형 표적.
## 돌진이 아닌 몸 접촉은 일반 장애물처럼 감속한다 (§8 [MVP 제안]).
## 타기팅·처치 로직은 Phase 3. 지금은 살아 있음 여부와 처치 함수만 있다.
@tool
class_name Enemy
extends StaticBody2D

signal killed(enemy: Enemy)

const BODY_COLOR := Color(0.86, 0.3, 0.62)
const CORE_COLOR := Color(1.0, 0.85, 0.95)
const LABEL_COLOR := Color(0.95, 0.75, 0.9)

@export var radius := 22.0:
	set(value):
		radius = maxf(value, 4.0)
		_sync_collider()
		queue_redraw()
@export var debug_label := "":
	set(value):
		debug_label = value
		queue_redraw()

var alive := true
var _collider: CollisionShape2D


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_collider = CollisionShape2D.new()
	_collider.shape = CircleShape2D.new()
	add_child(_collider)
	_sync_collider()


## 돌진이 적중했을 때 호출한다 (Phase 3). 사라지고 충돌도 끈다.
func kill() -> void:
	if not alive:
		return
	alive = false
	hide()
	if _collider:
		_collider.set_deferred("disabled", true)
	killed.emit(self)


func _sync_collider() -> void:
	if _collider:
		(_collider.shape as CircleShape2D).radius = radius


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, BODY_COLOR)
	draw_circle(Vector2.ZERO, radius * 0.35, CORE_COLOR)
	if not debug_label.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(-radius, -radius - 10), debug_label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, LABEL_COLOR)
