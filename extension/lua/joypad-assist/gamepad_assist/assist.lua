local USER_DEFAULTS = {
    DEADZONE = 10,
    STEERING_GAMMA = 65,

    RACE_NORMAL_RATE = 15,
    RACE_RETURN_RATE = 50,
    RACE_SPEED_SENSITIVITY = 50,
    RACE_COUNTERSTEER_GAIN = 50,
    RACE_COUNTERSTEER_MAX = 60,
    RACE_SLIDE_INPUT_REDUCTION = 35,

    DRIFT_NORMAL_RATE = 10,
    DRIFT_RETURN_RATE = 48,
    DRIFT_SPEED_SENSITIVITY = 10,
    DRIFT_COUNTERSTEER_GAIN = 50,
    DRIFT_COUNTERSTEER_MAX = 45,
}

local INTERNAL = {
    RACE_SPEED_START_KMH = 80.0,
    RACE_HIGH_SPEED_KMH = 160.0,
    DRIFT_HIGH_SPEED_KMH = 60.0,
    DRIFT_HIGH_SPEED_RATE_DAMPING = 0.05,

    RACE_YAW_DAMPING = 0.50,
    DRIFT_YAW_DAMPING = 0.35,

    RACE_COUNTERSTEER_RATE = 99.0,
    DRIFT_COUNTERSTEER_RATE = 99.0,

    RACE_SLIDE_SLIP_START = 0.20,
    RACE_SLIDE_SLIP_FULL = 1.00,
    RACE_SLIDE_YAW_START = 0.08,
    RACE_SLIDE_YAW_FULL = 0.45,

    DRIFT_REAR_SLIP_START = 0.20,
    DRIFT_REAR_SLIP_FULL = 1.00,
    DRIFT_YAW_START = 0.08,
    DRIFT_YAW_FULL = 0.45,

    DRIFT_INPUT_PRIORITY = 0.65,
    RETURN_RATE_MULTIPLIER = 1.20,

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

local mode = ac.storage["gamepadSteerMode:" .. ac.getCarID(0)] or "RACE"

if mode ~= "RACE" and mode ~= "DRIFT" and mode ~= "RAW" then
    mode = "RACE"
end

local function clamp(x, lo, hi)
    return math.max(lo, math.min(hi, x))
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

    return math.sign(value) * saturate(
        (magnitude - deadzone) / (1 - deadzone)
    )
end

local function getDriverInput(data)
    local input = applyDeadzone(
        data.steerStickX,
        percent(settings.DEADZONE) * 0.30
    )

    if input == 0 then
        return 0
    end

    local gamma = lerp(
        0.7,
        2.0,
        percent(settings.STEERING_GAMMA)
    )

    local magnitude = math.abs(input)
    local output = math.pow(magnitude, gamma)

    if mode == "DRIFT" then
        gamma = gamma * 1.42
        output = math.pow(magnitude, gamma)
    else
        local edge = clamp((magnitude - 0.5) / 0.5, 0, 1)
        local boost = edge * edge * (3 - 2 * edge)
        output = lerp(output, magnitude, boost)
    end

    return math.sign(input) * output
end

local function getNormalRate()
    local value = mode == "DRIFT"
        and settings.DRIFT_NORMAL_RATE
        or settings.RACE_NORMAL_RATE

    return lerp(2.0, 20.0, percent(value))
end

local function getReturnRate()
    local value = mode == "DRIFT"
        and settings.DRIFT_RETURN_RATE
        or settings.RACE_RETURN_RATE

    return lerp(3.0, 22.0, percent(value))
end

local function getSpeedFactor(data)
    local speed = math.abs(data.speedKmh)

    if mode == "DRIFT" then
        return smoothstep(
            speed / INTERNAL.DRIFT_HIGH_SPEED_KMH
        )
    end

    local range = INTERNAL.RACE_HIGH_SPEED_KMH
        - INTERNAL.RACE_SPEED_START_KMH

    return smoothstep(
        (speed - INTERNAL.RACE_SPEED_START_KMH) / range
    )
end

local function getSpeedAuthority(data)
    local sensitivity = mode == "DRIFT"
        and percent(settings.DRIFT_SPEED_SENSITIVITY)
        or percent(settings.RACE_SPEED_SENSITIVITY)

    return 1.0 - getSpeedFactor(data) * sensitivity
end

local function getSteeringRates(data)
    local damping = 1.0

    if mode == "DRIFT" then
        damping = 1.0
            - INTERNAL.DRIFT_HIGH_SPEED_RATE_DAMPING
            * getSpeedFactor(data)
    end

    return getNormalRate() * damping,
        getReturnRate() * damping
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

local function getAxleMotion()
    local car = ac.getCar(0)

    if not car or not car.wheels
        or not car.wheels[0]
        or not car.wheels[1]
        or not car.wheels[2]
        or not car.wheels[3]
        or not car.transform then
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
        front = front,
        rear = rear,
        frontSpeed = frontSpeed,
        frontAngle = frontAngle,
        rearAngle = rearAngle,
    }
end

