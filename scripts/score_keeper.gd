## 점수·콤보 계산 (기획서 §11, v0.2-2).
##
## - 기본 점수 = 최대 도달 X 기준 거리 × points_per_px (§11 [확정] 거리 비례, [MVP 제안] 뒤로 밀려도 다시 얻지 않음)
## - 콤보 = 의미 있는 액션만 센다 (§11 [MVP 제안]): 건물에 와이어 연결, 돌진 처치.
##   와이어는 같은 건물에는 한 번만 센다 (v0.2-2 리뷰 2번) — 같은 건물에 걸었다 놓기를 반복하거나 좌클릭 연타로는 오르지 않는다.
##   풀에서 다시 배치된 건물은 새 건물로 본다 (Building.serial).
## - combo_window 안에 다음 액션을 성공하면 콤보가 이어지고, 콤보 2 부터 액션마다 보너스 = 기본 × 배율(콤보가 늘수록 커짐).
## - 콤보가 끊기는 조건: 시간 초과, 사망, 몸 충돌(reset_on_bump, v0.2-2 리뷰 3번으로 켬).
class_name ScoreKeeper
extends Node

signal combo_changed(combo: int)
signal points_awarded(points: int, reason: String)

var tuning: ScoreTuning
var combo := 0
var best_combo := 0
## 콤보가 끊기기까지 남은 시간 (s)
var combo_time_left := 0.0
## 콤보 보너스로 얻은 점수 합계
var combo_points := 0
## 마지막으로 받은 보너스 (표시용)
var last_bonus := 0

## 이미 콤보로 센 건물: 인스턴스 ID → 그때의 Building.serial
var _counted_buildings := {}


func setup(player: PlayerController, score_tuning: ScoreTuning) -> void:
	tuning = score_tuning
	player.grapple.attached.connect(_on_wire_attached)
	player.dash.dash_hit.connect(_on_dash_hit)
	player.bumped.connect(_on_bumped)
	player.died.connect(func(_reason: String) -> void: _break_combo())


func _physics_process(delta: float) -> void:
	if combo <= 0:
		return
	combo_time_left -= delta
	if combo_time_left <= 0.0:
		_break_combo()


func distance_points(distance_px: float) -> int:
	return int(distance_px * tuning.points_per_px)


func total(distance_px: float) -> int:
	return distance_points(distance_px) + combo_points


## 지금 콤보에서 다음 액션이 받을 배율 (콤보 2 = ×1.0)
func multiplier_for(next_combo: int) -> float:
	return minf(1.0 + tuning.combo_multiplier_step * maxf(next_combo - 2, 0), tuning.max_combo_multiplier)


func _on_wire_attached(_anchor: Vector2, building: Building) -> void:
	var key := building.get_instance_id()
	if _counted_buildings.get(key, -1) == building.serial:
		return  # 같은 건물은 한 번만 (§11: 좌클릭 연타로 콤보를 올릴 수 없게)
	_counted_buildings[key] = building.serial
	_register("wire")


func _on_dash_hit(_enemy: Enemy) -> void:
	_register("slash")


func _on_bumped(_collider: Object) -> void:
	if tuning.reset_on_bump:
		_break_combo()


func _register(reason: String) -> void:
	combo = combo + 1 if combo_time_left > 0.0 else 1
	combo_time_left = tuning.combo_window
	best_combo = maxi(best_combo, combo)
	last_bonus = 0
	if combo >= 2:
		last_bonus = int(round(tuning.combo_base_points * multiplier_for(combo)))
		combo_points += last_bonus
		points_awarded.emit(last_bonus, reason)
	combo_changed.emit(combo)


func _break_combo() -> void:
	if combo == 0:
		return
	combo = 0
	combo_time_left = 0.0
	combo_changed.emit(0)
