
local USER_DEFAULTS = {
    DEADZONE = 1,
    STEERING_GAMMA = 65,

    RACE_NORMAL_RATE = 15,
    RACE_RETURN_RATE = 30,
    RACE_SPEED_SENSITIVITY = 50,
    RACE_COUNTERSTEER_GAIN = 50,
    RACE_COUNTERSTEER_MAX = 60,
    RACE_SLIDE_INPUT_REDUCTION = 35,

    DRIFT_NORMAL_RATE = 10,
    DRIFT_RETURN_RATE = 30,
    DRIFT_SPEED_SENSITIVITY = 10,
    DRIFT_COUNTERSTEER_GAIN = 50,
    DRIFT_COUNTERSTEER_MAX = 60,
    DRIFT_SLIDE_INPUT_REDUCTION = 10,
}

local INTERNAL = {
    HIGH_SPEED = {
        RACE = 160.0,
        DRIFT = 100.0,
    },

    YAW_DAMPING = 0.50,
    COUNTERSTEER_RATE = 99.0,

    SLIDE = {
        SLIP_START = 0.20,
        SLIP_FULL = 1.00,
        YAW_START = 0.08,
        YAW_FULL = 0.45,
        AXLE_START = 2.0,
        AXLE_FULL = 15.0,
    },

    MIN_DT = 0.001,
    MAX_DT = 0.05,
}

local settings = ac.INIConfig.scriptSettings():mapSection(
    "Tweaks",
    USER_DEFAULTS
)

local manualSteer = 0
local assistSteer = 0

local wasPressed = false
local settingsReloadTimer = 0

local mode = ac.storage["gamepadSteerMode:" .. ac.getCarID(0)] or "RACE"

if mode ~= "RACE" and mode ~= "DRIFT" and mode ~= "RAW" then
    mode = "RACE"
end

local function clamp(x, min, max)
    return math.max(min, math.min(max, x))
end

local function saturate(x)
    return clamp(x, 0, 1)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function mapSetting(value, min, max)
    return lerp(min, max, saturate(value / 100))
end

local function smoothstep(x)
    x = saturate(x)
    return x * x * (3 - 2 * x)
end

local function smooth(current, target, rate, dt)
    local amount = 1 - math.exp(-rate * dt)
    return current + (target - current) * amount
end

local function modeSetting(raceKey, driftKey)
    local key = mode == "DRIFT" and driftKey or raceKey
    return settings[key]
end

local function applyDeadzone(value, deadzone)
    local magnitude = math.abs(value)

    if magnitude <= deadzone then
        return 0
    end

    return math.sign(value) * saturate(
        (magnitude - deadzone) / (1 - deadzone)
    )
end

local function getDriverInput(data)
    local input = applyDeadzone(
        data.steerStickX,
        percent and percent(settings.DEADZONE) * 0.30
            or saturate(settings.DEADZONE / 100) * 0.30
    )

    if input == 0 then
        return 0
    end

    local gamma = mapSetting(settings.STEERING_GAMMA, 0.7, 2.0)

    return math.sign(input) * math.pow(math.abs(input), gamma)
end

local function getNormalRate()
    return mapSetting(
        modeSetting("RACE_NORMAL_RATE", "DRIFT_NORMAL_RATE"),
        1.0,
        10.0
    )
end

local function getReturnRate()
    return mapSetting(
        modeSetting("RACE_RETURN_RATE", "DRIFT_RETURN_RATE"),
        2.0,
        20.0
    )
end

local function getSteeringAuthority(data)
    local sensitivity = saturate(
        modeSetting("RACE_SPEED_SENSITIVITY", "DRIFT_SPEED_SENSITIVITY") / 100
    )

    local speedFactor = smoothstep(
        math.abs(data.speedKmh) / INTERNAL.HIGH_SPEED[mode]
    )

    return 1.0 - speedFactor * sensitivity
end

local function normalizedRange(value, startValue, fullValue)
    if fullValue <= startValue then
        return value >= startValue and 1 or 0
    end

    return smoothstep(
        (value - startValue) / (fullValue - startValue)
    )
