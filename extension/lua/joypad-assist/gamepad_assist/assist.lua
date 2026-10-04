local USER_DEFAULTS = {
    DEADZONE = 10,
    STEERING_GAMMA = 50,

    RACE_NORMAL_RATE = 35,
    RACE_RETURN_RATE = 55,
    RACE_SPEED_SENSITIVITY = 70,
    RACE_COUNTERSTEER_GAIN = 5,
    RACE_COUNTERSTEER_MAX = 30,

    DRIFT_NORMAL_RATE = 38,
    DRIFT_RETURN_RATE = 48,
    DRIFT_SPEED_SENSITIVITY = 10,
    DRIFT_COUNTERSTEER_GAIN = 32,
    DRIFT_COUNTERSTEER_MAX = 42,
}

local INTERNAL = {
    RACE_HIGH_SPEED_KMH = 200.0,
    DRIFT_HIGH_SPEED_KMH = 200.0,

    RACE_HIGH_SPEED_RATE_DAMPING = 0.10,
    DRIFT_HIGH_SPEED_RATE_DAMPING = 0.05,

    RACE_HIGH_SPEED_COUNTERSTEER = 0.70,

    DRIFT_REAR_SLIP_START = 0.20,
    DRIFT_REAR_SLIP_FULL = 1.00,

    DRIFT_YAW_START = 0.08,
    DRIFT_YAW_FULL = 0.45,

    DRIFT_ASSIST_MIN = 0.10,
    DRIFT_ASSIST_MAX = 1.00,

    CENTER_RETURN_MULTIPLIER = 1.20,
    COUNTERSTEER_RATE = 8.0,

    MIN_DT = 0.001,
    MAX_DT = 0.05,
}

local settings = ac.INIConfig.scriptSettings():mapSection(
    "Tweaks",
    USER_DEFAULTS
)

local steerOutput = 0
local countersteerOutput = 0
local wasPressed = false
local settingsReloadTimer = 0

local mode =
    ac.storage["gamepadSteerMode:" .. ac.getCarID(0)] or "RACE"

if mode ~= "RACE" and mode ~= "DRIFT" and mode ~= "RAW" then
    mode = "RACE"
end

local function clamp(x, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, x))
end

local function saturate(x)
    return clamp(x, 0, 1)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function smoothstep(x)
    x = saturate(x)
    return x * x * (3 - 2 * x)
end

local function smooth(current, target, rate, dt)
    if rate <= 0 then
        return current
    end

    local amount = 1 - math.exp(-rate * dt)
    return current + (target - current) * amount
end

local function percent(value)
    return saturate(value / 100)
end

local function applyDeadzone(value, deadzone)
    local magnitude = math.abs(value)

    if magnitude <= deadzone then
        return 0
    end

    local normalized =
        (magnitude - deadzone) /
        (1 - deadzone)

    return math.sign(value) * saturate(normalized)
end

local function applyGamma(value, gamma)
    if gamma == 1 then
        return value
    end

    return math.sign(value) *
        math.pow(math.abs(value), gamma)
end

local function getDeadzone()
    return percent(settings.DEADZONE) * 0.30
end

local function getGamma()
    return lerp(
        0.50,
        1.50,
        percent(settings.STEERING_GAMMA)
    )
end

local function getNormalRate()
    if mode == "DRIFT" then
        return lerp(
            1.0,
            12.0,
            percent(settings.DRIFT_NORMAL_RATE)
        )
    end

    return lerp(
        1.0,
        12.0,
        percent(settings.RACE_NORMAL_RATE)
    )
end

local function getReturnRate()
    if mode == "DRIFT" then
        return lerp(
            1.0,
            14.0,
            percent(settings.DRIFT_RETURN_RATE)
        )
    end

    return lerp(
        1.0,
        14.0,
        percent(settings.RACE_RETURN_RATE)
    )
end

local function getHighSpeedKmh()
    if mode == "DRIFT" then
        return INTERNAL.DRIFT_HIGH_SPEED_KMH
    end

    return INTERNAL.RACE_HIGH_SPEED_KMH
end

local function getSpeedFactor(data)
    local speedKmh = math.abs(data.speedKmh)
    local threshold = getHighSpeedKmh()

    if threshold <= 0 then
        return 1
    end

    return smoothstep(speedKmh / threshold)
end

local function getSpeedAuthority(data)
    local factor = getSpeedFactor(data)

    local sensitivity

    if mode == "DRIFT" then
        sensitivity =
            percent(settings.DRIFT_SPEED_SENSITIVITY)
    else
        sensitivity =
            percent(settings.RACE_SPEED_SENSITIVITY)
    end

    return clamp(
        1.0 - factor * sensitivity,
        0.0,
        1.0
    )
end

local function getSteeringRates(data)
    local factor = getSpeedFactor(data)

    local damping

    if mode == "DRIFT" then
        damping =
            1.0 -
            INTERNAL.DRIFT_HIGH_SPEED_RATE_DAMPING * factor
    else
        damping =
            1.0 -
            INTERNAL.RACE_HIGH_SPEED_RATE_DAMPING * factor
    end

    return getNormalRate() * damping,
        getReturnRate() * damping
end

local function normalizedRange(value, startValue, fullValue)
    if fullValue <= startValue then
        return value >= startValue and 1 or 0
    end

    return smoothstep(
        (value - startValue) /
        (fullValue - startValue)
    )
end

