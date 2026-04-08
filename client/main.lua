local points = {}
local scenes = {}
local ShowScenes = true
local imageCache = {}
local previewRequests = {}
local previewRequestCounter = 0
local previewQueue = {} -- Sequential queue for background detection
local isProcessingQueue = false
local destructionQueue = {} -- Safety buffer for DUI disposal
local duiTracker = {} -- Scene ID -> { dui = dui, cacheKey = cacheKey }
local isPlacing = false -- Safety lock for active placement
local mediaBrowserState = { promise = nil }
local ProcessPreviewQueue
local ShowScenePreview
local globalTxd = ('txd_scenes_%d'):format(math.random(1000, 9999))
local globalTxdHandle = CreateRuntimeTxd(globalTxd)

-- DUI Keep-Alive Thread (Prevents GIF freezing by forcing texture updates)
CreateThread(function()
    while true do
        Wait(0) -- every frame

        for id, tracker in pairs(duiTracker) do
            if tracker and tracker.dui then
                local handle = GetDuiHandle(tracker.dui)
                
                if handle and handle ~= 0 then
                    -- This keeps Chromium "alive" by simulating a draw origin change
                    SetDrawOrigin(0.0, 0.0, 0.0, 0)
                    ClearDrawOrigin()
                end
            end
        end
    end
end)

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

local function GetUrlHash(url)
    if not url then return '000000' end
    local hash = 5381
    for i = 1, #url do
        hash = ((hash * 33) + string.byte(url, i)) % 0x100000000
    end
    return string.format('%x', hash)
end

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

local function NormalizeMediaKind(value)
    value = Trim(value):lower()
    if value == 'video' then
        return 'video'
    end

    return 'image'
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
    normalized.mediaKind = NormalizeMediaKind(normalized.mediaKind)
    normalized.mediaExtension = Trim(normalized.mediaExtension):lower()
    normalized.mediaAnimated = normalized.mediaAnimated == true or normalized.mediaExtension == 'gif' or normalized.mediaKind == 'video'
    normalized.color = normalized.color or { r = 255, g = 255, b = 255 }
    normalized.color.r = Clamp(normalized.color.r or 255, 0, 255)
    normalized.color.g = Clamp(normalized.color.g or 255, 0, 255)
    normalized.color.b = Clamp(normalized.color.b or 255, 0, 255)
    normalized.distance = Clamp(normalized.distance or GetDefaultDistance(), 1.0, 20.0)
    normalized.imageScale = Clamp(normalized.imageScale or GetDefaultImageScale(), 0.1, 20.0)
    normalized.imageAspectRatio = Clamp(normalized.imageAspectRatio or 1.0, 0.2, 5.0)
    normalized.imageWidth = tonumber(normalized.imageWidth)
    normalized.imageHeight = tonumber(normalized.imageHeight)
    normalized.rotation = {
        x = tonumber(normalized.rotation and normalized.rotation.x) or 0.0,
        y = tonumber(normalized.rotation and normalized.rotation.y) or 0.0,
        z = tonumber(normalized.rotation and normalized.rotation.z) or 0.0,
    }
    normalized.faceCamera = normalized.faceCamera == true
    
    -- If dimensions are missing or are the legacy default, mark for possible auto-correction
    if not normalized.imageWidth or not normalized.imageHeight or (normalized.imageWidth == 1024 and normalized.imageHeight == 1024) then
        normalized.imageWidth = 1024
        normalized.imageHeight = 1024
        normalized.legacyDimensions = true
    end
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
        scene.mediaKind = 'image'
        scene.mediaExtension = ''
        scene.mediaAnimated = false
        scene.imageAspectRatio = 1.0
        scene.distance = GetDefaultDistance()
        scene.imageScale = GetDefaultImageScale()
        scene.textScale = GetDefaultTextScale()
        scene.durationMinutes = 0
        scene.font = 'chalet_london'
        scene.textEffect = 'outline'
        scene.textAnimation = 'none'
        scene.color = { r = 255, g = 255, b = 255 }
        scene.rotation = { x = 0.0, y = 0.0, z = 0.0 }
        scene.faceCamera = false
    end

    return scene
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
    local validation = lib.callback.await('djonstnix-scenes:server:prepareImagePath', nil, imagePath)
    if type(validation) ~= 'table' then
        return {
            ok = false,
            reason = 'image_validation_failed'
        }
    end

    return validation
end

--------------------------------------------------------------------------------
-- DUI & TEXTURE RESOURCE MANAGEMENT (Definitive Stabilization Version)
--------------------------------------------------------------------------------

local function ReleaseImageReference(id)
    local tracker = duiTracker[id]
    if not tracker then return end
    
    local cacheKey = tracker.cacheKey
    local img = imageCache[cacheKey]
    
    if img then
        img.refCount = math.max(0, (img.refCount or 1) - 1)
        
        -- ONLY destroy when nobody else is looking at it
        if img.refCount <= 0 then
            if img.dui then
                table.insert(destructionQueue, {
                    dui = img.dui,
                    expireAt = GetGameTimer() + 2000 -- 2.0s Safety Window
                })
            end
            imageCache[cacheKey] = nil
        end
    end
    
    duiTracker[id] = nil
end

local function ClearSceneImageResources(id)
    ReleaseImageReference(id)
end

local function DestroyImageCache()
    for key, image in pairs(imageCache) do
        if image.dui then
            table.insert(destructionQueue, {
                dui = image.dui,
                expireAt = GetGameTimer() + 2000
            })
        end
        imageCache[key] = nil
    end
end

local function AcquireImageReference(cacheKey, id, img)
    img.refCount = (img.refCount or 0) + 1

    for i = #destructionQueue, 1, -1 do
        if destructionQueue[i].dui == img.dui then
            table.remove(destructionQueue, i)
            break
        end
    end

    -- Track EVERYTHING (including 'placement' ghost) to prevent memory leaks
    duiTracker[id] = { 
        cacheKey = cacheKey, 
        dui = img.dui 
    }
