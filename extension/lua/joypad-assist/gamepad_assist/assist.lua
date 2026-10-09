local USER_DEFAULTS = {
    DEADZONE = 10,
    STEERING_GAMMA = 50,

    RACE_NORMAL_RATE = 35,
    RACE_RETURN_RATE = 55,
    RACE_SPEED_SENSITIVITY = 70,
    RACE_COUNTERSTEER_GAIN = 35,
    RACE_COUNTERSTEER_MAX = 60,

    DRIFT_NORMAL_RATE = 38,
    DRIFT_RETURN_RATE = 48,
    DRIFT_SPEED_SENSITIVITY = 10,
    DRIFT_COUNTERSTEER_GAIN = 50,
    DRIFT_COUNTERSTEER_MAX = 60
}

local INTERNAL = {
    RACE_HIGH_SPEED_KMH = 60.0,
    DRIFT_HIGH_SPEED_KMH = 60.0,

    RACE_HIGH_SPEED_RATE_DAMPING = 0.10,
    DRIFT_HIGH_SPEED_RATE_DAMPING = 0.05,

    RACE_HIGH_SPEED_COUNTERSTEER = 0.70,
    RACE_YAW_DAMPING = 0.5,
    RACE_SELF_STEER_RATE = 7.0,

    DRIFT_REAR_SLIP_START = 0.20,
    DRIFT_REAR_SLIP_FULL = 1.00,

    DRIFT_YAW_START = 0.08,
    DRIFT_YAW_FULL = 0.45,

    CENTER_RETURN_MULTIPLIER = 1.20,
    COUNTERSTEER_RATE = 10.0,

    MIN_DT = 0.001,
    MAX_DT = 0.05
}

local settings = ac.INIConfig.scriptSettings():mapSection("Tweaks", USER_DEFAULTS)

local steerOutput = 0
local countersteerOutput = 0
local wasPressed = false
local settingsReloadTimer = 0

local mode = ac.storage["gamepadSteerMode:" .. ac.getCarID(0)] or "RACE"

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

    local normalized = (magnitude - deadzone) / (1 - deadzone)

    return math.sign(value) * saturate(normalized)
end

local function applyGamma(value, gamma)
    if gamma == 1 then
        return value
    end

    return math.sign(value) * math.pow(math.abs(value), gamma)
end

local function getDeadzone()
    return percent(settings.DEADZONE) * 0.30
end

local function getGamma()
    return lerp(0.50, 1.50, percent(settings.STEERING_GAMMA))
end

local function getNormalRate()
    if mode == "DRIFT" then
        return lerp(1.0, 12.0, percent(settings.DRIFT_NORMAL_RATE))
    end

    return lerp(1.0, 12.0, percent(settings.RACE_NORMAL_RATE))
end

local function getReturnRate()
    if mode == "DRIFT" then
        return lerp(1.0, 14.0, percent(settings.DRIFT_RETURN_RATE))
    end

    return lerp(1.0, 14.0, percent(settings.RACE_RETURN_RATE))
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
        sensitivity = percent(settings.DRIFT_SPEED_SENSITIVITY)
    else
        sensitivity = percent(settings.RACE_SPEED_SENSITIVITY)
    end

    return clamp(1.0 - factor * sensitivity, 0.0, 1.0)
end

local function getSteeringRates(data)
    local factor = getSpeedFactor(data)

    local damping

    if mode == "DRIFT" then
        damping = 1.0 - INTERNAL.DRIFT_HIGH_SPEED_RATE_DAMPING * factor
    else
        damping = 1.0 - INTERNAL.RACE_HIGH_SPEED_RATE_DAMPING * factor
    end

    return getNormalRate() * damping, getReturnRate() * damping
end

local function normalizedRange(value, startValue, fullValue)
    if fullValue <= startValue then
        return value >= startValue and 1 or 0
    end

    return smoothstep((value - startValue) / (fullValue - startValue))
end

