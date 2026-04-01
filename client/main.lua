local points = {}
local scenes = {}
local ShowScenes = true
local imageCache = {}
local previewState = {
    source = nil,
    requestId = 0,
    loaded = nil,
    pending = false,
    width = nil,
    height = nil,
    aspectRatio = 1.0,
}
local mediaBrowserState = {
    promise = nil,
}

local SceneFonts = {
    { value = 'chalet_london', label = 'Standard', id = 0 },
    { value = 'house_script', label = 'Cursive', id = 1 },
    { value = 'monospace', label = 'Rockstar Tag', id = 2 },
    { value = 'handwritten', label = 'Leaderboard', id = 3 },
    { value = 'chalet_comprime', label = 'Condensed', id = 4 },
    { value = 'fixed_width', label = 'Fixed Numbers', id = 5 },
    { value = 'condensed_alt', label = 'Condensed Alt', id = 6 },
    { value = 'pricedown', label = 'Pricedown', id = 7 },
    { value = 'taxi', label = 'Taxi', id = 8 },
}

local SceneEffects = {
    { value = 'clean', label = 'Clean' },
    { value = 'outline', label = 'Outline' },
    { value = 'shadow', label = 'Shadow' },
    { value = 'soft_shadow', label = 'Soft Shadow' },
    { value = 'neon', label = 'Neon' },
    { value = 'ghost', label = 'Ghost' },
    { value = 'premium', label = 'Premium' },
    { value = 'warning', label = 'Warning' },
}

local SceneAnimations = {
    { value = 'none', label = 'None' },
    { value = 'pulse', label = 'Pulse' },
    { value = 'float', label = 'Float' },
    { value = 'flicker', label = 'Flicker' },
    { value = 'glitch', label = 'Glitch' },
    { value = 'breathe', label = 'Breathe' },
}

local function Trim(value)
    if not value then
        return ''
    end

    return tostring(value):match('^%s*(.-)%s*$') or ''
end

local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue
    if value < minValue then
        return minValue
    end

    if value > maxValue then
        return maxValue
    end

    return value
end

local function ToRGB(hex)
    hex = (hex or '#ffffff'):gsub('#', '')
    return {
        r = tonumber('0x' .. hex:sub(1, 2)) or 255,
        g = tonumber('0x' .. hex:sub(3, 4)) or 255,
        b = tonumber('0x' .. hex:sub(5, 6)) or 255,
    }
end

local function ToHex(color)
    color = color or {}
    return ('#%02x%02x%02x'):format(color.r or 255, color.g or 255, color.b or 255)
end

local function UrlEncode(value)
    if not value then
        return ''
    end

    value = tostring(value)
    value = value:gsub('\n', '\r\n')
    value = value:gsub('([^%w%-_%.~])', function(char)
        return string.format('%%%02X', string.byte(char))
    end)

    return value
end

local function CloneTable(value)
    local clone = {}
    for key, nestedValue in pairs(value or {}) do
        if type(nestedValue) == 'table' then
            clone[key] = CloneTable(nestedValue)
        else
            clone[key] = nestedValue
        end
    end
    return clone
end

local function GetImageConfigValue(key, fallback)
    if Config and Config.SceneImages and Config.SceneImages[key] ~= nil then
        return Config.SceneImages[key]
    end

    return fallback
end

local function GetUIConfigValue(key, fallback)
    if Config and Config.SceneUI and Config.SceneUI[key] ~= nil then
        return Config.SceneUI[key]
    end

    return fallback
end

local function GetMediaConfigValue(key, fallback)
    if Config and Config.SceneMedia and Config.SceneMedia[key] ~= nil then
        return Config.SceneMedia[key]
    end

    return fallback
end

local function GetDefaultDistance()
    return tonumber(GetImageConfigValue('defaultDistance', 7.5)) or 7.5
end

local function GetDefaultImageScale()
    return tonumber(GetImageConfigValue('defaultImageScale', 2.25)) or 2.25
end

local function GetDefaultTextScale()
    return tonumber(GetImageConfigValue('defaultTextScale', 0.48)) or 0.48
end

local function GetImagePreloadDistance()
    return tonumber(GetImageConfigValue('imagePreloadDistance', 40.0)) or 40.0
end

local function GetDefaultBrowserProvider()
    return Trim(GetMediaConfigValue('defaultProvider', 'tenor'))
end

local function GetFontId(fontKey)
    for _, font in ipairs(SceneFonts) do
        if font.value == fontKey then
            return font.id
        end
    end

    return 0
end

local function GetFontOptions()
    local options = {}
    for _, font in ipairs(SceneFonts) do
        options[#options + 1] = {
            value = font.value,
            label = font.label,
        }
    end

    return options
end

local function GetEffectOptions()
    local options = {}
    for _, effect in ipairs(SceneEffects) do
        options[#options + 1] = {
            value = effect.value,
            label = effect.label,
        }
    end

    return options
end

