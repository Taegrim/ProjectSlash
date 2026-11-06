## 개발용 화면 캡처 도구 (웹 빌드 제외). 리뷰 페이지용 스크린샷과 GIF 용 연속 프레임을 만든다.
## 헤드리스는 렌더링을 하지 않으므로 창이 잠깐 떴다가 닫힌다. 1프레임 = 1물리틱이 되도록 --fixed-fps 60 으로 실행한다.
##
##   godot --path . --fixed-fps 60 -s res://tests/capture_screens.gd -- --out=<폴더> [옵션]
##
## 옵션
##   --scene=res://...           캡처할 씬 (기본: 프로젝트 메인 씬 = 무한 코스. 고정 테스트 코스는 res://scenes/main.tscn). 현재 씬으로 불러오므로 재시작(R)도 실제 경로로 동작한다
##   --shots=이름@프레임,...      해당 프레임에 <out>/<이름>.png 저장 (기본 start@30)
##   --press=액션@프레임,...      해당 프레임에 입력 액션을 누른다 (예: restart@150, toggle_overview@200)
##   --record=시작-끝[:간격]      구간 프레임을 <out>/frames/f_0000.png … 로 저장 (GIF 재료, 간격 기본 2)
##   --call=명령@프레임;...       플레이어 와이어 조작 (구분자는 ';'):
##                                aim:x,y (조준점 고정 — 마우스 대신), attach (조준점으로 연결), release (해제),
##                                click / unclick (좌클릭 누름·놓기 — 한 버튼 방식 그대로),
##                                touchmode (터치 모드 UI 로 전환), tap (터치 누름 = 자동 조준, 놓기는 unclick),
##                                dash (우클릭과 같음: 자동 타기팅 돌진)
##                                예) --call="aim:626,430@40;attach@53;release@83"
##   --overview                   마지막에 코스 전체 보기를 켜고 <out>/overview.png 저장
##   --bot                        자동 조작 봇(tests/course_bot.gd)이 플레이 (무한 코스 녹화용, 코스는 환경 변수 COURSE_SEED 로 고정)
extends SceneTree

var _out := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var options := {"out": "", "scene": str(ProjectSettings.get_setting("application/run/main_scene")), "shots": "start@30", "press": "", "record": "", "call": ""}
	var overview := false
	var use_bot := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--bot":
			use_bot = true
		elif arg == "--overview":
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
	var calls := _parse_at_list(String(options["call"]).replace(",", "|").replace(";", ","))  # 좌표의 ',' 보호
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
	if use_bot:
		var bot: Node = load("res://tests/course_bot.gd").new()
		var course: Node = null
		for child in current_scene.get_children():
			if child is CourseBase:
				course = child
		bot.call("setup", current_scene.get_node("Player"), course)
		current_scene.add_child(bot)

	var last_frame := record_to
	for frame_list in [shots.keys(), presses.keys(), calls.keys()]:
		for frame in frame_list:
			last_frame = maxi(last_frame, frame)
	var recorded := 0
	for frame in range(0, last_frame + 1):
		for action in presses.get(frame, []):
			_press(action)
		for command in calls.get(frame, []):
			_call_player(String(command).replace("|", ","))
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


## aim:x,y / attach / release — 현재 씬의 Player 노드에 직접 명령한다 (재시작 뒤에도 새 Player 를 찾는다)
func _call_player(command: String) -> void:
	var player := current_scene.find_child("Player", true, false) if current_scene else null
	if player == null:
		printerr("Player 노드를 찾지 못함: " + command)
		return
	if command.begins_with("aim:"):
		var xy := command.trim_prefix("aim:").split(",")
		player.set("debug_aim_override", Vector2(float(xy[0]), float(xy[1])))
	elif command == "attach":
		player.get("grapple").call("request_attach", player.get("debug_aim_override"))
	elif command == "release":
		player.get("grapple").call("request_release")
	elif command == "dash":
		player.get("dash").call("request_dash")
	elif command == "touchmode":  # 터치 모드 UI 로 바꾼다 (모바일 화면 캡처용)
		current_scene.call("set_touch_mode", true)
		return
	elif command == "click":  # 좌클릭 누름 = 실제 입력 경로 (한 버튼이면 띠 조준 → 와이어, 아니면 돌진)
		print("click -> %s" % player.call("press_action", player.get("debug_aim_override")))
	elif command == "tap":  # 화면 터치 누름 = 모바일 자동 조준 (어디를 눌러도 같음)
		print("tap -> %s" % player.call("press_action", Vector2(player.get("global_position")), true))
	elif command == "unclick":  # 좌클릭 놓기 = 와이어 해제
		player.get("grapple").call("request_release")
	else:
		printerr("알 수 없는 명령: " + command)
		return
	# 헤드리스 탐색 결과와 맞춰 보기 위해 명령 시점의 위치·결과를 남긴다
	var result_of: Object = player.get("dash") if command == "dash" else player.get("grapple")
	print("call %s at pos %s -> %s" % [command, Vector2(player.get("global_position")).round(),
			result_of.get("last_request")])


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