local function getDriftFactor(data)
    local rearSlip = (math.abs(data.ndSlipRL) + math.abs(data.ndSlipRR)) * 0.5

    local yaw = math.abs(data.localAngularVelocity.y)

    local slipFactor = normalizedRange(rearSlip, INTERNAL.DRIFT_REAR_SLIP_START, INTERNAL.DRIFT_REAR_SLIP_FULL)

    local yawFactor = normalizedRange(yaw, INTERNAL.DRIFT_YAW_START, INTERNAL.DRIFT_YAW_FULL)

    return math.max(slipFactor, yawFactor)
end

local function getPointVelocity(position, velocity, angularVelocity)
    return {
        x = velocity.x + angularVelocity.y * position.z - angularVelocity.z * position.y,

        z = velocity.z + angularVelocity.x * position.y - angularVelocity.y * position.x
    }
end

local function getRaceSelfSteer(data)
    local vehicle = ac.getCar(0)

    if not vehicle or not vehicle.wheels or not vehicle.wheels[0] or not vehicle.wheels[1] or not vehicle.wheels[2] or
        not vehicle.wheels[3] then
        return 0
    end

    local velocity = vehicle.localVelocity
    local angular = vehicle.localAngularVelocity

    if not velocity or not angular then
        return 0
    end

    local inverse = vehicle.transform:inverse()

    local frontLeft = inverse:transformPoint(vehicle.wheels[0].position)
    local frontRight = inverse:transformPoint(vehicle.wheels[1].position)
    local rearLeft = inverse:transformPoint(vehicle.wheels[2].position)
    local rearRight = inverse:transformPoint(vehicle.wheels[3].position)

    local frontX = (frontLeft.x + frontRight.x) * 0.5
    local frontY = (frontLeft.y + frontRight.y) * 0.5
    local frontZ = (frontLeft.z + frontRight.z) * 0.5

    local rearX = (rearLeft.x + rearRight.x) * 0.5
    local rearY = (rearLeft.y + rearRight.y) * 0.5
    local rearZ = (rearLeft.z + rearRight.z) * 0.5

    local rearPosition = {
        x = rearX,
        y = rearY,
        z = rearZ
    }

    local frontPosition = {
        x = frontX,
        y = frontY,
        z = frontZ
    }

    local rearVelocity = getPointVelocity(rearPosition, velocity, angular)

    local frontVelocity = getPointVelocity(frontPosition, velocity, angular)

    local rearAngle = math.deg(math.atan2(rearVelocity.x, math.abs(rearVelocity.z)))

    local steeringLock = 35.0

    if data.steerLock and data.steerRatio and math.abs(data.steerRatio) > 0.001 then
        local measured = math.abs(data.steerLock / data.steerRatio)

        if measured > 3.0 and measured < 90.0 then
            steeringLock = measured
        end
    end

    local response = percent(settings.RACE_COUNTERSTEER_GAIN)

    local correctionExponent = 1.0 + (1.0 - math.log10(10.0 * (response * 0.9 + 0.1)))

    local normalizedRearAngle = clamp(-rearAngle / 72.0, -1.0, 1.0)

    local correctionBase =
        math.sign(normalizedRearAngle) * math.pow(math.abs(normalizedRearAngle), correctionExponent) * 72.0 /
            steeringLock

    local selfSteerCap = percent(settings.RACE_COUNTERSTEER_MAX)

    correctionBase = clamp(correctionBase, -selfSteerCap, selfSteerCap)

    local dampingForce = angular.y * INTERNAL.RACE_YAW_DAMPING * 0.15 * (30.0 / steeringLock)

    local rawSelfSteer = correctionBase + dampingForce

    local wheelbase = math.abs(frontZ - rearZ)

    local wheelbaseFactor = math.max(wheelbase / 2.5, 0.1)

    local frontSpeed = math.sqrt(frontVelocity.x * frontVelocity.x + frontVelocity.z * frontVelocity.z)

    local assistFadeIn = smoothstep((frontSpeed - 2.0 * wheelbaseFactor) / (4.0 * wheelbaseFactor))

    local speedMultiplier = lerp(1.0, INTERNAL.RACE_HIGH_SPEED_COUNTERSTEER, getSpeedFactor(data))

    return clamp(rawSelfSteer * assistFadeIn * speedMultiplier, -1.0, 1.0)
