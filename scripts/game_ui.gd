## 게임 UI — 디버그 표시(기획서 §13.1), 점수·콤보 HUD(v0.2-2), 일시정지·게임 오버 표시, 조작 안내.
## 게임 안 글자는 영어로 둔다: 웹 빌드의 기본 폰트에 한글 글리프가 없어 깨지는 것을 피하고 폰트 에셋을 늘리지 않기 위해서.
## 터치 모드 (v0.2-6): 일시정지 버튼(왼쪽 위), 일시정지 중 재개·재시작 버튼, 터치용 안내 줄, 게임 오버 '탭하면 재시작'.
## 버튼은 손가락 크기를 생각해 기준 해상도에서 110px (휴대폰에서 약 9mm) 로 둔다. 세로 화면이면 '가로로 돌려 주세요' 덮개를 띄운다.
class_name GameUI
extends CanvasLayer

signal pause_pressed
signal restart_pressed

const TOUCH_BUTTON_SIZE := 110.0
## 터치 모드 UI 배율 — 휴대폰 가로 화면은 기준의 약 0.5배로 보이므로 글자를 키운다 (v0.2-7 "모바일은 UI 만 크게")
const TOUCH_UI_SCALE := 1.5
const TOUCH_HINT := "Tap anywhere = dash (red ring) / wire (green mark)    Hold = swing, lift = jump"

const DEATH_TEXT := {
	"fall": "fell below the limit",
	"hazard": "hit a hazard",
	"ceiling": "flew above the ceiling",
}

## 점수·콤보 HUD 위치 (사용자 시안 선택 전 임시: 우측). 개발용으로 환경 변수 HUD_LAYOUT=right|left|top|bottom 이 우선
@export var hud_layout: ScoreHUD.Layout = ScoreHUD.Layout.RIGHT

var hud: ScoreHUD
var touch_mode := false
var pause_button: Button
var resume_button: Button
var restart_button: Button
var rotate_overlay: ColorRect

@onready var _debug_panel: Control = $DebugPanel
@onready var _debug_label: Label = $DebugPanel/DebugLabel
@onready var _pause_label: Label = $PauseLabel
@onready var _game_over_label: Label = $GameOverLabel


func _ready() -> void:
	var override := OS.get_environment("HUD_LAYOUT").to_upper()
	if ScoreHUD.Layout.has(override):
		hud_layout = ScoreHUD.Layout[override]
	hud = ScoreHUD.new()
	hud.layout = hud_layout
	add_child(hud)
	move_child(hud, 0)  # 일시정지·게임 오버 글자가 HUD 위에 오게
	_build_touch_controls()


func _build_touch_controls() -> void:
	pause_button = _make_button("II", Vector2(TOUCH_BUTTON_SIZE, TOUCH_BUTTON_SIZE))
	pause_button.position = Vector2(12, 12)
	pause_button.pressed.connect(func() -> void: pause_pressed.emit())
	var row := HBoxContainer.new()
	row.name = "PauseButtons"
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.set_anchors_preset(Control.PRESET_CENTER)
	row.offset_left = -280.0
	row.offset_right = 280.0
	row.offset_top = 60.0
	row.offset_bottom = 50.0 + TOUCH_BUTTON_SIZE
	row.visible = false
	add_child(row)
	resume_button = _make_button("RESUME", Vector2(260, TOUCH_BUTTON_SIZE), row)
	resume_button.pressed.connect(func() -> void: pause_pressed.emit())
	restart_button = _make_button("RESTART", Vector2(260, TOUCH_BUTTON_SIZE), row)
	restart_button.pressed.connect(func() -> void: restart_pressed.emit())
	# 세로 화면 덮개: 화면 전체를 가리고 아래로 가는 탭을 막는다
	rotate_overlay = ColorRect.new()
	rotate_overlay.name = "RotateOverlay"
	rotate_overlay.color = Color(0.04, 0.05, 0.08, 0.96)
	rotate_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rotate_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	rotate_overlay.visible = false
	var message := Label.new()
	message.text = "Rotate your device to landscape"
	message.add_theme_font_size_override("font_size", 64)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rotate_overlay.add_child(message)
	add_child(rotate_overlay)


