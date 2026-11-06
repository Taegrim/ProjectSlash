## 효과음 (v0.2-3) — 와이어 연결·해제, 돌진, 베기, 사망, 콤보 상승.
## 소리는 assets/sfx/<이름>.wav (tools/make_sfx.py 로 만든 임시음 — 같은 이름으로 덮어쓰면 실제 소리로 바뀐다).
## 오브젝트 풀링: AudioStreamPlayer 를 시작할 때 몇 개 만들어 두고 돌려 쓴다 (플레이 중 생성·삭제 없음).
## 웹 브라우저는 첫 클릭 전에는 소리를 막는다 — 이 게임은 클릭으로 시작하므로 문제 없다.
## 헤드리스 실행(테스트·검증)에서는 실제로 재생하지 않고 기록만 한다: 가짜 오디오 장치는 재생을 끝내지 않아
## 종료할 때 '리소스가 아직 쓰이는 중' 오류가 난다 (v0.2-3 에서 확인).
class_name SFX
extends Node

const NAMES := ["wire_attach", "wire_release", "dash", "slash", "death", "combo"]
const PLAYERS := 8

## 전체 효과음 크기 (dB)
@export var volume_db := -4.0

## 마지막으로 요청된 소리와 요청 횟수 (테스트용)
var last_played := ""
var played := {}

var _streams := {}
var _silent := false
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	_silent = DisplayServer.get_name() == "headless"
	for sound in NAMES:
		var path := "res://assets/sfx/%s.wav" % sound
		if ResourceLoader.exists(path):
			_streams[sound] = load(path)
	for i in PLAYERS:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)


func setup(player: PlayerController, score: ScoreKeeper) -> void:
	player.grapple.attached.connect(func(_anchor: Vector2, _building: Building) -> void: play("wire_attach"))
	player.grapple.released.connect(func(boosted: bool) -> void:
		if boosted:
			play("wire_release"))
	player.dash.dash_started.connect(func(_enemy: Enemy) -> void: play("dash"))
	player.dash.dash_hit.connect(func(_enemy: Enemy) -> void: play("slash", randf_range(0.95, 1.08)))
	player.died.connect(func(_reason: String) -> void: play("death"))
	score.combo_changed.connect(func(combo: int) -> void:
		if combo >= 2:
			play("combo", minf(1.0 + 0.06 * (combo - 2), 1.8), -6.0))


## 이름으로 재생. pitch 는 재생 속도 (1 = 원음)
func play(sound: String, pitch := 1.0, extra_db := 0.0) -> void:
	if not _streams.has(sound):
		return
	last_played = sound
	played[sound] = played.get(sound, 0) + 1
	if _silent:
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = _streams[sound]
	player.pitch_scale = pitch
	player.volume_db = volume_db + extra_db
	player.play()