end

local function getCountersteerTarget(data, driverTarget, dt)
    if mode == "DRIFT" then
        local ffb = data.ffb

        if math.abs(ffb) < 0.001 then
            return 0
        end

        local correction = -ffb

        correction = correction * percent(settings.DRIFT_COUNTERSTEER_GAIN)

        correction = correction * getDriftFactor(data)

        local maxCountersteer = percent(settings.DRIFT_COUNTERSTEER_MAX)

        correction = clamp(correction, -maxCountersteer, maxCountersteer)

        if math.abs(driverTarget) > 0.001 then
            local sameDirection = driverTarget * correction > 0

            if sameDirection then
                correction = correction * (1.0 - math.abs(driverTarget))
            end
        end

        return correction
    end

    return getRaceSelfSteer(data)
end

local function reloadSettings(dt)
    settingsReloadTimer = settingsReloadTimer + dt

    if settingsReloadTimer < 0.25 then
        return
    end

    settingsReloadTimer = 0

    local freshSettings = ac.INIConfig.scriptSettings():mapSection("Tweaks", USER_DEFAULTS)

    for key, defaultValue in pairs(USER_DEFAULTS) do
        local value = freshSettings[key]

        if value == nil then
            value = defaultValue
        end

        settings[key] = clamp(value, 1, 100)
    end
end

local function getDriverInput(data)
    local stick = applyDeadzone(data.steerStickX, getDeadzone())

    return applyGamma(stick, getGamma())
end

local function updateRaw()
    countersteerOutput = 0
end

local function updateAssisted(data, dt)
    local driverInput = getDriverInput(data)

    local driverTarget = driverInput * getSpeedAuthority(data)

    local countersteerTarget = getCountersteerTarget(data, driverTarget, dt)

    local countersteerRate = mode == "RACE" and INTERNAL.RACE_SELF_STEER_RATE or INTERNAL.COUNTERSTEER_RATE

    countersteerOutput = smooth(countersteerOutput, countersteerTarget, countersteerRate, dt)

    local target = clamp(driverTarget + countersteerOutput, -1, 1)

    local normalRate, returnRate = getSteeringRates(data)

    local returning = math.abs(target) < math.abs(steerOutput)

    local rate = normalRate

    if returning then
        rate = returnRate * INTERNAL.CENTER_RETURN_MULTIPLIER
    end

    steerOutput = smooth(steerOutput, target, rate, dt)

    if math.abs(steerOutput) < 0.0005 and math.abs(target) < 0.0005 then
        steerOutput = 0
    end

    data.steer = clamp(steerOutput, -1, 1)

    data.vibrationLeft = saturate(math.abs(data.ndSlipL))

    data.vibrationRight = saturate(math.abs(data.ndSlipR))
end

local function showModeNotification()
    if mode == "DRIFT" then
        ac.setMessage("STEERING MODE", "DRIFT MODE")
    elseif mode == "RAW" then
        ac.setMessage("STEERING MODE", "NO ASSIST")
    else
        ac.setMessage("STEERING MODE", "RACE MODE")
    end
end

local function updateModeSwitch()
    local pressed = ac.isGamepadButtonPressed(0, ac.GamepadButton.RightThumb)

    if pressed and not wasPressed then
        if mode == "RACE" then
            mode = "DRIFT"
        elseif mode == "DRIFT" then
            mode = "RAW"
        else
            mode = "RACE"
        end

        ac.storage["gamepadSteerMode:" .. ac.getCarID(0)] = mode

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

    dt = clamp(dt, INTERNAL.MIN_DT, INTERNAL.MAX_DT)

    reloadSettings(dt)
    updateModeSwitch()

    if mode == "RAW" then
        updateRaw()
    else
        updateAssisted(data, dt)
    end
end