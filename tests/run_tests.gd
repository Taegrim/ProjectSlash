## ProjectSlash 헤드리스 테스트 러너 — 외부 플러그인 없는 개발 전용 도구 (웹 빌드에서 제외).
##
## 하는 일
##   1) 로드 검사: res:// 아래 모든 .gd/.tscn/.tres 를 로드해 파스·참조 오류를 찾는다.
##      (숨김 폴더, .gdignore 가 있는 폴더, res://.godot, res://build 제외)
##   2) 테스트: res://tests/test_*.gd 의 test_* 메서드를 각각 새 인스턴스로 실행한다.
##      테스트 중 발생한 엔진/스크립트 오류(push_error 포함)도 실패로 집계한다.
##
## 실행
##   python tools/validate.py                                         (권장: 임포트 포함 전체 검증)
##   godot --headless --path . --fixed-fps 60 -s res://tests/run_tests.gd -- [옵션]
##   (--fixed-fps 는 physics_ticks_per_second 와 같아야 1프레임 = 1물리틱이 된다)
##
## 옵션 (-- 뒤에 지정)
##   --filter=<문자열>   파일명 또는 메서드명에 문자열이 포함된 테스트만 실행
##   --load=<res 경로>   지정한 리소스만 로드 검사하고 종료 (편집 훅용, 여러 번 지정 가능)
##   --no-load-check     전체 로드 검사 생략
extends SceneTree

const TEST_DIR := "res://tests"
const BASE_SUITE := "res://tests/test_case.gd"
const LOAD_CHECK_EXTENSIONS: PackedStringArray = ["gd", "tscn", "tres"]
const EXCLUDED_DIRS: PackedStringArray = ["res://.godot", "res://build"]
const TEST_TIMEOUT_MSEC := 30_000
## 오류가 난 뒤 코루틴이 끝나지 않으면 이 프레임 수만큼만 더 기다린다.
const STALL_FRAMES_AFTER_ERROR := 30


## 엔진/스크립트 오류를 가로채 기록한다 (경고는 제외).
class ErrorCollector extends Logger:
	var _mutex := Mutex.new()
	var _messages: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var text := rationale if not rationale.is_empty() else code
		_mutex.lock()
		_messages.append("%s  (%s:%d %s)" % [text, file, line, function])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func count() -> int:
		_mutex.lock()
		var n := _messages.size()
		_mutex.unlock()
		return n

	func since(start: int) -> PackedStringArray:
		_mutex.lock()
		var result := _messages.slice(start)
		_mutex.unlock()
		return result


var _errors := ErrorCollector.new()
var _passed := 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	OS.add_logger(_errors)
	_main.call_deferred()


func _main() -> void:
	var filter := ""
	var load_only: PackedStringArray = []
	var load_check := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")
		elif arg.begins_with("--load="):
			load_only.append(arg.trim_prefix("--load="))
		elif arg == "--no-load-check":
			load_check = false
		else:
			_fail("[runner] 알 수 없는 옵션: " + arg)

	if not load_only.is_empty():
		_check_loads(load_only)
	else:
		if load_check:
			_check_loads(_find_files("res://", LOAD_CHECK_EXTENSIONS))
		await _run_suites(filter)
	_finish()


func _check_loads(paths: PackedStringArray) -> void:
	var ok := 0
	for path in paths:
		var before := _errors.count()
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		var problems := _errors.since(before)
		if resource == null and problems.is_empty():
			problems.append("로드 실패 (null)")
		if problems.is_empty():
			ok += 1
		else:
			_fail("[load] " + path, problems)
	_passed += ok
	print("로드 검사: %d개 중 %d개 정상" % [paths.size(), ok])


func _run_suites(filter: String) -> void:
	var ran := 0
	for path in _find_files(TEST_DIR, PackedStringArray(["gd"])):
		var file_name := path.get_file()
		if not file_name.begins_with("test_") or path == BASE_SUITE:
			continue
		var script := load(path) as GDScript
		if script == null:
			_fail("[suite] 로드 실패: " + path)
			continue
		var seen := {}
		for method in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_") or seen.has(method_name):
				continue
			seen[method_name] = true
			if not filter.is_empty() and not (filter in file_name or filter in method_name):
				continue
			await _run_test(script, "%s::%s" % [file_name.get_basename(), method_name], method_name)
			ran += 1
	if ran == 0:
		print("실행한 테스트 없음 (%s/test_*.gd)" % TEST_DIR)


func _run_test(script: GDScript, label: String, method_name: String) -> void:
	var suite: Object = script.new()
	if not suite.has_method("cleanup_nodes"):
		_fail(label, PackedStringArray(["%s 를 상속해야 합니다" % BASE_SUITE]))
		return
	suite.set("tree", self)
	var errors_before := _errors.count()
	var state := {"done": false}
	var body := func() -> void:
		await suite.call("before_each")
		await suite.call(method_name)
		await suite.call("after_each")
		state["done"] = true
	body.call()

	# 테스트 코루틴이 끝날 때까지 프레임을 진행한다. 오류로 코루틴이 멈추면 오래 기다리지 않는다.
	var deadline := Time.get_ticks_msec() + TEST_TIMEOUT_MSEC
	var frames_since_error := 0
	while not state["done"] and Time.get_ticks_msec() < deadline:
		if _errors.count() > errors_before:
			frames_since_error += 1
			if frames_since_error > STALL_FRAMES_AFTER_ERROR:
				break
		await process_frame
	await suite.call("cleanup_nodes")

	var problems: PackedStringArray = (suite.get("failures") as PackedStringArray).duplicate()
	if not state["done"]:
		problems.append("테스트가 끝나지 않음 (시간 초과 또는 실행 중 스크립트 오류)")
	problems.append_array(_errors.since(errors_before))
	if problems.is_empty():
		_passed += 1
		print("  통과  ", label)
	else:
		_fail(label, problems)


func _find_files(dir_path: String, extensions: PackedStringArray) -> PackedStringArray:
	var found: PackedStringArray = []
	if dir_path in EXCLUDED_DIRS or FileAccess.file_exists(dir_path.path_join(".gdignore")):
		return found
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.include_hidden = false
	for file_name in dir.get_files():
		if file_name.get_extension() in extensions:
			found.append(dir_path.path_join(file_name))
	for sub_dir in dir.get_directories():
		found.append_array(_find_files(dir_path.path_join(sub_dir), extensions))
	return found


func _fail(label: String, details: PackedStringArray = PackedStringArray()) -> void:
	var text := "  실패  " + label
	for detail in details:
		text += "\n          - " + detail
	_failures.append(label)
	print(text)


func _finish() -> void:
	print("")
	print("결과: 통과 %d / 실패 %d" % [_passed, _failures.size()])
	if not _failures.is_empty():
		print("실패 항목: " + ", ".join(_failures))
	quit(0 if _failures.is_empty() else 1)