local function GetAnimationOptions()
    local options = {}
    for _, animation in ipairs(SceneAnimations) do
        options[#options + 1] = {
            value = animation.value,
            label = animation.label,
        }
    end

    return options
end

local function SceneCoords(scene)
    if not scene or not scene.coords then
        return vec3(0.0, 0.0, 0.0)
    end

    return vec3(scene.coords.x + 0.0, scene.coords.y + 0.0, scene.coords.z + 0.0)
end

local function NormalizeScene(scene)
    local normalized = CloneTable(scene or {})
    normalized.text = Trim(normalized.text)
    normalized.imagePath = Trim(normalized.imagePath)
    normalized.color = normalized.color or { r = 255, g = 255, b = 255 }
    normalized.color.r = Clamp(normalized.color.r or 255, 0, 255)
    normalized.color.g = Clamp(normalized.color.g or 255, 0, 255)
    normalized.color.b = Clamp(normalized.color.b or 255, 0, 255)
    normalized.distance = Clamp(normalized.distance or GetDefaultDistance(), 1.0, 20.0)
    normalized.imageScale = Clamp(normalized.imageScale or GetDefaultImageScale(), 0.5, 8.0)
    normalized.imageAspectRatio = Clamp(normalized.imageAspectRatio or 1.0, 0.2, 5.0)
    normalized.textScale = Clamp(normalized.textScale or GetDefaultTextScale(), 0.2, 1.25)
    normalized.durationMinutes = Clamp(normalized.durationMinutes or 0, 0, 43200)
    normalized.font = Trim(normalized.font)
    if normalized.font == '' then
        normalized.font = 'chalet_london'
    end

    normalized.textEffect = Trim(normalized.textEffect)
    if normalized.textEffect == '' then
        normalized.textEffect = 'outline'
    end
    normalized.textAnimation = Trim(normalized.textAnimation)
    if normalized.textAnimation == '' then
        normalized.textAnimation = 'none'
    end
    normalized.ownerName = Trim(normalized.ownerName)
    normalized.coords = {
        x = tonumber(normalized.coords and normalized.coords.x) or 0.0,
        y = tonumber(normalized.coords and normalized.coords.y) or 0.0,
        z = tonumber(normalized.coords and normalized.coords.z) or 0.0,
    }

    return normalized
end

local function BuildSceneDraft(existingScene)
    local scene = NormalizeScene(existingScene)
    if not existingScene then
        scene.text = ''
        scene.imagePath = ''
        scene.imageAspectRatio = 1.0
        scene.distance = GetDefaultDistance()
        scene.imageScale = GetDefaultImageScale()
        scene.textScale = GetDefaultTextScale()
        scene.durationMinutes = 0
        scene.font = 'chalet_london'
        scene.textEffect = 'outline'
        scene.textAnimation = 'none'
        scene.color = { r = 255, g = 255, b = 255 }
    end

    return scene
end

local function ShouldAutoScaleImage(sceneDraft)
    local defaultScale = GetDefaultImageScale()
    return math.abs((sceneDraft.imageScale or defaultScale) - defaultScale) <= 0.01
end

local function GetAutoImageScale(width, height, aspectRatio)
    local scale = GetDefaultImageScale()
    aspectRatio = Clamp(aspectRatio or 1.0, 0.2, 5.0)
    width = tonumber(width) or 0
    height = tonumber(height) or 0

    if aspectRatio >= 2.2 then
        scale = scale * 1.22
    elseif aspectRatio >= 1.85 then
        scale = scale * 1.14
    elseif aspectRatio >= 1.35 then
        scale = scale * 1.08
    elseif aspectRatio <= 0.42 then
        scale = scale * 0.68
    elseif aspectRatio <= 0.58 then
        scale = scale * 0.76
    elseif aspectRatio <= 0.72 then
        scale = scale * 0.84
    elseif aspectRatio <= 0.9 then
        scale = scale * 0.93
    end

    local shortestSide = math.min(width, height)
    local longestSide = math.max(width, height)
    if longestSide >= 1400 then
        scale = scale + 0.1
    elseif longestSide > 0 and longestSide <= 420 then
        scale = scale - 0.08
    end

    if aspectRatio < 1.0 and height > width then
        local portraitDominance = Clamp(height / math.max(width, 1), 1.0, 3.0)
        scale = scale - ((portraitDominance - 1.0) * 0.12)

        if shortestSide > 0 and shortestSide <= 500 then
            scale = scale - 0.05
        end
    end

    return Clamp(scale, 0.5, 8.0)
end

local function NormalizeImageSource(path)
    if not path or path == '' then
        return nil
    end

    if path:find('^https?://') then
        return path
    end

    local resourceName = GetCurrentResourceName()
    path = path:gsub('^/', '')
    return ('https://cfx-nui-%s/%s'):format(resourceName, path)
end

local function ValidateSceneImagePath(imagePath)
    local validation = lib.callback.await('qb-scenes:server:prepareImagePath', nil, imagePath)
    if type(validation) ~= 'table' then
        return {
            ok = false,
            reason = 'image_validation_failed'
        }
    end

    return validation