end

local function getPointVelocity(position, velocity, angular)
    return {
        x = velocity.x
            + angular.y * position.z
            - angular.z * position.y,

        z = velocity.z
            + angular.x * position.y
            - angular.y * position.x,
    }
end

local function getAxleData()
    local car = ac.getCar(0)

    if not car or not car.wheels
        or not car.wheels[0]
        or not car.wheels[1]
        or not car.wheels[2]
        or not car.wheels[3] then
        return nil
    end

    local velocity = car.localVelocity
    local angular = car.localAngularVelocity

    if not velocity or not angular then
        return nil
    end

    local inverse = car.transform:inverse()

    local fl = inverse:transformPoint(car.wheels[0].position)
    local fr = inverse:transformPoint(car.wheels[1].position)
    local rl = inverse:transformPoint(car.wheels[2].position)
    local rr = inverse:transformPoint(car.wheels[3].position)

    local front = {
        x = (fl.x + fr.x) * 0.5,
        y = (fl.y + fr.y) * 0.5,
        z = (fl.z + fr.z) * 0.5,
    }

    local rear = {
        x = (rl.x + rr.x) * 0.5,
        y = (rl.y + rr.y) * 0.5,
        z = (rl.z + rr.z) * 0.5,
    }

    local frontVelocity = getPointVelocity(front, velocity, angular)
    local rearVelocity = getPointVelocity(rear, velocity, angular)

    local frontAngle = math.deg(math.atan2(
        frontVelocity.x,
        math.abs(frontVelocity.z)
    ))

    local rearAngle = math.deg(math.atan2(
        rearVelocity.x,
        math.abs(rearVelocity.z)
    ))

    local frontSpeed = math.sqrt(
        frontVelocity.x * frontVelocity.x
        + frontVelocity.z * frontVelocity.z
    )

    return {
        frontZ = front.z,
        rearZ = rear.z,
        frontSpeed = frontSpeed,
        rearAngle = rearAngle,
        angleDifference = math.abs(frontAngle - rearAngle),
    }
end

local function getSlideFactor(data, axle)
    local slide = INTERNAL.SLIDE

    local rearSlip = (
        math.abs(data.ndSlipRL)
        + math.abs(data.ndSlipRR)
    ) * 0.5

    local yaw = math.abs(data.localAngularVelocity.y)

    local factor = math.max(
        normalizedRange(rearSlip, slide.SLIP_START, slide.SLIP_FULL),
        normalizedRange(yaw, slide.YAW_START, slide.YAW_FULL)
    )

    if axle then
        factor = math.max(
            factor,
            normalizedRange(
                axle.angleDifference,
                slide.AXLE_START,
                slide.AXLE_FULL
            )
        )
    end

    return factor
end

local function calculateAssist(data, axle)
    if not axle then
        return 0
    end

    local car = ac.getCar(0)

    if not car or not car.localAngularVelocity then
        return 0
    end

    local angular = car.localAngularVelocity
    local steeringLock = 35.0

    if data.steerLock and data.steerRatio
        and math.abs(data.steerRatio) > 0.001 then
        local measured = math.abs(data.steerLock / data.steerRatio)

        if measured > 3.0 and measured < 90.0 then
            steeringLock = measured
        end
    end

    local gain = modeSetting(
        "RACE_COUNTERSTEER_GAIN",
        "DRIFT_COUNTERSTEER_GAIN"
    )

    local maxSteer = modeSetting(
        "RACE_COUNTERSTEER_MAX",
        "DRIFT_COUNTERSTEER_MAX"
    )

    local response = saturate(gain / 100)

    local exponent = 1.0 + (
        1.0 - math.log10(10.0 * (response * 0.9 + 0.1))
    )

    local normalizedAngle = clamp(
        -axle.rearAngle / 72.0,
        -1.0,
        1.0
    )

    local correction = math.sign(normalizedAngle)
        * math.pow(math.abs(normalizedAngle), exponent)
        * 72.0 / steeringLock

    correction = clamp(
        correction,
        -saturate(maxSteer / 100),
        saturate(maxSteer / 100)
    )

    local damping = angular.y
        * INTERNAL.YAW_DAMPING
        * 0.15
        * (30.0 / steeringLock)

    local wheelbase = math.abs(axle.frontZ - axle.rearZ)
    local wheelbaseFactor = math.max(wheelbase / 2.5, 0.1)

    local fade = smoothstep(
        (axle.frontSpeed - 2.0 * wheelbaseFactor)
        / (4.0 * wheelbaseFactor)
    )

    return clamp((correction + damping) * fade, -1.0, 1.0)