end

local function GetSceneImage(scene, id)
    local imagePath = NormalizeImageSource(scene.imagePath or '')
    if not imagePath then return nil end

    local urlHash = GetUrlHash(imagePath)
    local width = tonumber(scene.imageWidth) or 1024
    local height = tonumber(scene.imageHeight) or 1024
    local mediaKind = NormalizeMediaKind(scene.mediaKind)
    
    -- Unique cache key by URL + Resolution to prevent distortions
    local cacheKey = ('img_%s_%s_%dx%d'):format(urlHash, mediaKind, width, height)

    -- 1. Correct Image Loaded Check
    if duiTracker[id] and duiTracker[id].cacheKey == cacheKey then
        return imageCache[cacheKey]
    end

    -- 2. Target Switch: Release old if changing image
    if duiTracker[id] and duiTracker[id].cacheKey ~= cacheKey then
        ReleaseImageReference(id)
    end

    -- 3. Cache Hit
    if imageCache[cacheKey] then
        local img = imageCache[cacheKey]
        local isFirstAcquisition = not duiTracker[id]

        AcquireImageReference(cacheKey, id, img)

        -- 🔥 KICK: If a permanent scene takes over a handle for the first time,
        -- force-refresh the URL to ensure the animation loop starts fresh.
        if isFirstAcquisition and id ~= 'placement' and img.dui and img.dui ~= 0 then
            local duiUrl = ('https://cfx-nui-%s/ui/image.html?src=%s&kind=%s&v=%d'):format(
                GetCurrentResourceName(), 
                UrlEncode(imagePath), 
                UrlEncode(mediaKind),
                GetGameTimer()
            )
            SetDuiUrl(img.dui, duiUrl)
        end

        return img
    end

    -- 4. Create New Handle with delayed texture warmup to avoid preview->placement crashes
    local txnName = ('tex_%s_%s_%dx%d'):format(urlHash, mediaKind, width, height)
    local duiUrl = ('https://cfx-nui-%s/ui/image.html?src=%s&kind=%s'):format(GetCurrentResourceName(), UrlEncode(imagePath), UrlEncode(mediaKind))
    local dui = CreateDui(duiUrl, width, height)
    if not dui or dui == 0 then
        return nil
    end

    local img = {
        txd = globalTxd,
        txn = txnName,
        dui = dui,
        width = width,
        height = height,
        refCount = 0,
        ready = false
    }

    imageCache[cacheKey] = img
    AcquireImageReference(cacheKey, id, img)

    CreateThread(function()
        Wait(500)

        if imageCache[cacheKey] ~= img then
            return
        end

        if not img.dui or img.dui == 0 then
            return
        end

        local duiHandle = GetDuiHandle(img.dui)
        if not duiHandle or duiHandle == 0 then
            return
        end

        local ok = pcall(function()
            CreateRuntimeTextureFromDuiHandle(globalTxdHandle, txnName, duiHandle)
        end)

        if ok then
            img.ready = true
        end
    end)

    -- Trigger dimension correction for legacy scenes if needed
    if scene.legacyDimensions and id ~= 'placement' and not scene.isCheckingDimensions and not isPlacing then
        scene.isCheckingDimensions = true
        table.insert(previewQueue, { id = id, scene = scene })
        ProcessPreviewQueue()
    end

    return img
end

-- Sequential dimension detection worker
ProcessPreviewQueue = function()
    if isProcessingQueue or #previewQueue == 0 then return end
    isProcessingQueue = true
    
    CreateThread(function()
        while #previewQueue > 0 do
            while isPlacing do
                Wait(250)
            end

            local item = table.remove(previewQueue, 1)
            -- Only check if we didn't already get them from a previous identical request
            if item.scene.legacyDimensions then
                print(('^5[DjonStNix Scenes]^7 Sequential Dimension Check: %s'):format(item.id))
                local detection = ShowScenePreview(item.scene.imagePath, item.scene.mediaKind)
                if detection.ok then
                    item.scene.imageWidth = detection.width
                    item.scene.imageHeight = detection.height
                    item.scene.imageAspectRatio = Clamp(detection.aspectRatio or 1.0, 0.2, 5.0)
                    print(('^5[DjonStNix Scenes]^7 Corrected ID %s to %dx%d'):format(item.id, detection.width, detection.height))
                    lib.callback.await('djonstnix-scenes:server:updateSceneDimensions', nil, item.id, detection.width, detection.height)
                end
                item.scene.legacyDimensions = false
            end
            Wait(200) -- Small gap between NUI signals
        end
        isProcessingQueue = false
    end)
end

local function HideScenePreview()
    SendNUIMessage({
        action = 'hidePreview'
    })
end

ShowScenePreview = function(imagePath, mediaKind)
    local source = NormalizeImageSource(imagePath)
    if not source then
        return { ok = false }
    end

    local retryCount = math.max(1, tonumber(GetImageConfigValue('previewRetryCount', 2)) or 2)
    local timeoutMs = math.max(5000, tonumber(GetImageConfigValue('previewTimeoutMs', 30000)) or 30000)

    for attempt = 1, retryCount do
        previewRequestCounter = previewRequestCounter + 1
        local requestId = previewRequestCounter
        
        local previewSource = source
        if source:find('^https?://') and not source:find('^https://cfx%-nui%-') then
            local separator = source:find('?', 1, true) and '&' or '?'
            -- Append a unique cache-buster to ensure NUI actually reloads & re-fires the onload event
            previewSource = ('%s%smtc_preview=%s'):format(source, separator, requestId)
        end

        previewRequests[requestId] = {
            id = requestId,
            source = previewSource,
            loaded = nil,
            pending = true,
            width = nil,
            height = nil,
            aspectRatio = 1.0,
        }

        SendNUIMessage({
            action = 'showPreview',
            src = previewSource,
            kind = NormalizeMediaKind(mediaKind),
            requestId = requestId,
        })

        local timeoutAt = GetGameTimer() + timeoutMs
        while previewRequests[requestId].pending and GetGameTimer() < timeoutAt do
            Wait(0)
        end

        local requestResult = previewRequests[requestId]
        if requestResult.loaded == true then
            local result = {
                ok = true,
                width = requestResult.width,
                height = requestResult.height,
                aspectRatio = requestResult.aspectRatio,
            }
            -- Cleanup immediately
            previewRequests[requestId] = nil
            return result
        elseif requestResult.loaded == false then
            -- Let's try again for a few attempts, maybe it's just a slow load
            previewRequests[requestId] = nil
        end
    end

    return { ok = false }