end

local function DestroyImageCache()
    for key, image in pairs(imageCache) do
        if image.dui then
            DestroyDui(image.dui)
        end
        imageCache[key] = nil
    end
end

local function HideScenePreview()
    previewState.source = nil
    previewState.requestId = previewState.requestId + 1
    previewState.loaded = nil
    previewState.pending = false
    previewState.width = nil
    previewState.height = nil
    previewState.aspectRatio = 1.0

    SendNUIMessage({
        action = 'hidePreview'
    })
end

local function ShowScenePreview(imagePath)
    local source = NormalizeImageSource(imagePath)
    if not source then
        return { ok = false }
    end

    local retryCount = math.max(1, tonumber(GetImageConfigValue('previewRetryCount', 2)) or 2)
    local timeoutMs = math.max(5000, tonumber(GetImageConfigValue('previewTimeoutMs', 30000)) or 30000)

    for attempt = 1, retryCount do
        previewState.requestId = previewState.requestId + 1

        local previewSource = source
        if source:find('^https?://') and not source:find('^https://cfx%-nui%-') then
            local separator = source:find('?', 1, true) and '&' or '?'
            previewSource = ('%s%smtc_preview=%s'):format(source, separator, previewState.requestId)
        end

        previewState.source = previewSource
        previewState.loaded = nil
        previewState.pending = true
        previewState.width = nil
        previewState.height = nil
        previewState.aspectRatio = 1.0

        SendNUIMessage({
            action = 'hidePreview'
        })

        Wait(0)

        SendNUIMessage({
            action = 'showPreview',
            src = previewSource,
            requestId = previewState.requestId,
        })

        local timeoutAt = GetGameTimer() + timeoutMs
        while previewState.pending and GetGameTimer() < timeoutAt do
            Wait(0)
        end

        if previewState.loaded == true then
            return {
                ok = true,
                width = previewState.width,
                height = previewState.height,
                aspectRatio = previewState.aspectRatio or 1.0,
            }
        end

        if attempt < retryCount then
            SendNUIMessage({
                action = 'hidePreview'
            })
            Wait(500)
        end
    end

    return { ok = false }
end

local function ConfirmPreview()
    while true do
        Wait(0)

        if IsControlJustPressed(0, 38) then
            HideScenePreview()
            return true
        end

        if IsControlJustPressed(0, 177) then
            HideScenePreview()
            return false
        end
    end
end

local function GetMediaBrowserStrings()
    return {
        title = Lang:t('browser.title'),
        subtitle = Lang:t('browser.subtitle'),
        search_placeholder = Lang:t('browser.search_placeholder'),
        search_button = Lang:t('browser.search_button'),
        empty = Lang:t('browser.empty'),
        searching = Lang:t('browser.searching'),
        no_results = Lang:t('browser.no_results'),
        close = Lang:t('browser.close'),
    }
end

local function CloseMediaBrowser(selection)
    if not mediaBrowserState.promise then
        return
    end

    local promiseRef = mediaBrowserState.promise
    mediaBrowserState.promise = nil

    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'closeBrowser',
    })

    promiseRef:resolve(selection)
end

local function OpenMediaBrowser()
    local providers = lib.callback.await('qb-scenes:server:getMediaProviders')
    if type(providers) ~= 'table' or #providers == 0 then
        QBCore.Functions.Notify(Lang:t('notify.browser_not_configured'), 'error')
        return nil
    end

    local promiseRef = promise.new()
    mediaBrowserState.promise = promiseRef

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openBrowser',
        providers = providers,
        defaultProvider = GetDefaultBrowserProvider(),
        strings = GetMediaBrowserStrings(),
    })

    return Citizen.Await(promiseRef)
end

local function GetClosestScene(maxDistance)
    local pedCoords = GetEntityCoords(cache.ped)
    local closestIndex, closestScene, closestDistance

    for index, scene in pairs(scenes) do
        local sceneCoords = SceneCoords(scene)
        local distance = #(sceneCoords - pedCoords)
        if distance <= maxDistance and (not closestDistance or distance < closestDistance) then
            closestIndex = index
            closestScene = scene
            closestDistance = distance
        end
    end

    return closestIndex, closestScene, closestDistance
end

local function ApplyTextEffect(scene, alpha)
    local effect = scene.textEffect or 'outline'
    local color = scene.color or { r = 255, g = 255, b = 255 }

    if effect == 'outline' then
        SetTextOutline()
    elseif effect == 'shadow' then
        SetTextDropshadow(2, 0, 0, 0, alpha)
    elseif effect == 'soft_shadow' then
        SetTextDropshadow(1, 0, 0, 0, math.floor(alpha * 0.7))
    elseif effect == 'neon' then
        SetTextOutline()
        SetTextEdge(2, color.r, color.g, color.b, math.floor(alpha * 0.7))
        SetTextDropshadow(2, 0, 0, 0, math.floor(alpha * 0.75))
    elseif effect == 'ghost' then
        SetTextOutline()
        SetTextDropshadow(4, 0, 0, 0, math.floor(alpha * 0.85))
    elseif effect == 'premium' then
        SetTextOutline()
        SetTextEdge(1, math.floor(color.r * 0.4), math.floor(color.g * 0.4), math.floor(color.b * 0.4), math.floor(alpha * 0.75))
        SetTextDropshadow(3, 0, 0, 0, math.floor(alpha * 0.8))
    elseif effect == 'warning' then
        SetTextOutline()
        SetTextEdge(2, 255, 140, 0, math.floor(alpha * 0.55))
        SetTextDropshadow(4, 0, 0, 0, alpha)
    end
