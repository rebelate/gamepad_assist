# Assetto Corsa CSP Gamepad Steering Assist

A lightweight CSP Lua steering assist for gamepad users.

## Features

- **R3** cycles between Race, Drift, and No Assist
- Separate Race and Drift steering behavior
- Configurable steering response and speed sensitivity
- Independent steering self-centering
- Countersteer assistance
- High-speed steering stabilization
- Slide-aware steering assistance
- Live settings reload

## Modes

### Race

Designed for stable circuit and touge driving.

- Smooth, configurable manual steering
- Independent countersteering response for faster corrections
- Reduces automatic countersteer assistance when manual steering is applied during a slide, regardless of steering direction
- Reduces opposing manual steering input during a slide
- Speed-based steering reduction
- Yaw damping and slide-aware stabilization

Manual steering and countersteering are smoothed separately. Their outputs are combined afterward, allowing the countersteer assist to react quickly without increasing the normal steering response rate.

### Drift

Designed for controlled slides and predictable countersteering.

- Configurable manual steering response
- A more progressive steering input curve than Race
- Drift-aware countersteer strength
- Countersteer assistance based on rear axle motion and yaw
- Reduced speed sensitivity
- Separate manual steering and countersteer smoothing

Drift uses the shared `STEERING_GAMMA` setting multiplied by an internal factor of `1.42`. This makes mid-range stick movements less sensitive while preserving full steering input at full stick deflection.

### No Assist

The Lua script does not apply its custom steering assistance.

Assetto Corsa/CSP's normal gamepad steering behavior is used instead.

## Controls

Press **R3 / Right Thumb** to cycle modes:

```text
RACE → DRIFT → NO ASSIST → RACE
```

The selected mode is saved per car.

## Configuration

All user-configurable values use a **1–100** scale.

Settings reload automatically while the script is running.

### Basic

```ini
DEADZONE=10
STEERING_GAMMA=65
```

- `DEADZONE` — Reduces small stick movements near the center.
  - Increase = larger deadzone
  - Decrease = smaller deadzone

- `STEERING_GAMMA` — Controls the steering response curve.
  - Increase = softer response to small stick movements
  - Decrease = stronger response near the center
  - Race uses the configured gamma directly.
  - Drift multiplies the calculated gamma by `1.42`.

### Race

```ini
RACE_NORMAL_RATE=15
RACE_RETURN_RATE=50
RACE_SPEED_SENSITIVITY=50
RACE_COUNTERSTEER_GAIN=50
RACE_COUNTERSTEER_MAX=60
RACE_SLIDE_INPUT_REDUCTION=35
```

- `RACE_NORMAL_RATE` — How quickly manual steering follows the stick.
  - Increase = faster response
  - Decrease = smoother, slower response

- `RACE_RETURN_RATE` — How quickly manual steering returns toward the requested steering input when reducing input.
  - Increase = faster return
  - Decrease = slower return

- `RACE_SPEED_SENSITIVITY` — Reduces driver steering authority at high speed.
  - Increase = less steering input at high speed
  - Decrease = more steering input at high speed

- `RACE_COUNTERSTEER_GAIN` — Controls the strength of automatic countersteering.
  - Increase = stronger correction
  - Decrease = weaker correction

- `RACE_COUNTERSTEER_MAX` — Limits the maximum automatic countersteering amount.
  - Increase = larger possible correction
  - Decrease = smaller possible correction

- `RACE_SLIDE_INPUT_REDUCTION` — Controls how strongly manual input and automatic countersteering are reduced during a detected slide.
  - Automatic countersteering is reduced proportionally to the slide factor and the magnitude of manual input, regardless of steering direction.
  - Opposing manual steering input is also reduced during a slide.
  - Increase = stronger reduction
  - Decrease = weaker reduction

**Note:** Race countersteering has its own internal response rate, separate from `RACE_NORMAL_RATE`. This allows faster corrections without making normal steering follow the stick faster.

### Drift

```ini
DRIFT_NORMAL_RATE=10
DRIFT_RETURN_RATE=48
DRIFT_SPEED_SENSITIVITY=10
DRIFT_COUNTERSTEER_GAIN=50
DRIFT_COUNTERSTEER_MAX=45
```

- `DRIFT_NORMAL_RATE` — How quickly steering follows the stick.
  - Increase = faster response
  - Decrease = smoother, slower response

- `DRIFT_RETURN_RATE` — How quickly steering returns toward the requested steering input when reducing input.
  - Increase = faster return
  - Decrease = slower return

- `DRIFT_SPEED_SENSITIVITY` — Reduces driver steering authority at high speed.
  - Increase = less steering input at high speed
  - Decrease = more steering input at high speed

- `DRIFT_COUNTERSTEER_GAIN` — Controls countersteering assistance based on drift conditions and steering feedback.
  - Increase = stronger correction
  - Decrease = weaker correction

- `DRIFT_COUNTERSTEER_MAX` — Limits the maximum countersteering correction.
  - Increase = larger possible correction
  - Decrease = smaller possible correction

## Internal Settings

The following values are defined in the Lua script rather than the user settings section:

- `RACE_COUNTERSTEER_RATE` — Controls how quickly Race countersteering reacts.
- `DRIFT_COUNTERSTEER_RATE` — Controls how quickly Drift countersteering reacts.
- `DRIFT_HIGH_SPEED_RATE_DAMPING` — Slightly reduces Drift steering response rates at high speed.
- `DRIFT_INPUT_PRIORITY` — Reduces Drift countersteering assistance when manual input opposes it.
- `RETURN_RATE_MULTIPLIER` — Multiplies the manual steering return rate.
- High-speed thresholds, slide detection thresholds, and yaw damping — Control when and how the assist responds.

These internal values do not need to be added to the `[Tweaks]` configuration section.