end

local function ConfirmPreview()
    while true do
        Wait(0)

        if IsControlJustPressed(0, 38) then
            HideScenePreview()
            Wait(300) -- Extra settling buffer to prevent preview->placement DUI collisions
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
    local providers = lib.callback.await('djonstnix-scenes:server:getMediaProviders')
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
    local ped = cache.ped
    if not ped or ped == 0 then
        return nil, nil, 0
    end

    local coords = GetEntityCoords(ped)
    local closestId = nil
    local closestScene = nil
    local closestDistance = maxDistance or 1000.0

    for id, scene in pairs(scenes) do
        local sceneCoords = SceneCoords(scene)
        local distance = #(coords - sceneCoords)
        if distance < closestDistance then
            closestDistance = distance
            closestId = id
            closestScene = scene
        end
    end

    return closestId, closestScene, closestDistance
end

local function GetSceneFromAim(maxDistance, tolerance)
    local ped = cache.ped
    if not ped or ped == 0 then
        return nil, nil, nil, 0
    end

    local _, _, rayCoords = lib.raycast.cam()
    if not rayCoords then
        return nil, nil, nil, 0
    end

    local pedCoords = GetEntityCoords(ped)
    local maxRange = maxDistance or 25.0
    local hitTolerance = tolerance or 1.75
    local closestId, closestScene, closestDistance = nil, nil, math.huge

    for id, scene in pairs(scenes) do
        local sceneCoords = SceneCoords(scene)
        local distanceToHit = #(sceneCoords - rayCoords)
        local distanceToPlayer = #(sceneCoords - pedCoords)

        if distanceToPlayer <= maxRange and distanceToHit <= hitTolerance and distanceToHit < closestDistance then
            closestDistance = distanceToHit
            closestId = id
            closestScene = scene
        end
    end

    return closestId, closestScene, rayCoords, closestDistance
end

local function DrawPlacementLaser(targetCoords, color)
    if not targetCoords then
        return
    end

    color = color or { r = 255, g = 70, b = 70 }
    local sourceCoords = GetGameplayCamCoord()
    if cache.ped and cache.ped ~= 0 then
        sourceCoords = GetEntityCoords(cache.ped)
        sourceCoords = vec3(sourceCoords.x, sourceCoords.y, sourceCoords.z + 0.65)
    end

    DrawLine(
        sourceCoords.x, sourceCoords.y, sourceCoords.z,
        targetCoords.x, targetCoords.y, targetCoords.z,
        color.r or 255, color.g or 70, color.b or 70, 220
    )

    DrawMarker(
        28,
        targetCoords.x, targetCoords.y, targetCoords.z + 0.03,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        0.05, 0.05, 0.05,
        color.r or 255, color.g or 70, color.b or 70, 180,
        false,
        false,
        2,
        false,
        nil,
        nil,
        false
    )
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

local function DrawTextLayer(text, coords, fontKey, scale, color, alpha, effect, rotation)
    local cameraCoords = GetGameplayCamCoord()
    local dist = #(cameraCoords - vec3(coords.x, coords.y, coords.z))
    
    -- Basic distance-based culling for performance
    if dist > 30.0 then return end

    local fovScale = (1.0 / GetGameplayCamFov()) * 100.0
    local drawScale = scale * fovScale * 0.45 -- Calibrated for 3D space
    
    local effectScene = {
        textEffect = effect,
        color = color,
    }
    -- Ensure finite coords to prevent engine crashes
    if not coords or not coords.x or not coords.y or not coords.z then return end
    if coords.x ~= coords.x or coords.y ~= coords.y or coords.z ~= coords.z then return end

    SetDrawOrigin(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, 0)
    
    SetTextScale(0.0, drawScale)
    SetTextFont(GetFontId(fontKey))
    SetTextProportional(true)
    SetTextColour(color.r, color.g, color.b, alpha)
    SetTextEntry('STRING')
    SetTextCentre(true)
    ApplyTextEffect(effectScene, alpha)
    AddTextComponentString(text)
    DrawText(0.0, 0.0) -- Coords are 0,0 because of SetDrawOrigin
    
    ClearDrawOrigin()
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


local function GetImageWorldScale(scene)
    local width = tonumber(scene.imageWidth) or 1024
    local height = tonumber(scene.imageHeight) or 1024
    local scale = Clamp(scene.imageScale or GetDefaultImageScale(), 0.1, 20.0)
    
    -- Safety: Zero or negative scale triggers engine crashes
    if width <= 0 then width = 1024 end
    if height <= 0 then height = 1024 end

    -- In world units (meters), 1024px @ 1.0 scale is approximately 1.5 units wide
    local baseUnit = 1.5 * scale
    
    -- We calculate the world-space dimensions based on the original image ratio
    -- This ignores screen aspect ratio entirely, ensuring no distortion on wide monitors.
    local worldWidth = (width / 1024.0) * baseUnit
    local worldHeight = (height / 1024.0) * baseUnit
    
    return worldWidth, worldHeight
end