end

local function GetAnimationSeed(scene)
    local coords = scene.coords or {}
    return ((coords.x or 0.0) * 0.173) + ((coords.y or 0.0) * 0.287) + ((coords.z or 0.0) * 0.131)
end

local function GetTextAnimationState(scene)
    local clock = GetGameTimer() / 1000.0
    local seed = GetAnimationSeed(scene)
    local animation = scene.textAnimation or 'none'
    local state = {
        alpha = 255,
        scaleMultiplier = 1.0,
        coordsOffset = { x = 0.0, y = 0.0, z = 0.0 },
        glitchLayers = nil,
    }

    if animation == 'pulse' then
        local wave = (math.sin((clock + seed) * 2.75) + 1.0) * 0.5
        state.alpha = Clamp(190 + math.floor(wave * 65), 125, 255)
        state.scaleMultiplier = 1.0 + (wave * 0.08)
    elseif animation == 'float' then
        state.coordsOffset.z = math.sin((clock + seed) * 1.9) * 0.03
        state.alpha = 235
    elseif animation == 'flicker' then
        local wave = math.abs(math.sin((clock + seed) * 16.0))
        state.alpha = Clamp(105 + math.floor(wave * 150), 90, 255)
        state.scaleMultiplier = 1.0 + (math.sin((clock + seed) * 8.0) * 0.015)
    elseif animation == 'glitch' then
        local wave = math.sin((clock + seed) * 11.0)
        state.alpha = Clamp(180 + math.floor(math.abs(math.sin((clock + seed) * 22.0)) * 75), 120, 255)
        state.scaleMultiplier = 1.0 + (wave * 0.035)
        state.coordsOffset.x = wave * 0.003
        state.coordsOffset.y = math.cos((clock + seed) * 8.5) * 0.002
        state.glitchLayers = {
            { x = -0.003, y = 0.0, z = 0.0, alpha = math.floor(state.alpha * 0.35), color = { r = 255, g = 80, b = 80 } },
            { x = 0.003, y = 0.0, z = 0.0, alpha = math.floor(state.alpha * 0.35), color = { r = 80, g = 220, b = 255 } },
        }
    elseif animation == 'breathe' then
        local wave = (math.sin((clock + seed) * 1.75) + 1.0) * 0.5
        state.alpha = Clamp(170 + math.floor(wave * 60), 120, 255)
        state.scaleMultiplier = 0.98 + (wave * 0.06)
        state.coordsOffset.z = wave * 0.015
    end

    return state
end

local function DrawTextLayer(text, coords, fontKey, scale, color, alpha, effect)
    local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z)
    if not onScreen then
        return
    end

    local cameraCoords = GetGameplayCamCoord()
    local distance = #(cameraCoords - vec3(coords.x, coords.y, coords.z))
    local distanceScale = (1.0 / math.max(distance, 1.0)) * 2.0
    local fovScale = (1.0 / GetGameplayCamFov()) * 100.0
    local drawScale = Clamp(distanceScale * fovScale * scale, 0.18, 1.1)
    local effectScene = {
        textEffect = effect,
        color = color,
    }
    alpha = math.floor(Clamp(alpha or 255, 0, 255))

    SetTextScale(0.0, drawScale)
    SetTextFont(GetFontId(fontKey))
    SetTextProportional(true)
    SetTextColour(color.r, color.g, color.b, alpha)
    SetTextEntry('STRING')
    SetTextCentre(true)
    ApplyTextEffect(effectScene, alpha)
    AddTextComponentString(text)
    DrawText(screenX, screenY)
end

local function DrawText3D(scene, coords, options)
    options = options or {}
    local animationState = GetTextAnimationState(scene)
    local alpha = math.floor(Clamp((options.alpha or 255) * (animationState.alpha / 255.0), 0, 255))
    local scale = Clamp((scene.textScale or GetDefaultTextScale()) * animationState.scaleMultiplier, 0.2, 1.25)
    local color = scene.color or { r = 255, g = 255, b = 255 }
    local animatedCoords = {
        x = coords.x + animationState.coordsOffset.x,
        y = coords.y + animationState.coordsOffset.y,
        z = coords.z + animationState.coordsOffset.z,
    }

    if animationState.glitchLayers then
        for _, layer in ipairs(animationState.glitchLayers) do
            DrawTextLayer(scene.text, {
                x = animatedCoords.x + layer.x,
                y = animatedCoords.y + layer.y,
                z = animatedCoords.z + layer.z,
            }, scene.font, scale, layer.color, Clamp(layer.alpha, 0, 255), 'clean')
        end
    end

    DrawTextLayer(scene.text, animatedCoords, scene.font, scale, color, alpha, scene.textEffect)
