## 점수·콤보 튜닝값 (기획서 §11). 모든 숫자는 [튜닝] 임시값이다.
class_name ScoreTuning
extends Resource

@export_group("거리 점수")
## 거리 점수 비율 (§11 [확정] 이동 거리에 비례): 최대 도달 X 1px 당 점수
@export var points_per_px: float = 0.1
## 화면에 보이는 거리 단위 (px → m)
@export var px_per_meter: float = 20.0

@export_group("콤보")
## ComboWindow (s): 이 시간 안에 다음 액션(새 건물에 와이어 연결·돌진 처치)을 성공해야 콤보가 이어진다
@export var combo_window: float = 2.5
## 콤보 2 이상일 때 액션 1회당 기본 보너스 점수.
## v0.2-2 리뷰 6번 "거리 점수와 비슷한 비중": 100/0.5/×5 이면 봇 60초에 보너스 15000~30000 ≫ 거리 약 3000 →
## 20/0.25/×3 으로 보너스 2000~3700 ≈ 거리 2700~3500
@export var combo_base_points: int = 20
## ComboMultiplier: 콤보가 하나 늘 때마다 보너스 배율 증가량 (콤보 2 = ×1.0, 3 = ×1.25, …)
@export var combo_multiplier_step: float = 0.25
@export var max_combo_multiplier: float = 3.0
## 콤보 초기화 조건: 건물·적에 몸으로 부딪히면 콤보를 끊는다 (v0.2-2 리뷰 3번: 켬. 끄면 시간 초과·사망만)
@export var reset_on_bump: bool = true
