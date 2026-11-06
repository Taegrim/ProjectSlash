## 적 — 돌진 베기 대상, 와이어 불가 (기획서 §7, §8 [확정]). v0.1 은 공격하지 않는 정지형 표적.
## 돌진이 아닌 몸 접촉은 일반 장애물처럼 감속한다 (§8 [MVP 제안]).
## 돌진 타기팅은 DashController 가 'enemies' 그룹에서 찾는다 (Phase 3).
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
	add_to_group("enemies")
	_collider = CollisionShape2D.new()
	_collider.shape = CircleShape2D.new()
	add_child(_collider)
	_sync_collider()


## 돌진이 적중했을 때 호출한다. 사라지고 충돌도 끈다 (§7.4).
func kill() -> void:
	if not alive:
		return
	alive = false
	hide()
	if _collider:
		_collider.set_deferred("disabled", true)
	killed.emit(self)


## 오브젝트 풀 (무한 코스): 켜면 되살리고, 끄면 처치 신호 없이 숨기고 충돌을 끈다
func set_pooled(active: bool) -> void:
	if active:
		revive()
		return
	alive = false
	hide()
	if _collider:
		_collider.set_deferred("disabled", true)


## 되살린다 (실험실 씬의 처음으로 돌아가기용. 게임 재시작은 씬을 다시 불러온다)
func revive() -> void:
	alive = true
	show()
	if _collider:
		_collider.set_deferred("disabled", false)


func _sync_collider() -> void:
	if _collider:
		(_collider.shape as CircleShape2D).radius = radius


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, BODY_COLOR)
	draw_circle(Vector2.ZERO, radius * 0.35, CORE_COLOR)
	if not debug_label.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(-radius, -radius - 10), debug_label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, LABEL_COLOR)