end

local function GetSceneImage(scene, id)
    local imagePath = NormalizeImageSource(scene.imagePath)
    if not imagePath then
        return nil
    end

    local cacheKey = ('scene_%s_%s'):format(id, imagePath)
    if imageCache[cacheKey] then
        return imageCache[cacheKey]
    end

    local txdName = ('mtc_scene_%s'):format(id)
    local txd = CreateRuntimeTxd(txdName)
    local duiUrl = ('https://cfx-nui-%s/ui/image.html?src=%s'):format(GetCurrentResourceName(), UrlEncode(imagePath))
    local dui = CreateDui(duiUrl, 1024, 1024)
    local duiHandle = GetDuiHandle(dui)

    CreateRuntimeTextureFromDuiHandle(txd, 'scene_image', duiHandle)

    imageCache[cacheKey] = {
        txd = txdName,
        txn = 'scene_image',
        dui = dui,
    }

    return imageCache[cacheKey]
end

local function GetImageSpriteSize(scene, distance)
    local ratio = Clamp(scene.imageAspectRatio or 1.0, 0.2, 5.0)
    local scale = Clamp(scene.imageScale or GetDefaultImageScale(), 0.5, 8.0)
    local base = math.max(0.05, 0.35 * (scale / math.max(distance, 1.0)))

    if ratio >= 1.0 then
        return base, base / ratio
    end

    return base * ratio, base
end

local function DrawImage3D(scene, id, options)
    local image = GetSceneImage(scene, id)
    if not image then
        return
    end

    options = options or {}
    local alpha = Clamp(options.alpha or 255, 0, 255)
    local sceneCoords = SceneCoords(scene)
    local distance = #(GetGameplayCamCoord() - sceneCoords)
    local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(sceneCoords.x, sceneCoords.y, sceneCoords.z)

    if not onScreen then
        return
    end

    local width, height = GetImageSpriteSize(scene, distance)
    DrawSprite(image.txd, image.txn, screenX, screenY, width, height, 0.0, 255, 255, 255, alpha)
end

local function DrawScene(scene, id, options)
    scene = NormalizeScene(scene)
    options = options or {}

    if scene.imagePath ~= '' then
        DrawImage3D(scene, id, options)
    end

    if scene.text ~= '' then
        local textCoords = CloneTable(scene.coords)
        if scene.imagePath ~= '' then
            textCoords.z = textCoords.z - 0.02
        end
        DrawText3D(scene, textCoords, options)
    end
end

