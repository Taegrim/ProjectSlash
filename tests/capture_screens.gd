## 개발용 화면 캡처 도구 (웹 빌드 제외). 리뷰 페이지용 스크린샷과 GIF 용 연속 프레임을 만든다.
## 헤드리스는 렌더링을 하지 않으므로 창이 잠깐 떴다가 닫힌다. 1프레임 = 1물리틱이 되도록 --fixed-fps 60 으로 실행한다.
##
##   godot --path . --fixed-fps 60 -s res://tests/capture_screens.gd -- --out=<폴더> [옵션]
##
## 옵션
##   --scene=res://...           캡처할 씬 (기본 메인 씬). 현재 씬으로 불러오므로 재시작(R)도 실제 경로로 동작한다
##   --shots=이름@프레임,...      해당 프레임에 <out>/<이름>.png 저장 (기본 start@30)
##   --press=액션@프레임,...      해당 프레임에 입력 액션을 누른다 (예: restart@150, toggle_overview@200)
##   --record=시작-끝[:간격]      구간 프레임을 <out>/frames/f_0000.png … 로 저장 (GIF 재료, 간격 기본 2)
##   --overview                   마지막에 코스 전체 보기를 켜고 <out>/overview.png 저장
extends SceneTree

var _out := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var options := {"out": "", "scene": "res://scenes/main.tscn", "shots": "start@30", "press": "", "record": ""}
	var overview := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--overview":
			overview = true
		elif arg.begins_with("--") and "=" in arg:
			var pair := arg.trim_prefix("--").split("=", true, 1)
			options[pair[0]] = pair[1]
	_out = options["out"]
	if _out.is_empty():
		printerr("--out=<폴더> 가 필요합니다")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)

	var shots := _parse_at_list(options["shots"])
	var presses := _parse_at_list(options["press"])
	var record_from := -1
	var record_to := -1
	var record_step := 2
	if not String(options["record"]).is_empty():
		var spec := String(options["record"]).split(":")
		var span := spec[0].split("-")
		record_from = int(span[0])
		record_to = int(span[1])
		if spec.size() > 1:
			record_step = maxi(1, int(spec[1]))
		DirAccess.make_dir_recursive_absolute(_out.path_join("frames"))

	change_scene_to_file(options["scene"])
	await process_frame
	await process_frame

	var last_frame := record_to
	for frame_list in [shots.keys(), presses.keys()]:
		for frame in frame_list:
			last_frame = maxi(last_frame, frame)
	var recorded := 0
	for frame in range(0, last_frame + 1):
		for action in presses.get(frame, []):
			_press(action)
		await process_frame
		for shot_name in shots.get(frame, []):
			_save(_out.path_join(shot_name + ".png"))
		if record_from >= 0 and frame >= record_from and frame <= record_to and (frame - record_from) % record_step == 0:
			_save(_out.path_join("frames/f_%04d.png" % recorded), false)
			recorded += 1
	if recorded > 0:
		print("recorded %d frames -> %s" % [recorded, _out.path_join("frames")])

	if overview and InputMap.has_action("toggle_overview"):
		_press("toggle_overview")  # 사용자가 Tab 을 누른 것과 같은 경로
		for _i in 5:
			await process_frame
		_save(_out.path_join("overview.png"))
	quit(0)


## "a@10,b@20,c@20" → {10: ["a"], 20: ["b", "c"]}
func _parse_at_list(text: String) -> Dictionary:
	var result := {}
	for item in text.split(",", false):
		var pair := item.strip_edges().split("@")
		if pair.size() != 2:
			continue
		var frame := int(pair[1])
		if not result.has(frame):
			result[frame] = []
		result[frame].append(pair[0])
	return result


func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


func _save(path: String, verbose := true) -> void:
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	if verbose:
		print("saved %s %dx%d (%s)" % [path, image.get_width(), image.get_height(), error_string(error)])
