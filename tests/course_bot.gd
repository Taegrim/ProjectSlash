## 자동 조작 봇 (개발용 — tests/ 는 웹 빌드 제외). 무한 코스의 통과 가능성 확인과 리뷰 녹화에 쓴다.
## 사람의 입력과 같은 요청 함수(request_attach / request_release / request_dash)만 부른다.
## 규칙: 돌진할 적이 있으면 돌진 → 없으면 앞쪽 건물의 띠(공중 구조물은 밑면)에 와이어 → 진행 방향이 앞·위가 되면 놓는다.
## 사람보다 서툰 단순한 규칙이라, 봇이 오래 살아남으면 '적어도 하나의 통과 경로가 있다'(§10.3)는 근거로 쓴다.
class_name CourseBot
extends Node

## 놓기 전에 최소한 잡고 있는 프레임 (해제 도약 조건 0.25초 = 15 프레임)
const MIN_HOLD := 16
const MAX_HOLD := 100
## 노리는 범위·연결 거리는 GrappleTuning 의 자동 조준 값 (auto_aim_look / auto_aim_reach / auto_aim_reach_aerial)

var player: PlayerController
var course: CourseBase
var actions := 0
## true 면 와이어를 먼저 시도하고 걸 곳이 없을 때만 돌진 (한 버튼 합치기 분석용, tests/analysis_one_button.gd)
var prefer_wire := false
## 할 수 있는 행동이 생긴 뒤 이만큼 프레임을 기다렸다 행동 (사람의 반응 시간 흉내, 분석용. 0 = 즉시)
var reaction_frames := 0
var _wait := 0

var _held := 0
var _cooldown := 0
var _last_building: Building


func setup(target_player: PlayerController, target_course: CourseBase) -> void:
	player = target_player
	course = target_course


func _physics_process(_delta: float) -> void:
	if player != null:
		step()


## 한 물리 프레임 분량의 판단
func step() -> void:
	if _cooldown > 0:
		_cooldown -= 1
	match player.state:
		PlayerController.State.AIRBORNE:
			if reaction_frames > 0:
				var available := player.dash.find_target().enemy != null or (_cooldown == 0 and find_anchor() != null)
				_wait = _wait + 1 if available else 0
				if _wait <= reaction_frames:
					return
				_wait = 0
			if prefer_wire and _cooldown == 0 and find_anchor() != null:
				_try_attach()
			elif player.dash.find_target().enemy != null:
				player.dash.request_dash()
				actions += 1
			elif _cooldown == 0:
				_try_attach()
		PlayerController.State.GRAPPLING:
			_held += 1
			var v := player.grapple.release_velocity
			if _held >= MIN_HOLD and ((v.x > 120.0 and v.y < -60.0) or _held > MAX_HOLD):
				player.grapple.request_release()
				_cooldown = 8
				actions += 1
			elif _held >= 10 and player.dash.find_target().enemy != null:
				player.dash.request_dash()  # 와이어 → 돌진 전환
				actions += 1


## 지금 걸 만한 건물 (없으면 null) — 분석 스크립트도 쓴다
func find_anchor() -> Building:
	return _best_anchor()[0]


func _try_attach() -> void:
	var picked: Array = _best_anchor()
	var best: Building = picked[0]
	if best == null:
		return
	player.grapple.request_attach(picked[1])
	if player.grapple.is_attached:
		_last_building = best
		_held = 0
		actions += 1


## 게임의 자동 조준(모바일 '아무 곳이나 누르기')과 같은 규칙 — GrappleController.find_auto_anchor
func _best_anchor() -> Array:
	var found := player.grapple.find_auto_anchor(_last_building)
	return [found.building, found.aim]
