## 테스트 스위트 기본 클래스. tests/test_*.gd 는 이 파일을 상속한다.
##
##     extends "res://tests/test_case.gd"
##
##     func test_no_input_moves_right_and_falls() -> void:
##         var player: Node2D = add_node(preload("res://scenes/player.tscn").instantiate())
##         var start := player.global_position
##         await physics_frames(60)
##         check(player.global_position.x > start.x, "자동 전진")
##         check(player.global_position.y > start.y, "중력 하강")
##
## - test_ 로 시작하는 메서드마다 새 인스턴스에서 실행된다. await 사용 가능.
## - 러너는 --fixed-fps <물리 틱 레이트> 로 실행되므로 physics_frames(n) 은 결정적이다
##   (기본 60틱/초 기준 physics_frames(60) = 1초).
## - check 실패, 테스트 중 발생한 엔진/스크립트 오류는 모두 실패로 집계된다.
extends RefCounted

var tree: SceneTree
var failures: PackedStringArray = []
var _owned_nodes: Array[Node] = []


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func check(condition: bool, message: String = "") -> bool:
	if not condition:
		fail(message if not message.is_empty() else "check 실패")
	return condition


func check_eq(actual: Variant, expected: Variant, message: String = "") -> bool:
	var same: bool
	if _is_number(actual) and _is_number(expected):
		same = float(actual) == float(expected)
	else:
		same = typeof(actual) == typeof(expected) and actual == expected
	if not same:
		fail("%s기대값 %s, 실제값 %s" % [_prefix(message), var_to_str(expected), var_to_str(actual)])
	return same


func check_near(actual: float, expected: float, tolerance: float, message: String = "") -> bool:
	var ok := absf(actual - expected) <= tolerance
	if not ok:
		fail("%s기대값 %s ± %s, 실제값 %s" % [_prefix(message), expected, tolerance, actual])
	return ok


func fail(message: String) -> void:
	failures.append(message)


## 노드를 씬 트리에 추가하고 테스트가 끝나면 자동으로 해제한다.
func add_node(node: Node) -> Node:
	tree.root.add_child(node)
	_owned_nodes.append(node)
	return node


## 물리 틱 count 번이 '처리 완료'된 직후까지 기다린다 (연속 호출해도 틱 수가 정확히 누적됨).
## physics_frame 시그널은 각 틱의 _physics_process 직전에 발생하므로, 마지막 틱 처리가 끝난
## 뒤인 process_frame 까지 한 번 더 기다린다. 러너가 1프레임 = 1물리틱으로 실행되는 것을 전제로 한다.
func physics_frames(count: int) -> void:
	for _i in count:
		await tree.physics_frame
	await tree.process_frame


## 러너 전용: 테스트가 추가한 노드를 정리한다.
func cleanup_nodes() -> void:
	for node in _owned_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_owned_nodes.clear()
	await tree.process_frame


func _prefix(message: String) -> String:
	return message + ": " if not message.is_empty() else ""


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