local function DrawImage3D(scene, id, options)
    local image = GetSceneImage(scene, id)
    if not image then
        return
    end

    options = options or {}
    local alpha = Clamp(options.alpha or 255, 0, 255)
    local sceneCoords = SceneCoords(scene)
    local worldWidth, worldHeight = GetImageWorldScale(scene)
    
    -- Crash Prevention: Validate all texture and numeric parameters
    if not image.txd or not image.txn or image.ready ~= true then return end
    if not worldWidth or not worldHeight or worldWidth <= 0 or worldHeight <= 0 then return end
    if worldWidth ~= worldWidth or worldHeight ~= worldHeight then return end -- NaN Check
    
    local faceCamera = scene.faceCamera ~= false
    local rot = scene.rotation or { x = 0.0, y = 0.0, z = 0.0 }
    local pitch = rot.x or 0.0
    local roll  = rot.y or 0.0
    local yaw   = rot.z or 0.0

    -- UNIFIED OPTIMIZED MARKER RENDERING:
    -- We use DrawMarker(9) for everything to ensure 'Depth Occlusion' (hides behind players/walls).
    -- SCALE FIX: We apply the worldHeight to BOTH the Y and Z axes. 
    -- This ensures that regardless of the specific FiveM build's axis-mapping, 
    -- the image maintains its correct proportions and never 'squishes' into a strip.
    DrawMarker(9, 
        sceneCoords.x, sceneCoords.y, sceneCoords.z, -- Coords
        0.0, 0.0, 0.0, -- Direction
        pitch + 90.0, roll, yaw, -- Rotation
        worldWidth + 0.0, worldHeight + 0.0, worldHeight + 0.0, -- Double-Axis Proportional Fix
        255, 255, 255, alpha, -- Colors
        false, -- Bob
        faceCamera, -- Face Camera (Billboarding)
        0, -- Draw Layer (0 is safest for hardware limits)
        false, -- Rotate
        image.txd, image.txn, 
        false -- Draw on entities
    )

    if GetImageConfigValue('debug', false) then
        local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(sceneCoords.x, sceneCoords.y, sceneCoords.z)
        if onScreen then
            DrawRect(screenX, screenY, 0.01, 0.01, 255, 255, 255, 200)
        end
    end
end

local function DrawScene(scene, id, options)
    options = options or {}

    if isPlacing and id ~= 'placement' then
        return
    end

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

local function RemoveScenePoint(id)
    local point = points[id]
    if point then
        point:remove()
        points[id] = nil
    end
end

local function CreateScenePoint(id, scene)
    local point = lib.points.new({
        coords = SceneCoords(scene),
        distance = scene.distance or GetDefaultDistance(),
    })

    point.sceneId = id
    point.sceneData = scene

    function point:nearby()
        if not ShowScenes then
            return
        end

        DrawScene(self.sceneData, self.sceneId)
    end

    return point
end

local function ScenePointNeedsRebuild(point, scene)
    if not point or not point.sceneData then
        return true
    end

    local current = point.sceneData
    local currentCoords = current.coords or {}
    local nextCoords = scene.coords or {}

    return (current.distance or 0.0) ~= (scene.distance or 0.0)
        or (currentCoords.x or 0.0) ~= (nextCoords.x or 0.0)
        or (currentCoords.y or 0.0) ~= (nextCoords.y or 0.0)
        or (currentCoords.z or 0.0) ~= (nextCoords.z or 0.0)
end

local function UpsertScene(sceneId, rawScene)
    local scene = NormalizeScene(rawScene)
    local point = points[sceneId]

    scenes[sceneId] = scene

    if ScenePointNeedsRebuild(point, scene) then
        if point then
            point:remove()
        end

        point = CreateScenePoint(sceneId, scene)
        points[sceneId] = point
        return
    end

    point.sceneData = scene
end

local function RemoveScene(sceneId)
    RemoveScenePoint(sceneId)
    scenes[sceneId] = nil
    ClearSceneImageResources(sceneId)
end

