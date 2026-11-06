"""임시 효과음 합성기 (v0.2-3) — 외부 에셋 없이 파이썬 표준 라이브러리로 짧은 wav 를 만든다.

    python tools/make_sfx.py            # assets/sfx/*.wav 를 다시 만든다

그레이박스 단계용 임시 소리다. 나중에 실제 효과음으로 바꿀 때는 같은 파일 이름으로 덮어쓰면 된다 (scripts/sfx.gd 가 이름으로 찾는다).
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / "assets" / "sfx"


def envelope(i: int, n: int, attack: float = 0.005, curve: float = 3.0) -> float:
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    return a * (1.0 - i / n) ** curve


def tone(seconds: float, f0: float, f1: float | None = None, curve: float = 3.0, harmonics=(1.0,)) -> list[float]:
    n = int(seconds * RATE)
    f1 = f0 if f1 is None else f1
    out, phase = [], 0.0
    for i in range(n):
        f = f0 + (f1 - f0) * (i / n)
        phase += 2 * math.pi * f / RATE
        s = sum(amp * math.sin(phase * (k + 1)) for k, amp in enumerate(harmonics))
        out.append(s * envelope(i, n, curve=curve))
    return out


def noise(seconds: float, smooth: float = 0.0, curve: float = 2.0, sweep: tuple[float, float] | None = None) -> list[float]:
    """smooth 0~1: 클수록 저역 통과(부드러운 바람 소리). sweep 이면 smooth 를 처음→끝으로 바꾼다"""
    n = int(seconds * RATE)
    out, last = [], 0.0
    rng = random.Random(7)
    for i in range(n):
        k = smooth if sweep is None else sweep[0] + (sweep[1] - sweep[0]) * (i / n)
        last = last * k + rng.uniform(-1, 1) * (1 - k)
        out.append(last * envelope(i, n, attack=0.01, curve=curve) * (1.0 / max(0.15, 1 - k)) * 0.35)
    return out


def mix(*tracks: list[float], gains=None) -> list[float]:
    n = max(len(t) for t in tracks)
    gains = gains or [1.0] * len(tracks)
    return [sum(g * (t[i] if i < len(t) else 0.0) for t, g in zip(tracks, gains)) for i in range(n)]


def save(name: str, samples: list[float], volume: float = 0.8) -> None:
    peak = max(1e-6, max(abs(s) for s in samples))
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(s / peak * volume * 32767)) for s in samples))
    print(f"{name}.wav  {len(samples) / RATE:.2f}s")


def main() -> None:
    # 와이어 연결: 금속성 '팅' (높은 배음이 빨리 사라짐) + 짧은 지퍼 소리
    save("wire_attach", mix(tone(0.16, 2100, 2000, curve=4, harmonics=(1.0, 0.4, 0.25)), tone(0.05, 700, 1600, curve=1.5)),
         volume=0.55)
    # 와이어 해제: 가벼운 휙
    save("wire_release", noise(0.18, sweep=(0.6, 0.9), curve=2.5), volume=0.5)
    # 돌진: 길고 강한 휙 (고역 → 저역)
    save("dash", mix(noise(0.28, sweep=(0.35, 0.85), curve=1.6), tone(0.28, 320, 140, curve=2)), volume=0.7)
    # 베기: 날카로운 타격 + 낮은 쿵
    save("slash", mix(noise(0.07, smooth=0.1, curve=3), tone(0.2, 150, 60, curve=3), tone(0.09, 1800, 900, curve=4),
                      gains=[1.0, 0.9, 0.35]), volume=0.85)
    # 사망: 내려가는 낮은 소리
    save("death", mix(tone(0.55, 320, 70, curve=1.5, harmonics=(1.0, 0.5)), noise(0.4, smooth=0.7)), volume=0.7)
    # 콤보 상승: 짧은 띵 (콤보가 오를수록 재생 속도로 음을 올린다)
    save("combo", tone(0.09, 880, 1320, curve=2.5, harmonics=(1.0, 0.3)), volume=0.45)


if __name__ == "__main__":
    main()