func _make_button(label: String, minimum: Vector2, parent: Node = self) -> Button:
	var button := Button.new()
	button.name = "PauseButton" if label == "II" else label.capitalize() + "Button"
	button.text = label
	button.custom_minimum_size = minimum
	button.size = minimum
	button.focus_mode = Control.FOCUS_NONE  # 키보드 포커스가 남아 스페이스 등으로 눌리지 않게
	button.add_theme_font_size_override("font_size", 40)
	button.modulate = Color(1, 1, 1, 0.8)
	button.visible = parent != self
	parent.add_child(button)
	return button


## 터치 모드 켜기/끄기: 버튼·안내 줄을 바꾼다. 디버그 창은 일시정지 버튼과 겹치지 않게 아래로 내린다
func set_touch_mode(enabled: bool) -> void:
	touch_mode = enabled
	pause_button.visible = enabled
	_debug_panel.position.y = 12.0 + (TOUCH_BUTTON_SIZE + 12.0 if enabled else 0.0)
	$PauseButtons.visible = enabled and _pause_label.visible
	# 휴대폰 가로 화면은 기준 해상도의 약 0.5배로 보이므로 글자를 키운다 (15px → 약 8px 이면 읽기 어려움)
	var k := TOUCH_UI_SCALE if enabled else 1.0
	hud.set_ui_scale(k)
	var hint: Label = $HintLabel
	hint.add_theme_font_size_override("font_size", 26 if enabled else 15)
	hint.offset_top = -50.0 if enabled else -36.0
	_pause_label.add_theme_font_size_override("font_size", roundi(30 * k))
	_game_over_label.add_theme_font_size_override("font_size", roundi(32 * k))
	_game_over_label.offset_top = -90.0 * k
	_game_over_label.offset_bottom = 90.0 * k
	_refresh_hint()


## 세로 화면 덮개
func set_rotate_overlay(enabled: bool) -> void:
	rotate_overlay.visible = enabled


var _air_text := "A"
var _scheme_text := ""


## 조작 안내 줄 끝에 공중 좌우 조작 방식 표시 (F2 로 A/B 전환)
func set_air_control(mode: MovementTuning.AirControlMode) -> void:
	_air_text = "A" if mode == MovementTuning.AirControlMode.NONE else "B (A/D)"
	_refresh_hint()


## 조작 안내 줄 앞부분 = 입력 방식 (F3 으로 한 버튼 / 두 버튼 전환, v0.2-5)
func set_input_scheme(one_button: bool) -> void:
	_scheme_text = ("LMB = wire on yellow band (hold, release = jump) / dash elsewhere (red ring)" if one_button
			else "LMB hold = wire (yellow band)    RMB dash (red ring)")
	_refresh_hint()


func _refresh_hint() -> void:
	var hint: Label = $HintLabel
	if not hint.has_meta("base"):
		hint.set_meta("base", hint.text)
	if touch_mode:
		hint.text = TOUCH_HINT
		return
	hint.text = "%s    %s    F3 input    F2 air: %s" % [_scheme_text, hint.get_meta("base"), _air_text]


func set_debug_visible(enabled: bool) -> void:
	_debug_panel.visible = enabled


func set_debug_text(text: String) -> void:
	_debug_label.text = text


func set_paused(paused: bool) -> void:
	_pause_label.visible = paused
	_pause_label.text = "PAUSED" if touch_mode else "PAUSED   (ESC resume, R restart)"
	$PauseButtons.visible = paused and touch_mode


func show_game_over(reason: String, distance: float, score := -1, best_combo := 0) -> void:
	# 디버그 표시와 같은 반올림(%.0f)을 써서 두 값이 어긋나지 않게 한다
	var score_line := ("\nscore  %s    best combo  x%d" % [ScoreHUD._group_digits(score), best_combo]) if score >= 0 else ""
	_game_over_label.text = "GAME OVER  -  %s\ndistance  %.0f px%s\n\n%s" % [DEATH_TEXT.get(reason, reason), distance,
			score_line, "TAP  to restart" if touch_mode else "R  restart"]
	_game_over_label.visible = true


## 코스 클리어 표시 (Phase 4). 게임 오버와 같은 자리를 초록색으로 쓴다
func show_clear(seconds: float, distance: float, kills: int) -> void:
	_game_over_label.text = "COURSE CLEAR
time  %.1f s    distance  %.0f px    kills  %d

%s" % [seconds, distance, kills, "TAP  to play again" if touch_mode else "R  play again"]
	_game_over_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.55))
	_game_over_label.visible = true


func is_game_over_visible() -> bool:
	return _game_over_label.visible
