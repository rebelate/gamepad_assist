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