local function getDriftFactor(data)
    local rearSlip =
        (
            math.abs(data.ndSlipRL) +
            math.abs(data.ndSlipRR)
        ) * 0.5

    local yaw =
        math.abs(data.localAngularVelocity.y)

    local slipFactor =
        normalizedRange(
            rearSlip,
            INTERNAL.DRIFT_REAR_SLIP_START,
            INTERNAL.DRIFT_REAR_SLIP_FULL
        )

    local yawFactor =
        normalizedRange(
            yaw,
            INTERNAL.DRIFT_YAW_START,
            INTERNAL.DRIFT_YAW_FULL
        )

    return lerp(
        INTERNAL.DRIFT_ASSIST_MIN,
        INTERNAL.DRIFT_ASSIST_MAX,
        math.max(slipFactor, yawFactor)
    )
end

local function getCountersteerTarget(data, driverTarget)
    local ffb = data.ffb

    if math.abs(ffb) < 0.001 then
        return 0
    end

    local correction = -ffb

    if math.abs(driverTarget) > 0.001 and
        driverTarget * correction > 0 then
        return 0
    end

    if mode == "DRIFT" then
        correction =
            correction *
            percent(settings.DRIFT_COUNTERSTEER_GAIN)

        correction =
            correction *
            getDriftFactor(data)

        return clamp(
            correction,
            -percent(settings.DRIFT_COUNTERSTEER_MAX),
            percent(settings.DRIFT_COUNTERSTEER_MAX)
        )
    end

    local speedFactor =
        getSpeedFactor(data)

    local speedMultiplier =
        lerp(
            1.0,
            INTERNAL.RACE_HIGH_SPEED_COUNTERSTEER,
            speedFactor
        )

    correction =
        correction *
        percent(settings.RACE_COUNTERSTEER_GAIN) *
        speedMultiplier

    return clamp(
        correction,
        -percent(settings.RACE_COUNTERSTEER_MAX),
        percent(settings.RACE_COUNTERSTEER_MAX)
    )
end

local function reloadSettings(dt)
    settingsReloadTimer =
        settingsReloadTimer + dt

    if settingsReloadTimer < 0.25 then
        return
    end

    settingsReloadTimer = 0

    local freshSettings =
        ac.INIConfig.scriptSettings():mapSection(
            "Tweaks",
            USER_DEFAULTS
        )

    for key, defaultValue in pairs(USER_DEFAULTS) do
        local value = freshSettings[key]

        if value == nil then
            value = defaultValue
        end

        settings[key] =
            clamp(value, 1, 100)
    end
end

local function getDriverInput(data)
    local stick =
        applyDeadzone(
            data.steerStickX,
            getDeadzone()
        )

    return applyGamma(
        stick,
        getGamma()
    )
end

local function updateRaw()
    countersteerOutput = 0
end

local function updateAssisted(data, dt)
    local driverInput =
        getDriverInput(data)

    local driverTarget =
        driverInput *
        getSpeedAuthority(data)

    local countersteerTarget =
        getCountersteerTarget(
            data,
            driverTarget
        )

    countersteerOutput =
        smooth(
            countersteerOutput,
            countersteerTarget,
            INTERNAL.COUNTERSTEER_RATE,
            dt
        )

    local target =
        clamp(
            driverTarget + countersteerOutput,
            -1,
            1
        )

    local normalRate, returnRate =
        getSteeringRates(data)

    local returning =
        math.abs(target) < math.abs(steerOutput)

    local rate = normalRate

    if returning then
        rate =
            returnRate *
            INTERNAL.CENTER_RETURN_MULTIPLIER
    end

    steerOutput =
        smooth(
            steerOutput,
            target,
            rate,
            dt
        )

    if math.abs(steerOutput) < 0.0005 and
        math.abs(target) < 0.0005 then
        steerOutput = 0
    end

    data.steer =
        clamp(
            steerOutput,
            -1,
            1
        )

    data.vibrationLeft =
        saturate(math.abs(data.ndSlipL))

    data.vibrationRight =
        saturate(math.abs(data.ndSlipR))
end

local function showModeNotification()
    if mode == "DRIFT" then
        ac.setMessage(
            "STEERING MODE",
            "DRIFT MODE"
        )
    elseif mode == "RAW" then
        ac.setMessage(
            "STEERING MODE",
            "NO ASSIST"
        )
    else
        ac.setMessage(
            "STEERING MODE",
            "RACE MODE"
        )
    end
end

local function updateModeSwitch()
    local pressed =
        ac.isGamepadButtonPressed(
            0,
            ac.GamepadButton.RightThumb
        )

    if pressed and not wasPressed then
        if mode == "RACE" then
            mode = "DRIFT"
        elseif mode == "DRIFT" then
            mode = "RAW"
        else
            mode = "RACE"
        end

        ac.storage[
            "gamepadSteerMode:" ..
            ac.getCarID(0)
        ] = mode

        steerOutput = 0
        countersteerOutput = 0

        showModeNotification()
    end

    wasPressed = pressed
end

ac.onCarJumped(function()
    steerOutput = 0
    countersteerOutput = 0
end)

function script.update(dt)
    local data = ac.getJoypadState()

    if not data then
        return
    end

    dt =
        clamp(
            dt,
            INTERNAL.MIN_DT,
            INTERNAL.MAX_DT
        )

    reloadSettings(dt)
    updateModeSwitch()

    if mode == "RAW" then
        updateRaw()
    else
        updateAssisted(data, dt)
    end
end