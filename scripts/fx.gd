## 시각 효과 (v0.2-3) — 돌진 궤적, 베기 파편·섬광, 와이어 연결 불꽃, 사망 터짐, 화면 흔들림, 히트스톱.
## 오브젝트 풀링: 파티클·궤적 노드를 시작할 때 미리 만들어 두고 돌려 쓴다 (플레이 중 생성·삭제 없음).
## 파티클은 CPUParticles2D (Compatibility·웹에서 확실히 동작).
## 히트스톱(벨 때 아주 잠깐 느려짐)은 화면 연출이라 헤드리스 실행(테스트·검증)에서는 하지 않는다 — 프레임 수로 재는 테스트가 흔들리지 않게.
class_name FX
extends Node2D

const SLASH_COLOR := Color(1.0, 0.55, 0.75)
const TRAIL_COLOR := Color(1.0, 0.6, 0.4)
const SPARK_COLOR := Color(1.0, 0.85, 0.35)
const DEATH_COLOR := Color(0.55, 0.9, 1.0)
const BURSTS := 8
const TRAILS := 3

@export var hit_stop_seconds := 0.06
@export var hit_stop_scale := 0.05
@export var slash_shake := 7.0
@export var death_shake := 14.0
@export var trail_fade := 0.35

var _player: PlayerController
var _camera: Camera2D
var _bursts: Array[CPUParticles2D] = []
var _next_burst := 0
var _trails: Array[Line2D] = []
var _next_trail := 0
var _active_trail: Line2D
var _slash_lines: Array[Line2D] = []
var _shake_time := 0.0
var _shake_total := 0.0
var _shake_strength := 0.0


func _ready() -> void:
	for i in BURSTS:
		var burst := CPUParticles2D.new()
		burst.emitting = false
		burst.one_shot = true
		burst.explosiveness = 1.0
		burst.lifetime = 0.5
		burst.local_coords = false
		burst.gravity = Vector2(0, 700)
		burst.scale_amount_min = 3.0
		burst.scale_amount_max = 6.0
		var fade := Gradient.new()
		fade.set_color(0, Color.WHITE)
		fade.set_color(1, Color(1, 1, 1, 0))
		burst.color_ramp = fade
		add_child(burst)
		_bursts.append(burst)
	for i in TRAILS:
		var trail := Line2D.new()
		trail.width = 12.0
		trail.default_color = TRAIL_COLOR
		trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
		trail.end_cap_mode = Line2D.LINE_CAP_ROUND
		var taper := Curve.new()
		taper.add_point(Vector2(0, 0.2))
		taper.add_point(Vector2(1, 1))
		trail.width_curve = taper
		trail.visible = false
		add_child(trail)
		_trails.append(trail)
		var cut := Line2D.new()  # 적을 가르는 섬광 선
		cut.width = 5.0
		cut.default_color = Color.WHITE
		cut.visible = false
		add_child(cut)
		_slash_lines.append(cut)


func setup(player: PlayerController, camera: Camera2D) -> void:
	_player = player
	_camera = camera
	player.dash.dash_started.connect(_on_dash_started)
	player.dash.dash_hit.connect(_on_dash_hit)
	player.dash.dash_ended.connect(_on_dash_ended)
	player.grapple.attached.connect(func(anchor: Vector2, _b: Building) -> void: burst(anchor, SPARK_COLOR, 10, 260.0))
	player.died.connect(func(_reason: String) -> void:
		burst(player.global_position, DEATH_COLOR, 40, 520.0)
		shake(death_shake, 0.35))


func _physics_process(_delta: float) -> void:
	if _active_trail and _player.state == PlayerController.State.DASHING:
		_active_trail.add_point(_player.global_position)


func _process(delta: float) -> void:
	if _camera == null:
		return
	if _shake_time > 0.0:
		_shake_time -= delta
		var k := maxf(_shake_time / _shake_total, 0.0)
		_camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake_strength * k
	elif _camera.offset != Vector2.ZERO:
		_camera.offset = Vector2.ZERO


## 파편 터짐. direction 이 있으면 그 방향으로 몰아서 튄다
func burst(at: Vector2, color: Color, amount: int, speed: float, direction := Vector2.ZERO) -> void:
	var particles := _bursts[_next_burst]
	_next_burst = (_next_burst + 1) % _bursts.size()
	particles.global_position = at
	particles.amount = amount
	particles.color = color
	particles.initial_velocity_min = speed * 0.45
	particles.initial_velocity_max = speed
	particles.direction = direction if direction != Vector2.ZERO else Vector2.UP
	particles.spread = 60.0 if direction != Vector2.ZERO else 180.0
	particles.restart()


func shake(strength: float, seconds: float) -> void:
	_shake_strength = maxf(strength, _shake_strength if _shake_time > 0.0 else 0.0)
	_shake_time = seconds
	_shake_total = seconds


func _on_dash_started(_enemy: Enemy) -> void:
	_active_trail = _trails[_next_trail]
	_next_trail = (_next_trail + 1) % _trails.size()
	_kill_fade(_active_trail)
	_active_trail.clear_points()
	_active_trail.add_point(_player.global_position)
	_active_trail.modulate = Color.WHITE
	_active_trail.visible = true


func _on_dash_hit(enemy: Enemy) -> void:
	var direction := _player.dash.direction
	burst(enemy.global_position, SLASH_COLOR, 26, 520.0, direction)
	burst(enemy.global_position, Color.WHITE, 10, 300.0)
	var cut := _slash_lines[_next_trail % _slash_lines.size()]
	var across := direction.orthogonal() * (enemy.radius + 18.0)
	cut.points = PackedVector2Array([enemy.global_position - across - direction * 10.0,
			enemy.global_position + across + direction * 10.0])
	_fade(cut, 0.22)
	shake(slash_shake, 0.15)
	_hit_stop()


func _on_dash_ended(_reason: String) -> void:
	if _active_trail:
		_fade(_active_trail, trail_fade)
		_active_trail = null


func _fade(line: Line2D, seconds: float) -> void:
	_kill_fade(line)
	line.visible = true
	line.modulate = Color.WHITE
	var tween := create_tween()
	tween.tween_property(line, "modulate:a", 0.0, seconds)
	tween.tween_callback(func() -> void:
		line.visible = false
		line.clear_points())
	line.set_meta("tween", tween)


## 진행 중인 사라짐 연출을 멈춘다 (get_meta 는 기본값이 null 이면 키가 없을 때 오류를 내므로 has_meta 로 확인)
func _kill_fade(line: Line2D) -> void:
	if line.has_meta("tween"):
		var tween: Tween = line.get_meta("tween")
		if tween and tween.is_valid():
			tween.kill()


func _hit_stop() -> void:
	if hit_stop_seconds <= 0.0 or DisplayServer.get_name() == "headless":
		return
	Engine.time_scale = hit_stop_scale
	get_tree().create_timer(hit_stop_seconds, true, false, true).timeout.connect(func() -> void: Engine.time_scale = 1.0)