local function SyncScenes(sceneList)
    local nextIds = {}
    local toRemove = {}

    for uid, rawScene in pairs(sceneList or {}) do
        nextIds[uid] = true
        UpsertScene(uid, rawScene)
    end

    for uid, _ in pairs(scenes) do
        if not nextIds[uid] then
            toRemove[#toRemove + 1] = uid
        end
    end

    for _, uid in ipairs(toRemove) do
        RemoveScene(uid)
    end
end

local function UpdateSceneImageStreaming()
    if not cache.ped or cache.ped == 0 then
        return
    end

    local pedCoords = GetEntityCoords(cache.ped)
    local preloadDistance = math.max(10.0, GetImagePreloadDistance())

    for id, scene in pairs(scenes) do
        if scene.imagePath ~= '' then
            local sceneCoords = SceneCoords(scene)
            local distance = #(sceneCoords - pedCoords)
            local loadDistance = math.max(preloadDistance, (scene.distance or GetDefaultDistance()) + 10.0)
            local unloadDistance = loadDistance + 15.0

            if isPlacing or not ShowScenes then
                if duiTracker[id] then
                    ClearSceneImageResources(id)
                end
            elseif distance <= loadDistance then
                GetSceneImage(scene, id)
            elseif distance > unloadDistance and duiTracker[id] then
                ClearSceneImageResources(id)
            end
        elseif duiTracker[id] then
            ClearSceneImageResources(id)
        end
    end
end

local function ApplyPrimaryScaleDelta(sceneDraft, delta)
    if sceneDraft.imagePath ~= '' then
        sceneDraft.imageScale = Clamp(sceneDraft.imageScale + delta, 0.1, 20.0)
        return
    end

    sceneDraft.textScale = Clamp(sceneDraft.textScale + (delta * 0.16), 0.2, 1.25)
end

local function ApplySecondaryScaleDelta(sceneDraft, delta)
    if sceneDraft.text ~= '' then
        sceneDraft.textScale = Clamp(sceneDraft.textScale + delta, 0.2, 1.25)
    end
end

local function ApplyRotationDelta(sceneDraft, axis, delta)
    sceneDraft.rotation = sceneDraft.rotation or { x = 0.0, y = 0.0, z = 0.0 }
    sceneDraft.rotation[axis] = (sceneDraft.rotation[axis] + delta) % 360.0
end

local function GetCameraPlacementBasis()
    local rotation = GetGameplayCamRot(2)
    local pitch = math.rad(rotation.x or 0.0)
    local yaw = math.rad(rotation.z or 0.0)

    local forward = {
        x = -math.sin(yaw) * math.cos(pitch),
        y = math.cos(yaw) * math.cos(pitch),
        z = math.sin(pitch)
    }

    local length = math.sqrt(forward.x^2 + forward.y^2 + forward.z^2)
    if length > 0 then
        forward.x = forward.x / length
        forward.y = forward.y / length
        forward.z = forward.z / length
    end

    local right = {
        x = math.cos(yaw),
        y = math.sin(yaw),
        z = 0.0,
    }

    return forward, right
end

local function ApplyPositionDelta(offset, direction, delta)
    offset.x = (offset.x or 0.0) + ((direction.x or 0.0) * delta)
    offset.y = (offset.y or 0.0) + ((direction.y or 0.0) * delta)
    offset.z = (offset.z or 0.0) + ((direction.z or 0.0) * delta)
end

local function GetPlacementAnchorCoords()
    local _, _, rayCoords = lib.raycast.cam()
    if rayCoords then
        return {
            x = rayCoords.x + 0.0,
            y = rayCoords.y + 0.0,
            z = rayCoords.z + 0.0,
        }
    end

    local pedCoords = GetEntityCoords(cache.ped)
    local forward = GetCameraPlacementBasis()
    local fallbackDistance = math.max(2.0, GetDefaultDistance())

    return {
        x = pedCoords.x + ((forward.x or 0.0) * fallbackDistance),
        y = pedCoords.y + ((forward.y or 0.0) * fallbackDistance),
        z = pedCoords.z + ((forward.z or 0.0) * fallbackDistance),
    }
end

local function DisablePlacementCombatControls()
    DisablePlayerFiring(cache.playerId, true)
    for _, group in ipairs({ 0, 1, 2 }) do
        DisableControlAction(group, 24, true) -- attack
        DisableControlAction(group, 25, true) -- aim
        DisableControlAction(group, 37, true) -- weapon wheel
        DisableControlAction(group, 69, true)
        DisableControlAction(group, 70, true)
        DisableControlAction(group, 92, true)
        DisableControlAction(group, 140, true)
        DisableControlAction(group, 141, true)
        DisableControlAction(group, 142, true)
        DisableControlAction(group, 257, true)
        DisableControlAction(group, 263, true)
        DisableControlAction(group, 264, true)
    end
end

local function DisablePlacementMovementControls()
    for _, group in ipairs({ 0, 1, 2 }) do
        DisableControlAction(group, 30, true) -- move left/right axis
        DisableControlAction(group, 31, true) -- move forward/back axis
        DisableControlAction(group, 32, true) -- W
        DisableControlAction(group, 33, true) -- S
        DisableControlAction(group, 34, true) -- A
        DisableControlAction(group, 35, true) -- D
        DisableControlAction(group, 22, true) -- SPACE
        DisableControlAction(group, 36, true) -- CTRL
    end
end

local function CoordPicker(sceneDraft)
    sceneDraft = NormalizeScene(sceneDraft)
    local previewScene = sceneDraft

    isPlacing = true -- Acquire placement lock
    isPlacing = true -- Acquire placement lock
    local positionOffset = { x = 0.0, y = 0.0, z = 0.0 }
    local depthOffset = 0.0
    local controlsLocked = false
    local enabled = true
    local promiseRef = promise.new()

    lib.showTextUI([[
E → Confirm Placement  
BACKSPACE → Cancel  

F3 → Toggle Movement/Combat Lock  

ALT + W/S → Move Forward / Back  
ALT + A/D → Move Left / Right  
ALT + SPACE / CTRL → Move Up / Down  

Arrow Up / Down → Tilt Forward / Back  
Arrow Left / Right → Tilt Left / Right  

Q / R → Rotate (Spin)  

Mouse Wheel → Scale  
SHIFT → Precision Mode  

G → Reset Position  
F → Toggle Face Camera
]], {
        position = 'bottom-center'
    })

    -- Placement Render Thread
    CreateThread(function()
        local offset = 0.2
        while enabled do
            Wait(0)

            local baseCoords = GetPlacementAnchorCoords()
            local coords = {
                x = baseCoords.x,
                y = baseCoords.y,
                z = baseCoords.z,
            }
            local forward, _ = GetCameraPlacementBasis()
            coords.x = coords.x + positionOffset.x + ((forward.x or 0.0) * depthOffset)
            coords.y = coords.y + positionOffset.y + ((forward.y or 0.0) * depthOffset)
            coords.z = coords.z + positionOffset.z + ((forward.z or 0.0) * depthOffset)

            previewScene.coords = coords

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

            DrawPlacementLaser(coords, { r = 255, g = 85, b = 85 })

            DrawScene(previewScene, 'placement', {
                alpha = 225
            })

            -- Visual Axis Helper: Draw a small 3D crosshair at the center to show orientation
            local helperScale = 0.1
            -- X Axis (Red)
            DrawLine(coords.x, coords.y, coords.z, coords.x + helperScale, coords.y, coords.z, 255, 0, 0, 150)
            -- Y Axis (Green)
            DrawLine(coords.x, coords.y, coords.z, coords.x, coords.y + helperScale, coords.z, 0, 255, 0, 150)
            -- Z Axis (Blue)
            DrawLine(coords.x, coords.y, coords.z, coords.x, coords.y, coords.z + helperScale, 0, 0, 255, 150)
        end
    end)

    -- Placement Control Thread
    CreateThread(function()
        while enabled do
            Wait(0)

            -- Toggle Lock
            if IsControlJustPressed(0, 170) then
                controlsLocked = not controlsLocked
                if controlsLocked then
                    PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
                else
                    PlaySoundFrontend(-1, "CANCEL", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
                end
            end

            -- Apply Conditional Disables
            if controlsLocked then
                DisablePlacementCombatControls()
                DisablePlacementMovementControls()
            end

            -- Essential Disables (Always Active)
            DisableControlAction(0, 23, true) -- enter / vehicle
            DisableControlAction(0, 75, true) -- exit vehicle
            DisableControlAction(0, 200, true) -- pause

            local shiftHeld = IsControlPressed(0, 21) -- Shift (Precision)
            local rotationSpeed = shiftHeld and 0.35 or 1.5
            local moveSpeed = shiftHeld and 0.01 or 0.04
            local primaryScaleDelta = shiftHeld and 0.04 or 0.12
            local secondaryScaleDelta = shiftHeld and 0.01 or 0.03
            local _, right = GetCameraPlacementBasis()

            -- Manual Position Nudges (Require Alt to not block movement)
            if IsControlPressed(0, 19) then -- LEFT ALT
                if IsDisabledControlPressed(0, 32) then -- W
                    depthOffset = depthOffset + moveSpeed
                elseif IsDisabledControlPressed(0, 33) then -- S
                    depthOffset = depthOffset - moveSpeed
                end

                if IsDisabledControlPressed(0, 34) then -- A
                    ApplyPositionDelta(positionOffset, right, -moveSpeed)
                elseif IsDisabledControlPressed(0, 35) then -- D
                    ApplyPositionDelta(positionOffset, right, moveSpeed)
                end

                if IsDisabledControlPressed(0, 22) then -- SPACE
                    positionOffset.z = positionOffset.z + moveSpeed
                elseif IsDisabledControlPressed(0, 36) then -- CTRL
                    positionOffset.z = positionOffset.z - moveSpeed
                end
                
                -- Disable movement when Alt is held for precision
                DisablePlacementMovementControls()
            end

            -- Scaling
            if IsControlJustPressed(0, 15) then
                if shiftHeld then
                    ApplySecondaryScaleDelta(sceneDraft, secondaryScaleDelta)
                else
                    ApplyPrimaryScaleDelta(sceneDraft, primaryScaleDelta)
                end
            end

            if IsControlJustPressed(0, 14) then
                if shiftHeld then
                    ApplySecondaryScaleDelta(sceneDraft, -secondaryScaleDelta)
                else
                    ApplyPrimaryScaleDelta(sceneDraft, -primaryScaleDelta)
                end
            end

            -- Rotation (Seesaw Behavior)
            -- Arrow Up/Down = Pitch (X axis), Arrow Left/Right = Roll (Y axis)
            if IsControlPressed(0, 172) then -- Arrow Up
                ApplyRotationDelta(sceneDraft, 'x', rotationSpeed)
            elseif IsControlPressed(0, 173) then -- Arrow Down
                ApplyRotationDelta(sceneDraft, 'x', -rotationSpeed)
            elseif IsControlPressed(0, 174) then -- Arrow Left
                ApplyRotationDelta(sceneDraft, 'y', rotationSpeed)
            elseif IsControlPressed(0, 175) then -- Arrow Right
                ApplyRotationDelta(sceneDraft, 'y', -rotationSpeed)
            end

            -- Spin the whole image on its facing axis
            if IsControlPressed(0, 44) then -- Q
                ApplyRotationDelta(sceneDraft, 'z', rotationSpeed)
            end

            if IsControlPressed(0, 45) then -- R
                ApplyRotationDelta(sceneDraft, 'z', -rotationSpeed)
            end

            if IsControlJustPressed(0, 47) then -- G
                positionOffset = { x = 0.0, y = 0.0, z = 0.0 }
                depthOffset = 0.0
            end

            -- Toggles
            if IsControlJustPressed(0, 49) then -- F
                sceneDraft.faceCamera = not sceneDraft.faceCamera
                QBCore.Functions.Notify('Face Camera: ' .. (sceneDraft.faceCamera and 'ON' or 'OFF'), 'primary')
            end

            if IsControlJustPressed(0, 38) then -- E
                local baseCoords = GetPlacementAnchorCoords()
                local forward, _ = GetCameraPlacementBasis()
                local coords = {
                    x = baseCoords.x + positionOffset.x + ((forward.x or 0.0) * depthOffset),
                    y = baseCoords.y + positionOffset.y + ((forward.y or 0.0) * depthOffset),
                    z = baseCoords.z + positionOffset.z + ((forward.z or 0.0) * depthOffset),
                }

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
                    rotation = sceneDraft.rotation,
                    faceCamera = sceneDraft.faceCamera,
                })
            elseif IsControlJustPressed(0, 177) then -- BACKSPACE
                enabled = false
                lib.hideTextUI()
                promiseRef:resolve(nil)
            end
        end
    end)

    local result = Citizen.Await(promiseRef)
    ReleaseImageReference('placement')
    isPlacing = false -- Release placement lock
    return result
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
            min = 10,
            max = 2000,
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
            default = math.floor(draft.distance * 10),
            min = 10,
            max = 200,
            required = true,
        },
        {
            type = 'checkbox',
            label = Lang:t('createScene.face_camera_label'),
            description = Lang:t('createScene.face_camera_description'),
            checked = draft.faceCamera,
        },
        {
            type = 'slider',
            label = Lang:t('createScene.rotation_x_label'),
            description = Lang:t('createScene.rotation_x_description'),
            default = math.floor(draft.rotation.x or 0),
            min = 0,
            max = 360,
        },
        {
            type = 'slider',
            label = Lang:t('createScene.rotation_y_label'),
            description = Lang:t('createScene.rotation_y_description'),
            default = math.floor(draft.rotation.y or 0),
            min = 0,
            max = 360,
        },
        {
            type = 'slider',
            label = Lang:t('createScene.rotation_z_label'),
            description = Lang:t('createScene.rotation_z_description'),
            default = math.floor(draft.rotation.z or 0),
            min = 0,
            max = 360,
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

    local faceCameraIndex = 11
    local rotationXIndex = 12
    local rotationYIndex = 13
    local rotationZIndex = 14
    local repositionIndex = includeReposition and 15 or nil

    local result = {
        text = Trim(input[1]),
        color = ToRGB(input[2]),
        font = input[3] or draft.font,
        textEffect = input[4] or draft.textEffect,
        textAnimation = input[5] or draft.textAnimation,
        textScale = Clamp((tonumber(input[6]) or math.floor(GetDefaultTextScale() * 100)) / 100, 0.2, 1.25),
        imagePath = Trim(input[7]),
        imageScale = Clamp((tonumber(input[8]) or math.floor(GetDefaultImageScale() * 100)) / 100, 0.1, 20.0),
        durationMinutes = Clamp(tonumber(input[9]) or 0, 0, 43200),
        distance = Clamp((tonumber(input[10]) or math.floor(GetDefaultDistance() * 10)) / 10, 1.0, 20.0),
        imageWidth = draft.imageWidth or 1024,
        imageHeight = draft.imageHeight or 1024,
        imageAspectRatio = draft.imageAspectRatio or 1.0,
        mediaKind = draft.mediaKind or 'image',
        mediaExtension = draft.mediaExtension or '',
        mediaAnimated = draft.mediaAnimated == true,
        reposition = repositionIndex and input[repositionIndex] == true or false,
        faceCamera = input[faceCameraIndex] ~= nil and input[faceCameraIndex] or draft.faceCamera,
        rotation = {
            x = tonumber(input[rotationXIndex]) or draft.rotation.x or 0.0,
            y = tonumber(input[rotationYIndex]) or draft.rotation.y or 0.0,
            z = tonumber(input[rotationZIndex]) or draft.rotation.z or 0.0,
        },
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
        sceneDraft.mediaKind = 'image'
        sceneDraft.mediaExtension = ''
        sceneDraft.mediaAnimated = false
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
    sceneDraft.mediaKind = NormalizeMediaKind(validation.mediaKind)
    sceneDraft.mediaExtension = Trim(validation.mediaExtension):lower()
    sceneDraft.mediaAnimated = validation.mediaAnimated == true

    local preview = ShowScenePreview(sceneDraft.imagePath, sceneDraft.mediaKind)
    if not preview.ok then
        HideScenePreview()
        QBCore.Functions.Notify(Lang:t('notify.preview_failed'), 'error')
        return false
    end

    -- 🔥 STEP 1: Keep placement DUI alive until handover or timeout
    CreateThread(function()
        local timeout = GetGameTimer() + 2000 -- Max 2 seconds protection

        while GetGameTimer() < timeout do
            local hasRealScene = false

            -- If any persistent scene exists now, we can safely release the ghost
            for id, _ in pairs(scenes) do
                if id ~= 'placement' then
                    hasRealScene = true
                    break
                end
            end

            if hasRealScene then
                break
            end

            Wait(50)
        end

        ReleaseImageReference('placement')
    end)

    sceneDraft.imageWidth = tonumber(preview.width) or 1024
    sceneDraft.imageHeight = tonumber(preview.height) or 1024
    sceneDraft.imageAspectRatio = Clamp(preview.aspectRatio or 1.0, 0.2, 5.0)

    print(('^5[DjonStNix Scenes]^7 Loaded Image: %dx%d (Ratio: %.2f)'):format(
        sceneDraft.imageWidth,
        sceneDraft.imageHeight,
        sceneDraft.imageAspectRatio
    ))

    QBCore.Functions.Notify(Lang:t('notify.preview_loaded'), 'success')

    if not ConfirmPreview() then
        QBCore.Functions.Notify(Lang:t('notify.preview_cancelled'), 'error')
        return false
    end

    return true
end

local function toggleScenes()
    ShowScenes = not ShowScenes
    UpdateSceneImageStreaming()
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
    sceneDraft.rotation = placement.rotation or sceneDraft.rotation
    sceneDraft.faceCamera = placement.faceCamera ~= nil and placement.faceCamera or sceneDraft.faceCamera

    local result = lib.callback.await('djonstnix-scenes:server:newScene', nil, sceneDraft)

    NotifyResult(result, 'scene_created', 'failed')
    
    -- 🔥 STEP 2: Force immediate acquisition of the new scene's DUI
    UpdateSceneImageStreaming()
end

local function browseSceneMedia()
    local selection = OpenMediaBrowser()
    if not selection or Trim(selection.url) == '' then
        return
    end

    local seedScene = BuildSceneDraft()
    seedScene.imagePath = Trim(selection.url)
    seedScene.mediaKind = NormalizeMediaKind(selection.mediaKind)
    seedScene.mediaExtension = Trim(selection.mediaExtension):lower()
    seedScene.mediaAnimated = selection.mediaAnimated == true

    local width = tonumber(selection.width) or 0
    local height = tonumber(selection.height) or 0
    if width > 0 and height > 0 then
        seedScene.imageWidth = width
        seedScene.imageHeight = height
        seedScene.imageAspectRatio = Clamp(width / height, 0.2, 5.0)
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
        sceneDraft.rotation = placement.rotation or sceneDraft.rotation
        sceneDraft.faceCamera = placement.faceCamera ~= nil and placement.faceCamera or sceneDraft.faceCamera
    else
        sceneDraft.coords = scene.coords
    end

    local result = lib.callback.await('djonstnix-scenes:server:updateScene', nil, index, sceneDraft)
    NotifyResult(result, 'scene_updated', 'failed_update')
end

local function clearNearbyScenes()
    local input = lib.inputDialog(Lang:t('createScene.cleanup_title'), {
        {
            type = 'slider',
            label = Lang:t('createScene.cleanup_radius_label'),
            description = Lang:t('createScene.cleanup_radius_description'),
            default = 5,
            min = 1,
            max = 50,
            required = true,
        }
    })

    if not input then return end

    local radius = tonumber(input[1])
    local result = lib.callback.await('djonstnix-scenes:server:clearArea', false, radius)
    
    if result and result.ok then
        QBCore.Functions.Notify(Lang:t('notify.cleaned_area'):format(result.count), 'success')
    else
        NotifyResult(result, 'cleaned_area', 'scene_no_permission')
    end
end

local function destroyAimedScene()
    local enabled = true
    local promiseRef = promise.new()

    lib.showTextUI(Lang:t('textUI.destroy_preview'), {
        position = 'bottom-center'
    })

    CreateThread(function()
        while enabled do
            Wait(0)

            local targetId, targetScene, rayCoords = GetSceneFromAim(25.0, 2.0)

            if rayCoords then
                DrawPlacementLaser(rayCoords, { r = 255, g = 60, b = 60 })
            end

            if targetScene then
                local sceneCoords = SceneCoords(targetScene)
                DrawBox(
                    sceneCoords.x - 0.22,
                    sceneCoords.y - 0.22,
                    sceneCoords.z - 0.22,
                    sceneCoords.x + 0.22,
                    sceneCoords.y + 0.22,
                    sceneCoords.z + 0.22,
                    255,
                    70,
                    70,
                    90
                )
                DrawPlacementLaser(sceneCoords, { r = 255, g = 60, b = 60 })
            end

            if IsControlJustPressed(0, 38) then -- E
                enabled = false
                lib.hideTextUI()
                promiseRef:resolve(targetId)
            elseif IsControlJustPressed(0, 177) then -- BACKSPACE
                enabled = false
                lib.hideTextUI()
                promiseRef:resolve(false)
            end
        end
    end)

    local targetId = Citizen.Await(promiseRef)
    if targetId == false then
        return
    end

    if not targetId then
        QBCore.Functions.Notify(Lang:t('notify.scene_nearby'), 'error')
        return
    end

    local result = lib.callback.await('djonstnix-scenes:server:destroyScene', nil, targetId)
    NotifyResult(result, 'succes_destroy', 'failed_destroy')
end

local function OpenSceneMenu()
    local nearestIndex, nearestScene, nearestDistance = GetClosestScene(3.0)
    local nearestDescription = nearestScene and
        (Lang:t('optionsScene.nearest_scene') .. (' %.1fm | %s'):format(nearestDistance, nearestScene.ownerName ~= '' and nearestScene.ownerName or Lang:t('optionsScene.unknown_owner')))
        or Lang:t('optionsScene.no_scene')

    local manageOptions = {
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
            onSelect = destroyAimedScene,
        },
    }

    -- Administrative cleanup option
    local isAdmin = lib.callback.await('djonstnix-scenes:server:hasAdminPermission', false)
    if isAdmin then
        manageOptions[#manageOptions + 1] = {
            title = Lang:t('optionsScene.cleanup'),
            description = Lang:t('optionsScene.cleanup_description'),
            icon = 'broom',
            onSelect = clearNearbyScenes,
        }
    end

    lib.registerContext({
        id = 'djonstnix-scenes-manage',
        title = Lang:t('optionsScene.manage'),
        menu = 'djonstnix-scenes',
        options = manageOptions
    })

    lib.registerContext({
        id = 'djonstnix-scenes',
        title = GetUIConfigValue('menuTitle', 'DjonStNix Scenes'),
        options = {
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
                title = Lang:t('optionsScene.manage'),
                description = Lang:t('optionsScene.manage_description'),
                icon = 'sliders',
                menu = 'djonstnix-scenes-manage',
            },
            {
                title = Lang:t('optionsScene.toggle'),
                description = Lang:t('optionsScene.toggle_description'),
                icon = 'eye',
                onSelect = toggleScenes,
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

    local result = lib.callback.await('djonstnix-scenes:server:searchMedia', nil, provider, query)
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

RegisterNetEvent('djonstnix-scenes:client:setScenes', function(serverScenes)
    SyncScenes(serverScenes or {})
end)

RegisterNetEvent('djonstnix-scenes:client:upsertScene', function(scene)
    if not scene or not scene.id then
        return
    end

    UpsertScene(scene.id, scene)
end)

RegisterNetEvent('djonstnix-scenes:client:removeScenes', function(sceneIds)
    for _, sceneId in ipairs(sceneIds or {}) do
        if sceneId ~= 'placement' or not isPlacing then
            RemoveScene(sceneId)
        end
    end
end)

RegisterNetEvent('djonstnix-scenes:client:refreshScenes', function(serverScenes)
    SyncScenes(serverScenes or {})
end)

RegisterNUICallback('scenePreviewStatus', function(data, cb)
    local requestId = tonumber(data.requestId)
    if not requestId or not previewRequests[requestId] then
        cb({ ok = true })
        return
    end

    local request = previewRequests[requestId]
    request.loaded = data.loaded == true
    request.width = tonumber(data.width) or 1024
    request.height = tonumber(data.height) or 1024

    if request.width and request.height and request.height > 0 then
        request.aspectRatio = Clamp(request.width / request.height, 0.2, 5.0)
    else
        request.aspectRatio = 1.0
    end

    request.pending = false
    cb({ ok = true })
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    CloseMediaBrowser(nil)
    HideScenePreview()
    -- Note: We avoid explicitly calling DestroyImageCache here.
    -- FiveM cleanup during onResourceStop is often the source of 'glucose-sodium-nineteen'.
    -- The engine naturally discards allocated NUI/DUI memory as the resource environment dies.
end)

CreateThread(function()
    while true do
        local now = GetGameTimer()
        for i = #destructionQueue, 1, -1 do
            local item = destructionQueue[i]
            if now > item.expireAt then
                if item.dui then
                    DestroyDui(item.dui)
                    item.dui = nil -- Guard against double destruction
                end
                table.remove(destructionQueue, i)
            end
        end
        Wait(1000)
    end
end)

CreateThread(function()
    local serverScenes = lib.callback.await('djonstnix-scenes:server:getScenes')
    SyncScenes(serverScenes or {})
end)

CreateThread(function()
    while true do
        Wait(100)
        UpdateSceneImageStreaming()
    end
end)
