## 건물 — 와이어 연결 대상, 돌진 불가. 몸이 닿으면 감속하고 관통할 수 없다 (기획서 §8 [확정]).
##
## 원점 = 지붕 왼쪽 위 모서리, size.y 만큼 아래로 뻗는다.
## AttachableSurface (§6.2 [MVP 제안]): 지붕에서 attach_band_depth 만큼 내려온 상단 띠. 와이어는 이 영역 안의
## 레이캐스트 적중 지점에만 걸린다 (연결 로직은 Phase 2). 띠를 깊게 하면 '낮은 연결' 상황을 만들 수 있다.
##
## 그림은 @tool 로 에디터에서도 보이고, 충돌체는 실행할 때만 size 로 만든다 (그림과 충돌이 항상 일치).
@tool
class_name Building
extends StaticBody2D

const GROUP := "buildings"

const BODY_COLOR := Color(0.22, 0.25, 0.33)
const OUTLINE_COLOR := Color(0.47, 0.52, 0.64)
const ATTACH_COLOR := Color(0.96, 0.79, 0.3, 0.55)
const LABEL_COLOR := Color(0.85, 0.88, 0.95)

@export var size := Vector2(220, 700):
	set(value):
		size = value.max(Vector2(10, 10))
		_sync_collider()
		queue_redraw()
## 와이어 연결 가능 띠가 지붕에서 얼마나 내려가서 시작하는지 (px) — [튜닝]. 0 이면 지붕부터.
## 레벨 디자인에서 '연결점이 낮아 더 크게 돌아 올라가야 하는' 건물을 만들 때 쓴다. 테스트 코스는 모두 0
## (2차 수정 리뷰 11번: 난이도는 실제 레벨 디자인에서 잡고, 지금은 띠가 지붕까지 닿아야 함)
@export var attach_band_top := 0.0:
	set(value):
		attach_band_top = maxf(value, 0.0)
		queue_redraw()
## 와이어 연결 가능 띠의 깊이 (px, 띠 시작점부터 아래로) — [튜닝]
@export var attach_band_depth := 80.0:
	set(value):
		attach_band_depth = maxf(value, 0.0)
		queue_redraw()
## 공중 구조물인지 (아래가 비어 있는 다리·간판 등). 와이어를 걸면 반시계 방향(아래 → 오른쪽 → 위)으로 돈다.
## false 면 아래에서 솟은 건물로 보고 시계 방향(왼쪽 → 위 → 지붕 쪽)으로 돈다 (Phase 2 리뷰 10번, 수정 리뷰 10번)
@export var aerial := false
## 디버그 표시 이름 (테스트 코스의 A, B, E 등)
@export var debug_label := "":
	set(value):
		debug_label = value
		queue_redraw()

var _collider: CollisionShape2D
var _layer := 2
## 풀에서 다시 배치될 때마다 1 씩 늘어난다 — 같은 노드라도 다른 '건물'로 구분할 때 쓴다 (콤보: 건물마다 한 번)
var serial := 0


## 오브젝트 풀 (무한 코스): 끄면 숨기고 충돌에서 빠진다. 생성·삭제 없이 위치·크기만 바꿔 다시 쓴다
func set_pooled(active: bool) -> void:
	if active:
		serial += 1
	visible = active
	collision_layer = _layer if active else 0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group(GROUP)  # 자동 조준(GrappleController.find_auto_anchor)이 찾는다
	_layer = collision_layer
	_collider = CollisionShape2D.new()
	_collider.shape = RectangleShape2D.new()
	add_child(_collider)
	_sync_collider()


## 와이어 연결 가능 영역 (전역 좌표). 띠가 건물보다 깊으면 건물 높이까지만.
func get_attach_rect() -> Rect2:
	var band := _band_rect()
	return Rect2(global_position + band.position, band.size)


## 띠 영역 (건물 기준 좌표)
func _band_rect() -> Rect2:
	var top := minf(attach_band_top, size.y)
	return Rect2(Vector2(0.0, top), Vector2(size.x, minf(attach_band_depth, size.y - top)))


## 건물 전체 영역 (전역 좌표)
func get_rect() -> Rect2:
	return Rect2(global_position, size)


func _sync_collider() -> void:
	if _collider == null:
		return
	(_collider.shape as RectangleShape2D).size = size
	_collider.position = size / 2.0


func _draw() -> void:
	var body := Rect2(Vector2.ZERO, size)
	draw_rect(body, BODY_COLOR)
	draw_rect(_band_rect(), ATTACH_COLOR)
	draw_rect(body, OUTLINE_COLOR, false, 2.0)
	if not debug_label.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(6, -10), debug_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, LABEL_COLOR)
