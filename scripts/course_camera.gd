## 카메라 — 플레이어 진행을 추적하고, 플레이어를 화면 중앙보다 왼쪽에 둔다 (기획서 §3 [확정]·[MVP 제안]).
## X: 플레이어 X + forward_offset 을 그대로 따라간다.
## Y: 위쪽으로는 완만하게(지수 보간) 따라가고, 아래쪽으로는 base_y + follow_down_limit 까지만 내려간다.
##    떨어지는 플레이어를 끝없이 따라가면 '화면 아래로 추락하면 사망'이 성립하지 않기 때문이다 (§3 [필수 주의]).
##    사망 판정 자체는 카메라와 별개인 코스의 하단 판정선이 한다.
## 플레이어와 같은 물리 프레임에 움직여 떨림을 줄인다. 디버그: 코스 전체 보기(Tab).
class_name CourseCamera
extends Camera2D

var target: Node2D
## 플레이어보다 앞(+X)을 비추는 거리 (MovementTuning.camera_forward_offset)
var forward_offset := 220.0
## 카메라 Y 기준 높이 (보통 스폰 높이)
var base_y := 0.0
## 기준보다 아래로 내려갈 수 있는 최대 거리 (MovementTuning.camera_vertical_follow_limit)
var follow_down_limit := 200.0
## Y 추적 세기 (MovementTuning.camera_vertical_smoothing)
var vertical_smoothing := 4.0
## 코스 전체 보기 때 화면에 맞출 영역 (전역 좌표)
var overview_rect := Rect2()
var overview := false


func configure(follow_target: Node2D, tuning: MovementTuning, base_height: float) -> void:
	target = follow_target
	forward_offset = tuning.camera_forward_offset
	follow_down_limit = tuning.camera_vertical_follow_limit
	vertical_smoothing = tuning.camera_vertical_smoothing
	base_y = base_height
	snap_to_target()


## 보간 없이 목표 위치로 바로 맞춘다 (시작·전체 보기 해제 때)
func snap_to_target() -> void:
	if target:
		global_position = Vector2(target.global_position.x + forward_offset, _desired_y())
		reset_smoothing()


func _physics_process(delta: float) -> void:
	if overview or target == null:
		return
	var weight := 1.0 - exp(-vertical_smoothing * delta)
	global_position = Vector2(target.global_position.x + forward_offset, lerpf(global_position.y, _desired_y(), weight))


## 플레이어 높이를 따라가되 기준보다 follow_down_limit 이상 아래로는 내려가지 않는다
func _desired_y() -> float:
	return minf(target.global_position.y, base_y + follow_down_limit)


## 카메라가 내려갈 수 있는 가장 낮은 Y
func get_lowest_y() -> float:
	return base_y + follow_down_limit


func set_overview(enabled: bool) -> void:
	overview = enabled and overview_rect.has_area()
	if overview:
		var view := get_viewport_rect().size
		var scale_to_fit := minf(view.x / overview_rect.size.x, view.y / overview_rect.size.y)
		zoom = Vector2(scale_to_fit, scale_to_fit)
		global_position = overview_rect.get_center()
	else:
		zoom = Vector2.ONE
		snap_to_target()
