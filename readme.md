# Assetto Corsa CSP Gamepad Steering Assist

A lightweight CSP Lua steering assist for gamepad users.

## Features

- **R3** cycles between:
  - Race
  - Drift
  - No Assist
- Separate Race and Drift steering behavior
- Configurable steering response
- Configurable speed sensitivity
- Independent steering self-centering
- Smooth countersteer assist
- High-speed steering stabilization
- Live settings reload

## Modes

### Race

Designed for stable circuit and touge driving.

- Moderate steering response
- Gentle countersteer
- Speed-based steering reduction
- Stronger self-centering

### Drift

Designed for controlled slides and easy countersteering.

- Slightly faster steering response
- Stronger countersteer
- Drift-aware countersteer strength
- Reduced speed sensitivity

### No Assist

Lua does not modify `data.steer`.

AC/CSP's normal gamepad steering behavior is used instead.

## Controls

Press **R3 / Right Thumb** to cycle:

```text
RACE → DRIFT → NO ASSIST → RACE
```
# Config

All values: **1–100**

## Basic

```ini
DEADZONE=10
STEERING_GAMMA=50
```

- `DEADZONE` — Stick deadzone.
  - Increase = less sensitive
  - Decrease = more sensitive
  - Range: 1–100

- `STEERING_GAMMA` — Steering response around center.
  - Increase = smoother
  - Decrease = more sensitive
  - Range: 1–100

## Race

```ini
RACE_NORMAL_RATE=35
RACE_RETURN_RATE=55
RACE_SPEED_SENSITIVITY=70
RACE_COUNTERSTEER_GAIN=5
RACE_COUNTERSTEER_MAX=30
```

- `RACE_NORMAL_RATE` — How fast steering follows the stick.
  - Increase = faster
  - Decrease = smoother
  - Range: 1–100

- `RACE_RETURN_RATE` — How fast steering returns to center.
  - Increase = faster return
  - Decrease = slower return
  - Range: 1–100

- `RACE_SPEED_SENSITIVITY` — Reduces steering at high speed.
  - Increase = more stable
  - Decrease = more steering
  - Range: 1–100

- `RACE_COUNTERSTEER_GAIN` — Countersteer strength.
  - Increase = stronger assist
  - Decrease = weaker assist
  - Range: 1–100

- `RACE_COUNTERSTEER_MAX` — Maximum countersteer.
  - Increase = larger correction
  - Decrease = smaller correction
  - Range: 1–100

## Drift

```ini
DRIFT_NORMAL_RATE=38
DRIFT_RETURN_RATE=48
DRIFT_SPEED_SENSITIVITY=10
DRIFT_COUNTERSTEER_GAIN=50
DRIFT_COUNTERSTEER_MAX=60
```

- `DRIFT_NORMAL_RATE` — How fast steering follows the stick.
  - Increase = faster
  - Decrease = smoother
  - Range: 1–100

- `DRIFT_RETURN_RATE` — How fast steering returns to center.
  - Increase = faster return
  - Decrease = slower return
  - Range: 1–100

- `DRIFT_SPEED_SENSITIVITY` — Reduces steering at high speed.
  - Increase = more stable
  - Decrease = more steering
  - Range: 1–100

- `DRIFT_COUNTERSTEER_GAIN` — Countersteer strength.
  - Increase = stronger assist
  - Decrease = weaker assist
  - Range: 1–100

- `DRIFT_COUNTERSTEER_MAX` — Maximum countersteer.
  - Increase = larger correction
  - Decrease = smaller correction
  - Range: 1–100
