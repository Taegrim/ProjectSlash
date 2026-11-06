## 게임 UI — 디버그 표시(기획서 §13.1), 점수·콤보 HUD(v0.2-2), 일시정지·게임 오버 표시, 조작 안내.
## 게임 안 글자는 영어로 둔다: 웹 빌드의 기본 폰트에 한글 글리프가 없어 깨지는 것을 피하고 폰트 에셋을 늘리지 않기 위해서.
class_name GameUI
extends CanvasLayer

const DEATH_TEXT := {
	"fall": "fell below the limit",
	"hazard": "hit a hazard",
	"ceiling": "flew above the ceiling",
}

## 점수·콤보 HUD 위치 (사용자 시안 선택 전 임시: 우측). 개발용으로 환경 변수 HUD_LAYOUT=right|left|top|bottom 이 우선
@export var hud_layout: ScoreHUD.Layout = ScoreHUD.Layout.RIGHT

var hud: ScoreHUD

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


func set_debug_visible(enabled: bool) -> void:
	_debug_panel.visible = enabled


func set_debug_text(text: String) -> void:
	_debug_label.text = text


func set_paused(paused: bool) -> void:
	_pause_label.visible = paused


func show_game_over(reason: String, distance: float, score := -1, best_combo := 0) -> void:
	# 디버그 표시와 같은 반올림(%.0f)을 써서 두 값이 어긋나지 않게 한다
	var score_line := ("\nscore  %s    best combo  x%d" % [ScoreHUD._group_digits(score), best_combo]) if score >= 0 else ""
	_game_over_label.text = "GAME OVER  -  %s\ndistance  %.0f px%s\n\nR  restart" % [DEATH_TEXT.get(reason, reason), distance,
			score_line]
	_game_over_label.visible = true


## 코스 클리어 표시 (Phase 4). 게임 오버와 같은 자리를 초록색으로 쓴다
func show_clear(seconds: float, distance: float, kills: int) -> void:
	_game_over_label.text = "COURSE CLEAR
time  %.1f s    distance  %.0f px    kills  %d

R  play again" % [seconds, distance, kills]
	_game_over_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.55))
	_game_over_label.visible = true


func is_game_over_visible() -> bool:
	return _game_over_label.visible