local function getDriftFactor(data)
    local rearSlip = (
        math.abs(data.ndSlipRL)
        + math.abs(data.ndSlipRR)
    ) * 0.5

    local angular = data.localAngularVelocity
    local yaw = angular and math.abs(angular.y) or 0

    return math.max(
        normalizedRange(
            rearSlip,
            INTERNAL.DRIFT_REAR_SLIP_START,
            INTERNAL.DRIFT_REAR_SLIP_FULL
        ),
        normalizedRange(
            yaw,
            INTERNAL.DRIFT_YAW_START,
            INTERNAL.DRIFT_YAW_FULL
        )
    )
end

local function getRaceSlideFactor(data)
    local rearSlip = (
        math.abs(data.ndSlipRL)
        + math.abs(data.ndSlipRR)
    ) * 0.5

    local angular = data.localAngularVelocity
    local yaw = angular and math.abs(angular.y) or 0

    return math.max(
        normalizedRange(
            rearSlip,
            INTERNAL.RACE_SLIDE_SLIP_START,
            INTERNAL.RACE_SLIDE_SLIP_FULL
        ),
        normalizedRange(
            yaw,
            INTERNAL.RACE_SLIDE_YAW_START,
            INTERNAL.RACE_SLIDE_YAW_FULL
        )
    )
end

local function getAxleSelfSteer(
    data,
    axle,
    gainSetting,
    maxSetting,
    yawDamping
)
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

    local response = percent(gainSetting)

    local exponent = 1.0 + (
        1.0 - math.log10(10.0 * (response * 0.9 + 0.1))
    )

    local normalizedAngle = clamp(-axle.rearAngle / 72.0, -1.0, 1.0)

    local correction = math.sign(normalizedAngle)
        * math.pow(math.abs(normalizedAngle), exponent)
        * 72.0 / steeringLock

    local damping = angular.y
        * yawDamping
        * 0.15
        * (30.0 / steeringLock)

    local wheelbase = math.abs(axle.front.z - axle.rear.z)
    local wheelbaseFactor = math.max(wheelbase / 2.5, 0.1)

    local fade = smoothstep(
        (axle.frontSpeed - 2.0 * wheelbaseFactor)
        / (4.0 * wheelbaseFactor)
    )

    local maximum = percent(maxSetting)

    return clamp(
        (correction + damping) * fade,
        -maximum,
        maximum
    )
end

local function getCountersteerTarget(data, driverTarget, axle)
    if mode == "DRIFT" then
        local correction = getAxleSelfSteer(
            data,
            axle,
            settings.DRIFT_COUNTERSTEER_GAIN,
            settings.DRIFT_COUNTERSTEER_MAX,
            INTERNAL.DRIFT_YAW_DAMPING
        )

        correction = correction * getDriftFactor(data)

        if driverTarget * correction < 0 then
            correction = correction * (
                1.0
                - percent(INTERNAL.DRIFT_INPUT_PRIORITY)
                * math.abs(driverTarget)
            )
        end

        return correction
    end

    return getAxleSelfSteer(
        data,
        axle,
        settings.RACE_COUNTERSTEER_GAIN,
        settings.RACE_COUNTERSTEER_MAX,
        INTERNAL.RACE_YAW_DAMPING
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

local function updateRaw()
    countersteerOutput = 0
end

local function updateAssisted(data, dt)
    local driverInput = getDriverInput(data)
    local driverTarget = driverInput * getSpeedAuthority(data)
    local axle = getAxleMotion()

    local countersteerTarget = getCountersteerTarget(
        data,
        driverTarget,
        axle
    )

    if mode == "RACE" then
        local slideFactor = getRaceSlideFactor(data)
        local reduction = percent(settings.RACE_SLIDE_INPUT_REDUCTION)

        countersteerTarget = countersteerTarget * (
            1.0 - slideFactor * reduction * math.abs(driverTarget)
        )
    end

    local countersteerRate = mode == "RACE"
        and INTERNAL.RACE_COUNTERSTEER_RATE
        or INTERNAL.DRIFT_COUNTERSTEER_RATE

    countersteerOutput = smooth(
        countersteerOutput,
        countersteerTarget,
        countersteerRate,
        dt
    )

    local countersteerMaximum = mode == "DRIFT"
        and percent(settings.DRIFT_COUNTERSTEER_MAX)
        or percent(settings.RACE_COUNTERSTEER_MAX)

    countersteerOutput = clamp(
        countersteerOutput,
        -countersteerMaximum,
        countersteerMaximum
    )

    local normalRate, returnRate = getSteeringRates(data)
    local driverRate = normalRate

    if driverTarget * steerOutput >= 0
        and math.abs(driverTarget) < math.abs(steerOutput) then
        driverRate = returnRate * INTERNAL.RETURN_RATE_MULTIPLIER
    elseif mode == "DRIFT"
        and driverTarget * steerOutput > 0
        and math.abs(driverTarget) > math.abs(steerOutput) then
        driverRate = normalRate * 0.65
    end

    steerOutput = smooth(
        steerOutput,
        driverTarget,
        driverRate,
        dt
    )

    if math.abs(steerOutput) < 0.0005
        and math.abs(driverTarget) < 0.0005 then
        steerOutput = 0
    end

    data.steer = clamp(
        steerOutput + countersteerOutput,
        -1.0,
        1.0
    )

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
    local pressed = ac.isGamepadButtonPressed(
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

        ac.storage["gamepadSteerMode:" .. ac.getCarID(0)] = mode

        steerOutput = 0
        countersteerOutput = 0

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