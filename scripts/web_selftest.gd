## 웹 빌드 자체 확인 (개발용) — 페이지 주소에 ?selftest 가 있을 때만 동작한다. 일반 플레이에는 아무 영향이 없다.
## 게임이 실제로 몇 초 돌아간 뒤 자기 화면(PNG)과 상태를 로컬 서버(/__selftest)로 보낸다 → tools/web_build.py --check 가 받는다.
## 헤드리스 브라우저의 스크린샷은 엔진이 뜨기 전 로딩 화면을 찍기 쉬워서, 게임이 직접 보고하게 했다.
class_name WebSelfTest
extends Node

const WAIT_PHYSICS_FRAMES := 90

var _main: Node
var _frames := 0


## 웹 + ?selftest 일 때만 붙인다
static func attach_if_requested(main: Node) -> void:
	if not OS.has_feature("web"):
		return
	var query := str(JavaScriptBridge.eval("window.location.search", true))
	if not query.contains("selftest"):
		return
	var probe := WebSelfTest.new()
	probe._main = main
	probe.process_mode = Node.PROCESS_MODE_ALWAYS
	main.add_child(probe)


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames != WAIT_PHYSICS_FRAMES:
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var player: PlayerController = _main.get_node("Player")
	var report := {
		"frames": _frames,
		"player_x": player.global_position.x,
		"state": player.get_state_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"touch_mode": _main.get("touch_mode"),
		"viewport": "%dx%d" % [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"png": Marshalls.raw_to_base64(image.save_png_to_buffer()),
	}
	JavaScriptBridge.eval("fetch('/__selftest', {method: 'POST', body: %s})" % JSON.stringify(JSON.stringify(report)), true)