local function SetupScenes(sceneList)
    for _, point in ipairs(points) do
        point:remove()
    end

    points = {}
    DestroyImageCache()

    for id, rawScene in pairs(sceneList) do
        local scene = NormalizeScene(rawScene)
        scenes[id] = scene

        if scene.imagePath ~= '' then
            GetSceneImage(scene, id)
        end

        local point = lib.points.new({
            coords = SceneCoords(scene),
            distance = scene.distance or GetDefaultDistance(),
        })

        function point:nearby()
            if not ShowScenes then
                return
            end

            DrawScene(scene, id)
        end

        points[#points + 1] = point
    end
end

local function PreloadNearbySceneImages()
    if not cache.ped or cache.ped == 0 then
        return
    end

    local pedCoords = GetEntityCoords(cache.ped)
    local preloadDistance = math.max(10.0, GetImagePreloadDistance())

    for id, scene in pairs(scenes) do
        if scene.imagePath ~= '' then
            local sceneCoords = SceneCoords(scene)
            local distance = #(sceneCoords - pedCoords)
            if distance <= math.max(preloadDistance, (scene.distance or GetDefaultDistance()) + 10.0) then
                GetSceneImage(scene, id)
            end
        end
    end
end

local function ApplyPrimaryScaleDelta(sceneDraft, delta)
    if sceneDraft.imagePath ~= '' then
        sceneDraft.imageScale = Clamp(sceneDraft.imageScale + delta, 0.5, 8.0)
        return
    end

    sceneDraft.textScale = Clamp(sceneDraft.textScale + (delta * 0.16), 0.2, 1.25)
end

local function ApplySecondaryScaleDelta(sceneDraft, delta)
    if sceneDraft.text ~= '' then
        sceneDraft.textScale = Clamp(sceneDraft.textScale + delta, 0.2, 1.25)
    end
end

local function CoordPicker(sceneDraft)
    sceneDraft = NormalizeScene(sceneDraft)

    local coords = GetEntityCoords(cache.ped)
    local enabled = true
    local promiseRef = promise.new()

    lib.showTextUI(Lang:t('textUI.place_preview'), {
        position = 'left-center',
        icon = 'crosshairs'
    })

    CreateThread(function()
        while enabled do
            Wait(50)
            local _, _, rayCoords = lib.raycast.cam()
            if rayCoords then
                coords = rayCoords
            end
        end
    end)

    CreateThread(function()
        local offset = 0.2
        while enabled do
            Wait(0)

            local previewScene = CloneTable(sceneDraft)
            previewScene.coords = {
                x = coords.x,
                y = coords.y,
                z = coords.z,
            }

            DrawBox(
                coords.x - offset,
                coords.y - offset,
                coords.z - offset,
                coords.x + offset,
                coords.y + offset,
                coords.z + offset,
                197,
                160,
                89,
                75
            )

            DrawScene(previewScene, 'placement', {
                alpha = 225
            })
        end
    end)

    CreateThread(function()
        while enabled do
            Wait(0)

            local shiftHeld = IsControlPressed(0, 21)

            if IsControlJustPressed(0, 15) then
                if shiftHeld then
                    ApplySecondaryScaleDelta(sceneDraft, 0.03)
                else
                    ApplyPrimaryScaleDelta(sceneDraft, 0.15)
                end
            elseif IsControlJustPressed(0, 14) then
                if shiftHeld then
                    ApplySecondaryScaleDelta(sceneDraft, -0.03)
                else
                    ApplyPrimaryScaleDelta(sceneDraft, -0.15)
                end
            elseif IsControlJustPressed(0, 38) then
                enabled = false
                lib.hideTextUI()
                promiseRef:resolve({
                    coords = {
                        x = coords.x,
                        y = coords.y,
                        z = coords.z,
                    },
                    imageScale = sceneDraft.imageScale,
                    textScale = sceneDraft.textScale,
                })
            elseif IsControlJustPressed(0, 177) then
                enabled = false
                lib.hideTextUI()
                promiseRef:resolve(nil)
            end
        end
    end)

    return Citizen.Await(promiseRef)
end

local function NotifyResult(result, successKey, fallbackErrorKey)
    if type(result) == 'table' and result.ok then
        QBCore.Functions.Notify(Lang:t('notify.' .. successKey), 'success')
        return true
    end

    local reason = type(result) == 'table' and result.reason or fallbackErrorKey
    QBCore.Functions.Notify(Lang:t('notify.' .. (reason or fallbackErrorKey)), 'error')
    return false
end

local function OpenSceneForm(title, scene, includeReposition)
    local draft = BuildSceneDraft(scene)
    local dialogFields = {
        {
            type = 'input',
            label = Lang:t('createScene.input_label'),
            description = Lang:t('createScene.input_description'),
            default = draft.text,
            required = false,
        },
        {
            type = 'color',
            label = Lang:t('createScene.color_label'),
            description = Lang:t('createScene.color_description'),
            default = ToHex(draft.color),
            required = true,
        },
        {
            type = 'select',
            label = Lang:t('createScene.font_label'),
            description = Lang:t('createScene.font_description'),
            options = GetFontOptions(),
            default = draft.font,
            required = true,
        },
        {
            type = 'select',
            label = Lang:t('createScene.effect_label'),
            description = Lang:t('createScene.effect_description'),
            options = GetEffectOptions(),
            default = draft.textEffect,
            required = true,
        },
        {
            type = 'select',
            label = Lang:t('createScene.animation_label'),
            description = Lang:t('createScene.animation_description'),
            options = GetAnimationOptions(),
            default = draft.textAnimation,
            required = true,
        },
        {
            type = 'slider',
            label = Lang:t('createScene.text_size_label'),
            description = Lang:t('createScene.text_size_description'),
            default = math.floor(draft.textScale * 100),
            min = 20,
            max = 125,
            required = true,
        },
        {
            type = 'input',
            label = Lang:t('createScene.image_label'),
            description = Lang:t('createScene.image_description'),
            default = draft.imagePath,
            required = false,
            placeholder = 'ui/images/example.png',
        },
        {
            type = 'slider',
            label = Lang:t('createScene.image_size_label'),
            description = Lang:t('createScene.image_size_description'),
            default = math.floor(draft.imageScale * 100),
            min = 50,
            max = 800,
            required = true,
        },
        {
            type = 'number',
            label = Lang:t('createScene.timer_label'),
            description = Lang:t('createScene.timer_description'),
            default = draft.durationMinutes or 0,
            min = 0,
            max = 43200,
            required = true,
        },
        {
            type = 'slider',
            label = Lang:t('createScene.slider_label'),
            description = Lang:t('createScene.slider_description'),
            default = math.floor(draft.distance * 10),
            min = 10,
            max = 200,
            required = true,
        }
    }

    if includeReposition then
        dialogFields[#dialogFields + 1] = {
            type = 'checkbox',
            label = Lang:t('createScene.reposition_label'),
            description = Lang:t('createScene.reposition_description'),
            checked = false,
        }
    end

    local input = lib.inputDialog(title, dialogFields)
    if not input then
        return nil
    end

    local result = {
        text = Trim(input[1]),
        color = ToRGB(input[2]),
        font = input[3] or draft.font,
        textEffect = input[4] or draft.textEffect,
        textAnimation = input[5] or draft.textAnimation,
        textScale = Clamp((tonumber(input[6]) or math.floor(GetDefaultTextScale() * 100)) / 100, 0.2, 1.25),
        imagePath = Trim(input[7]),
        imageScale = Clamp((tonumber(input[8]) or math.floor(GetDefaultImageScale() * 100)) / 100, 0.5, 8.0),
        durationMinutes = Clamp(tonumber(input[9]) or 0, 0, 43200),
        distance = Clamp((tonumber(input[10]) or math.floor(GetDefaultDistance() * 10)) / 10, 1.0, 20.0),
        imageAspectRatio = draft.imageAspectRatio or 1.0,
        reposition = includeReposition and input[11] == true or false,
        coords = draft.coords,
    }

    if result.text == '' and result.imagePath == '' then
        QBCore.Functions.Notify(Lang:t('notify.scene_content_required'), 'error')
        return nil
    end

    return result
end

local function PrepareSceneImageDraft(sceneDraft)
    if sceneDraft.imagePath == '' then
        sceneDraft.imageAspectRatio = 1.0
        return true
    end

    QBCore.Functions.Notify(Lang:t('notify.image_preparing'), 'primary')
    local validation = ValidateSceneImagePath(sceneDraft.imagePath)
    if not validation.ok then
        QBCore.Functions.Notify(Lang:t('notify.' .. (validation.reason or 'image_validation_failed')), 'error')
        return false
    end

    sceneDraft.imagePath = validation.imagePath

    local preview = ShowScenePreview(sceneDraft.imagePath)
    if not preview.ok then
        HideScenePreview()
        QBCore.Functions.Notify(Lang:t('notify.preview_failed'), 'error')
        return false
    end

    sceneDraft.imageAspectRatio = Clamp(preview.aspectRatio or 1.0, 0.2, 5.0)
    if ShouldAutoScaleImage(sceneDraft) and not GetImageConfigValue('disableAutoScale', false) then
        sceneDraft.imageScale = GetAutoImageScale(preview.width, preview.height, sceneDraft.imageAspectRatio)
    end
    QBCore.Functions.Notify(Lang:t('notify.preview_loaded'), 'success')

    if not ConfirmPreview() then
        QBCore.Functions.Notify(Lang:t('notify.preview_cancelled'), 'error')
        return false
    end

    return true
end

local function toggleScenes()
    ShowScenes = not ShowScenes
    QBCore.Functions.Notify(
        Lang:t('notify.scene_visibility') ..
        (ShowScenes and Lang:t('notify.scene_visibility_visible') or Lang:t('notify.scene_visibility_hidden')),
        'success'
    )
end

local function createScene(initialScene)
    local sceneDraft = OpenSceneForm(Lang:t('createScene.new_scene'), initialScene)
    if not sceneDraft then
        return
    end

    if not PrepareSceneImageDraft(sceneDraft) then
        return
    end

    local placement = CoordPicker(sceneDraft)
    if not placement then
        QBCore.Functions.Notify(Lang:t('notify.not_placed'), 'error')
        return
    end

    sceneDraft.coords = placement.coords
    sceneDraft.imageScale = placement.imageScale or sceneDraft.imageScale
    sceneDraft.textScale = placement.textScale or sceneDraft.textScale

    local result = lib.callback.await('qb-scenes:server:newScene', nil, sceneDraft)
    NotifyResult(result, 'scene_created', 'failed')
end

local function browseSceneMedia()
    local selection = OpenMediaBrowser()
    if not selection or Trim(selection.url) == '' then
        return
    end

    local seedScene = BuildSceneDraft()
    seedScene.imagePath = Trim(selection.url)

    local width = tonumber(selection.width) or 0
    local height = tonumber(selection.height) or 0
    if width > 0 and height > 0 then
        seedScene.imageAspectRatio = Clamp(width / height, 0.2, 5.0)
        if not GetImageConfigValue('disableAutoScale', false) then
            seedScene.imageScale = GetAutoImageScale(width, height, seedScene.imageAspectRatio)
        end
    end

    createScene(seedScene)
end

local function editClosestScene()
    local index, scene = GetClosestScene(3.0)
    if not index or not scene then
        QBCore.Functions.Notify(Lang:t('notify.scene_nearby'), 'error')
        return
    end

    local sceneDraft = OpenSceneForm(Lang:t('createScene.edit_scene'), scene, true)
    if not sceneDraft then
        return
    end

    if not PrepareSceneImageDraft(sceneDraft) then
        return
    end

    if sceneDraft.reposition then
        local placement = CoordPicker(sceneDraft)
        if not placement then
            QBCore.Functions.Notify(Lang:t('notify.not_placed'), 'error')
            return
        end

        sceneDraft.coords = placement.coords
        sceneDraft.imageScale = placement.imageScale or sceneDraft.imageScale
        sceneDraft.textScale = placement.textScale or sceneDraft.textScale
    else
        sceneDraft.coords = scene.coords
    end

    local result = lib.callback.await('qb-scenes:server:updateScene', nil, index, sceneDraft)
    NotifyResult(result, 'scene_updated', 'failed_update')
end

local function destroyClosestScene()
    local index = GetClosestScene(3.0)
    if not index then
        QBCore.Functions.Notify(Lang:t('notify.scene_nearby'), 'error')
        return
    end

    local result = lib.callback.await('qb-scenes:server:destoryScene', nil, index)
    NotifyResult(result, 'succes_destroy', 'failed_destroy')
end

local function OpenSceneMenu()
    local nearestIndex, nearestScene, nearestDistance = GetClosestScene(3.0)
    local nearestDescription = nearestScene and
        (Lang:t('optionsScene.nearest_scene') .. (' %.1fm | %s'):format(nearestDistance, nearestScene.ownerName ~= '' and nearestScene.ownerName or Lang:t('optionsScene.unknown_owner')))
        or Lang:t('optionsScene.no_scene')

    lib.registerContext({
        id = 'djonstnix-scenes',
        title = GetUIConfigValue('menuTitle', 'DjonStNix Scenes'),
        options = {
            {
                title = Lang:t('optionsScene.toggle'),
                description = Lang:t('optionsScene.toggle_description'),
                icon = 'eye',
                onSelect = toggleScenes,
            },
            {
                title = Lang:t('optionsScene.create'),
                description = Lang:t('optionsScene.create_description'),
                icon = 'plus',
                onSelect = createScene,
            },
            {
                title = Lang:t('optionsScene.browse'),
                description = Lang:t('optionsScene.browse_description'),
                icon = 'images',
                onSelect = browseSceneMedia,
            },
            {
                title = Lang:t('optionsScene.edit'),
                description = nearestDescription,
                icon = 'pen-to-square',
                onSelect = editClosestScene,
            },
            {
                title = Lang:t('optionsScene.destroy'),
                description = nearestDescription,
                icon = 'trash',
                onSelect = destroyClosestScene,
            }
        }
    })

    lib.showContext('djonstnix-scenes')
end

RegisterCommand('scene', function()
    OpenSceneMenu()
end)

RegisterCommand(GetUIConfigValue('keybindCommand', 'scene_menu'), function()
    OpenSceneMenu()
end, false)

RegisterKeyMapping(
    GetUIConfigValue('keybindCommand', 'scene_menu'),
    GetUIConfigValue('keybindDescription', 'Open the DjonStNix scenes menu'),
    'keyboard',
    GetUIConfigValue('defaultKey', 'F7')
)

RegisterCommand('scenepreview', function(_, args)
    local imagePath = Trim(table.concat(args, ' '))
    if imagePath == '' then
        QBCore.Functions.Notify(Lang:t('notify.preview_usage'), 'error')
        return
    end

    local sceneDraft = BuildSceneDraft()
    sceneDraft.imagePath = imagePath

    if not PrepareSceneImageDraft(sceneDraft) then
        return
    end
end, false)

RegisterNUICallback('sceneMediaSearch', function(data, cb)
    local provider = Trim(data and data.provider)
    local query = Trim(data and data.query)

    local result = lib.callback.await('qb-scenes:server:searchMedia', nil, provider, query)
    if type(result) ~= 'table' then
        cb({
            ok = false,
            reason = 'browser_search_failed',
            results = {},
        })
        return
    end

    cb(result)
end)

RegisterNUICallback('sceneMediaSelect', function(data, cb)
    CloseMediaBrowser(data or nil)
    cb({ ok = true })
end)

RegisterNUICallback('sceneMediaClose', function(_, cb)
    CloseMediaBrowser(nil)
    cb({ ok = true })
end)

RegisterNetEvent('qb-scenes:client:refreshScenes', function(serverScenes)
    local normalizedScenes = {}
    for index, scene in pairs(serverScenes or {}) do
        normalizedScenes[index] = NormalizeScene(scene)
    end

    scenes = normalizedScenes
    SetupScenes(normalizedScenes)
end)

RegisterNUICallback('scenePreviewStatus', function(data, cb)
    if data.source ~= previewState.source or tonumber(data.requestId) ~= previewState.requestId then
        cb({ ok = true })
        return
    end

    previewState.loaded = data.loaded == true
    previewState.pending = false
    previewState.width = tonumber(data.width) or nil
    previewState.height = tonumber(data.height) or nil

    if previewState.width and previewState.height and previewState.height > 0 then
        previewState.aspectRatio = previewState.width / previewState.height
    else
        previewState.aspectRatio = 1.0
    end

    cb({ ok = true })
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    CloseMediaBrowser(nil)
    HideScenePreview()
    DestroyImageCache()
end)

CreateThread(function()
    scenes = lib.callback.await('qb-scenes:server:getScenes')
    SetupScenes(scenes or {})
end)

CreateThread(function()
    while true do
        Wait(1500)
        PreloadNearbySceneImages()
    end
end)