end

local function getSlideInputReduction()
    return saturate(
        modeSetting(
            "RACE_SLIDE_INPUT_REDUCTION",
            "DRIFT_SLIDE_INPUT_REDUCTION"
        ) / 100
    )
end

local function reloadSettings(dt)
    settingsReloadTimer = settingsReloadTimer + dt

    if settingsReloadTimer < 2 then
        return
    end

    settingsReloadTimer = 0

    local fresh = ac.INIConfig.scriptSettings():mapSection(
        "Tweaks",
        USER_DEFAULTS
    )

    for key, defaultValue in pairs(USER_DEFAULTS) do
        settings[key] = clamp(
            fresh[key] or defaultValue,
            0,
            100
        )
    end
end

local function resetSteering()
    manualSteer = 0
    assistSteer = 0
end

local function updateAssisted(data, dt)
    local manualTarget = getDriverInput(data)
        * getSteeringAuthority(data)

    local axle = getAxleData()
    local assistTarget = calculateAssist(data, axle)

    local slide = getSlideFactor(data, axle)
    local reduction = getSlideInputReduction()

    assistTarget = assistTarget * (
        1.0 - slide * reduction * math.abs(manualTarget)
    )

    if manualTarget * assistTarget < 0 then
        manualTarget = manualTarget * (
            1.0 - slide * reduction
        )
    end

    assistSteer = smooth(
        assistSteer,
        assistTarget,
        INTERNAL.COUNTERSTEER_RATE,
        dt
    )

    local driverRate = getNormalRate()

    if manualTarget * manualSteer >= 0
        and math.abs(manualTarget) < math.abs(manualSteer) then
        driverRate = getReturnRate()
    end

    manualSteer = smooth(
        manualSteer,
        manualTarget,
        driverRate,
        dt
    )

    if math.abs(manualSteer) < 0.0005
        and math.abs(manualTarget) < 0.0005 then
        manualSteer = 0
    end

    data.steer = clamp(
        manualSteer + assistSteer,
        -1.0,
        1.0
    )

    data.vibrationLeft = saturate(math.abs(data.ndSlipL))
    data.vibrationRight = saturate(math.abs(data.ndSlipR))
end

local function updateRaw()
    resetSteering()
end

local function showModeNotification()
    local message = mode == "DRIFT" and "DRIFT MODE"
        or mode == "RAW" and "NO ASSIST"
        or "RACE MODE"

    ac.setMessage("STEERING MODE", message)
end

local function updateModeSwitch()
    local pressed = ac.isGamepadButtonPressed(
        0,
        ac.GamepadButton.RightThumb
    )

    if pressed and not wasPressed then
        mode = mode == "RACE" and "DRIFT"
            or mode == "DRIFT" and "RAW"
            or "RACE"

        ac.storage["gamepadSteerMode:" .. ac.getCarID(0)] = mode

        resetSteering()
        showModeNotification()
    end

    wasPressed = pressed
end

function script.update(dt)
    local data = ac.getJoypadState()

    if not data then
        return
    end

    dt = clamp(dt, INTERNAL.MIN_DT, INTERNAL.MAX_DT)

    reloadSettings(dt)
    updateModeSwitch()

    if mode == "RAW" then
        updateRaw()
    else
        updateAssisted(data, dt)
    end
end
