## 점수·콤보 HUD (v0.2-2). 점수(크게), 거리(m), 콤보 배수와 남은 시간 막대.
## 위치는 layout 으로 고른다 — 사용자가 시안을 비교해 정한다 (우측 = 시선 방향, 좌측 = 동선 방해 없음, 상단, 하단).
## 콤보는 2 이상일 때만 보이고, 오를 때 잠깐 커졌다 돌아온다.
## 게임 안 글자는 영어 (웹 기본 폰트에 한글 글리프가 없음, game_ui.gd 참고).
class_name ScoreHUD
extends Control

enum Layout { RIGHT, LEFT, TOP, BOTTOM }

const SCORE_COLOR := Color(0.95, 0.97, 1.0)
const DIST_COLOR := Color(0.7, 0.78, 0.9)
const COMBO_COLOR := Color(1.0, 0.72, 0.3)
const OUTLINE := Color(0.05, 0.05, 0.08)
const MARGIN := 18.0

var layout: Layout = Layout.RIGHT

var _box: BoxContainer
var _score_label: Label
var _dist_label: Label
var _combo_box: VBoxContainer
var _combo_label: Label
var _combo_bar: ProgressBar
var _shown_combo := 0
var _pulse: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_label = _make_label(30, SCORE_COLOR)
	_dist_label = _make_label(18, DIST_COLOR)
	_combo_label = _make_label(26, COMBO_COLOR)
	_combo_bar = ProgressBar.new()
	_combo_bar.show_percentage = false
	_combo_bar.max_value = 1.0
	_combo_bar.custom_minimum_size = Vector2(170, 6)
	_combo_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = COMBO_COLOR
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.15)
	_combo_bar.add_theme_stylebox_override("fill", fill)
	_combo_bar.add_theme_stylebox_override("background", back)
	_combo_box = VBoxContainer.new()
	_combo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_box.add_child(_combo_label)
	_combo_box.add_child(_combo_bar)
	_combo_box.visible = false
	apply_layout(layout)


func apply_layout(next: Layout) -> void:
	layout = next
	if _box:
		for child in _box.get_children():
			_box.remove_child(child)
		_box.queue_free()
	var horizontal := layout in [Layout.TOP, Layout.BOTTOM]
	_box = HBoxContainer.new() if horizontal else VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 28 if horizontal else 2)
	add_child(_box)
	for child in [_score_label, _dist_label, _combo_box]:
		_box.add_child(child)
	var align := HORIZONTAL_ALIGNMENT_RIGHT if layout == Layout.RIGHT else HORIZONTAL_ALIGNMENT_LEFT
	for label in [_score_label, _dist_label, _combo_label]:
		label.horizontal_alignment = align
	_box.alignment = BoxContainer.ALIGNMENT_END if layout == Layout.RIGHT else BoxContainer.ALIGNMENT_BEGIN
	match layout:
		Layout.RIGHT:
			_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, MARGIN)
			_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Layout.LEFT:
			_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, MARGIN)
		Layout.TOP:
			_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, MARGIN)
			_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
		Layout.BOTTOM:
			_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, MARGIN)
			_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
			_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
			_box.offset_bottom = -44.0  # 아래 조작 안내 줄 위
			_box.offset_top = -44.0


## 매 프레임 값 갱신. combo_ratio = 콤보가 끊기기까지 남은 시간 비율 (0~1)
func show_values(score: int, meters: float, combo: int, multiplier: float, bonus: int, combo_ratio: float) -> void:
	_score_label.text = "SCORE  %s" % _group_digits(score)
	_dist_label.text = "%.0f m" % meters
	_combo_box.visible = combo >= 2
	if combo >= 2:
		_combo_label.text = "COMBO x%d   +%d  (x%.1f)" % [combo, bonus, multiplier]
		_combo_bar.value = combo_ratio
	if combo > _shown_combo and combo >= 2:
		_pulse_combo()
	_shown_combo = combo


func get_box_rect() -> Rect2:
	return _box.get_global_rect()


func _pulse_combo() -> void:
	if _pulse:
		_pulse.kill()
	_combo_label.pivot_offset = _combo_label.size / 2.0
	_combo_label.scale = Vector2(1.35, 1.35)
	_pulse = create_tween()
	_pulse.tween_property(_combo_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", 6)
	return label


static func _group_digits(value: int) -> String:
	var text := str(absi(value))
	var out := ""
	while text.length() > 3:
		out = "," + text.substr(text.length() - 3) + out
		text = text.substr(0, text.length() - 3)
	return text + out
