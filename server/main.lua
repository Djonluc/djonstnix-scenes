local import = require('server.json')
local BanIdentifier, IsBanned, SaveScenes, GetSavedScenes = import[1], import[2], import[3], import[4]

local scenes = {}
local preparedRemoteImages = {}
math.randomseed(os.time())

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

local function UrlEncode(value)
    if value == nil then
        return ''
    end

    value = tostring(value)
    value = value:gsub('\n', '\r\n')
    value = value:gsub('([^%w%-_%.~])', function(char)
        return string.format('%%%02X', string.byte(char))
    end)

    return value
end

local function BuildQueryString(params)
    local parts = {}

    for key, value in pairs(params or {}) do
        if value ~= nil and tostring(value) ~= '' then
            parts[#parts + 1] = ('%s=%s'):format(UrlEncode(key), UrlEncode(value))
        end
    end

    return table.concat(parts, '&')
end

local function GetIdentifier(player, identifierType)
    for _, identifier in pairs(GetPlayerIdentifiers(player)) do
        if string.find(identifier, identifierType) then
            return identifier
        end
    end

    return nil
end

local function GetImageConfig()
    return Config and Config.SceneImages or {}
end

local function GetPermissionConfig()
    return Config and Config.ScenePermissions or {}
end

local function GetMediaConfig()
    return Config and Config.SceneMedia or {}
end

local function GetFivemanageApiKey()
    return Trim(GetConvar('djonstnix-scenes:fivemanageApiKey', ''))
end

local function GetTenorApiKey()
    return Trim(GetConvar('djonstnix-scenes:tenorApiKey', ''))
end

local function GetDefaultDistance()
    local config = GetImageConfig()
    return tonumber(config.defaultDistance) or 7.5
end

local function GetDefaultImageScale()
    local config = GetImageConfig()
    return tonumber(config.defaultImageScale) or 2.25
end

local function GetDefaultTextScale()
    local config = GetImageConfig()
    return tonumber(config.defaultTextScale) or 0.48
end

local function NormalizeColor(color)
    color = color or {}

    return {
        r = Clamp(color.r or color[1] or 255, 0, 255),
        g = Clamp(color.g or color[2] or 255, 0, 255),
        b = Clamp(color.b or color[3] or 255, 0, 255),
    }
end

local function NormalizeCoords(coords)
    if type(coords) ~= 'table' then
        return nil
    end

    local x = tonumber(coords.x or coords[1])
    local y = tonumber(coords.y or coords[2])
    local z = tonumber(coords.z or coords[3])

    if not x or not y or not z then
        return nil
    end

    return {
        x = x + 0.0,
        y = y + 0.0,
        z = z + 0.0,
    }
end

local function GetUrlHost(url)
    local host = url:match('^https?://([^/%?#]+)')
    if not host then
        return nil
    end

    return host:lower():gsub(':%d+$', '')
end

local function GetPathExtension(path)
    local cleanPath = path:match('^[^?#]+') or path
    return cleanPath:match('%.([%w]+)$')
end

local function GetExtensionFromContentType(contentType)
    if not contentType then
        return 'png'
    end

    local extensions = {
        ['image/png'] = 'png',
        ['image/jpeg'] = 'jpg',
        ['image/webp'] = 'webp',
        ['image/gif'] = 'gif',
        ['image/bmp'] = 'bmp',
        ['image/tiff'] = 'tiff',
        ['image/svg+xml'] = 'svg',
        ['image/x-icon'] = 'ico',
        ['image/heic'] = 'heic',
    }

    return extensions[contentType:lower()] or 'png'
end

local function IsAllowedExtension(path)
    local config = GetImageConfig()
    local extension = GetPathExtension(path)
    if not extension then
        return false
    end

    extension = extension:lower()
    return config.allowedExtensions and config.allowedExtensions[extension] == true
end

local function IsAllowedHost(host, allowedHosts)
    local config = GetImageConfig()
    allowedHosts = allowedHosts or config.allowedStoredHosts
    if not allowedHosts or #allowedHosts == 0 then
        return false
    end

    host = host:lower()

    for _, allowedHost in ipairs(allowedHosts) do
        allowedHost = allowedHost:lower()

        if allowedHost:sub(1, 2) == '*.' then
            local suffix = allowedHost:sub(2)
            if host:sub(-#suffix) == suffix then
                return true
            end
        elseif host == allowedHost then
            return true
        end
    end

    return false
end

local function GetHeader(headers, targetName)
    if type(headers) ~= 'table' then
        return nil
    end

    targetName = targetName:lower()
    for name, value in pairs(headers) do
        if tostring(name):lower() == targetName then
            return tostring(value)
        end
    end

    return nil
end

local function IsImageContentType(contentType)
    return contentType and contentType:lower():find('image/', 1, true) ~= nil
end

local function PerformHttpRequestAwait(url, method, body, headers)
    local promiseRef = promise.new()

    PerformHttpRequest(url, function(statusCode, responseBody, responseHeaders, errorData)
        promiseRef:resolve({
            statusCode = statusCode,
            body = responseBody,
            headers = responseHeaders,
            errorData = errorData
        })
    end, method or 'GET', body or '', headers or {})

    return Citizen.Await(promiseRef)
end

local function GetMediaProviderConfig(providerName)
    local mediaConfig = GetMediaConfig()
    local providers = mediaConfig.providers or {}
    return providers[providerName or ''] or {}
end

local function GetEnabledMediaProviders()
    local providers = {}
    local tenorConfig = GetMediaProviderConfig('tenor')

    if tenorConfig.enabled ~= false and GetTenorApiKey() ~= '' then
        providers[#providers + 1] = {
            id = 'tenor',
            label = Trim(tenorConfig.label) ~= '' and tenorConfig.label or 'Tenor',
        }
    end

    return providers
end

local function BuildMediaResult(provider, id, title, mediaUrl, previewUrl, width, height)
    mediaUrl = Trim(mediaUrl)
    previewUrl = Trim(previewUrl)

    if mediaUrl == '' then
        return nil
    end

    return {
        provider = provider,
        id = Trim(id),
        title = Trim(title),
        url = mediaUrl,
        previewUrl = previewUrl ~= '' and previewUrl or mediaUrl,
        width = tonumber(width) or 0,
        height = tonumber(height) or 0,
    }
end

local function SearchTenorMedia(query)
    local tenorConfig = GetMediaProviderConfig('tenor')
    local apiKey = GetTenorApiKey()
    if apiKey == '' or tenorConfig.enabled == false then
        return nil, 'browser_not_configured'
    end

    query = Trim(query)
    if query == '' then
        return {}
    end

    local endpoint = (Trim(tenorConfig.apiBaseUrl) ~= '' and Trim(tenorConfig.apiBaseUrl) or 'https://tenor.googleapis.com/v2') .. '/search'
    local url = endpoint .. '?' .. BuildQueryString({
        key = apiKey,
        client_key = Trim(tenorConfig.clientKey) ~= '' and Trim(tenorConfig.clientKey) or GetCurrentResourceName(),
        q = query,
        limit = Clamp(tonumber(tenorConfig.limit) or 18, 1, 50),
        media_filter = Trim(tenorConfig.mediaFilter) ~= '' and Trim(tenorConfig.mediaFilter) or 'gif,tinygif,mediumgif',
        contentfilter = Trim(tenorConfig.contentFilter) ~= '' and Trim(tenorConfig.contentFilter) or 'medium',
    })

    local response = PerformHttpRequestAwait(url, 'GET', '', {
        ['Accept'] = 'application/json',
        ['User-Agent'] = 'djonstnix-scenes/1.0',
    })

    if not response.statusCode or response.statusCode < 200 or response.statusCode >= 300 or not response.body or response.body == '' then
        return nil, 'browser_search_failed'
    end

    local ok, decoded = pcall(json.decode, response.body)
    if not ok or type(decoded) ~= 'table' or type(decoded.results) ~= 'table' then
        return nil, 'browser_search_failed'
    end

    local results = {}
    for _, item in ipairs(decoded.results) do
        local mediaFormats = type(item.media_formats) == 'table' and item.media_formats or {}
        local primary = mediaFormats.gif or mediaFormats.mediumgif or mediaFormats.tinygif or mediaFormats.nanogif or mediaFormats.webp or mediaFormats.gifpreview
        local preview = mediaFormats.tinygif or mediaFormats.nanogif or mediaFormats.gifpreview or primary

        local dims = {}
        if type(primary) == 'table' and type(primary.dims) == 'table' then
            dims = primary.dims
        elseif type(preview) == 'table' and type(preview.dims) == 'table' then
            dims = preview.dims
        end

        local result = BuildMediaResult(
            'tenor',
            item.id or '',
            item.content_description or item.title or query,
            type(primary) == 'table' and primary.url or '',
            type(preview) == 'table' and preview.url or '',
            dims[1],
            dims[2]
        )

        if result then
            results[#results + 1] = result
        end
    end

    return results, nil
end

local function Base64Encode(data)
    local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    return ((data:gsub('.', function(char)
        local binary = ''
        local byte = char:byte()

        for i = 8, 1, -1 do
            binary = binary .. (byte % 2 ^ i - byte % 2 ^ (i - 1) > 0 and '1' or '0')
        end

        return binary
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(bits)
        if #bits < 6 then
            return ''
        end

        local value = 0
        for i = 1, 6 do
            if bits:sub(i, i) == '1' then
                value = value + 2 ^ (6 - i)
            end
        end

        return alphabet:sub(value + 1, value + 1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

local function BuildUploadFilename(extension)
    extension = Trim(extension)
    if extension == '' then
        extension = 'png'
    end

    return ('scene-%s-%06d.%s'):format(os.time(), math.random(0, 999999), extension)
end

local function NormalizeDurationMinutes(value)
    return Clamp(value or 0, 0, 43200)
end

local function BuildExpiresAt(durationMinutes)
    durationMinutes = NormalizeDurationMinutes(durationMinutes)
    if durationMinutes <= 0 then
        return nil, 0
    end

    return os.time() + (durationMinutes * 60), durationMinutes
end

local function IsSceneExpired(scene)
    return scene and scene.expiresAt and tonumber(scene.expiresAt) and tonumber(scene.expiresAt) > 0 and tonumber(scene.expiresAt) <= os.time()
end

local function PruneExpiredScenes()
    local removed = false

    for index = #scenes, 1, -1 do
        if IsSceneExpired(scenes[index]) then
            table.remove(scenes, index)
            removed = true
        end
    end

    return removed
end

local function HasAdminPermission(source)
    local permissionConfig = GetPermissionConfig()
    local adminGroups = permissionConfig.adminGroups or { 'god', 'admin' }

    if not QBCore or not QBCore.Functions or not QBCore.Functions.HasPermission then
        return false
    end

    for _, group in ipairs(adminGroups) do
        if QBCore.Functions.HasPermission(source, group) then
            return true
        end
    end

    return false
end

local function CanManageScene(source, scene)
    if HasAdminPermission(source) then
        return true
    end

    local identifier = GetIdentifier(source, 'license')
    if not identifier or not scene then
        return false
    end

    return scene.ownerIdentifier and scene.ownerIdentifier == identifier
end

local function ValidateStoredRemoteImage(url)
    local config = GetImageConfig()
    if not config.validateStoredRemoteImages then
        return true
    end

    local response = PerformHttpRequestAwait(url, 'GET', '', {
        ['Accept'] = 'image/*,*/*;q=0.8',
        ['User-Agent'] = 'djonstnix-scenes/1.0',
        ['Range'] = 'bytes=0-1024',
    })

    local contentType = GetHeader(response.headers, 'content-type')
    return response.statusCode and response.statusCode >= 200 and response.statusCode < 400 and IsImageContentType(contentType)
end

local function UploadImageDataToFivemanage(dataUri, filename)
    local config = GetImageConfig()
    local apiKey = GetFivemanageApiKey()
    if apiKey == '' then
        return nil, 'image_upload_not_configured'
    end

    local payload = json.encode({
        base64 = dataUri,
        filename = filename
    })

    local response = PerformHttpRequestAwait(config.fivemanageBase64ApiUrl, 'POST', payload, {
        ['Authorization'] = apiKey,
        ['Content-Type'] = 'application/json',
    })

    if not response.statusCode or response.statusCode < 200 or response.statusCode >= 300 then
        return nil, 'image_upload_failed'
    end

    if not response.body or response.body == '' then
        return nil, 'image_upload_failed'
    end

    local ok, decoded = pcall(json.decode, response.body)
    if not ok or type(decoded) ~= 'table' or type(decoded.data) ~= 'table' or type(decoded.data.url) ~= 'string' or decoded.data.url == '' then
        return nil, 'image_upload_failed'
    end

    return decoded.data.url, nil
end

local function RehostRemoteImage(imageUrl)
    local config = GetImageConfig()
    local response = PerformHttpRequestAwait(imageUrl, 'GET', '', {
        ['Accept'] = 'image/*,*/*;q=0.8',
        ['User-Agent'] = 'djonstnix-scenes/1.0',
    })

    if not response.statusCode or response.statusCode < 200 or response.statusCode >= 300 then
        return nil, 'image_remote_unreachable'
    end

    local contentType = GetHeader(response.headers, 'content-type')
    if not IsImageContentType(contentType) then
        return nil, 'image_remote_unreachable'
    end

    local body = response.body or ''
    if body == '' then
        return nil, 'image_remote_unreachable'
    end

    local contentLength = tonumber(GetHeader(response.headers, 'content-length'))
    local bodyLength = #body
    local maxFileSize = tonumber(config.maxRemoteFileSize) or (8 * 1024 * 1024)
    local size = contentLength or bodyLength
    if size > maxFileSize or bodyLength > maxFileSize then
        return nil, 'image_remote_too_large'
    end

    local filename = BuildUploadFilename(GetExtensionFromContentType(contentType))
    local dataUri = ('data:%s;base64,%s'):format(contentType, Base64Encode(body))
    return UploadImageDataToFivemanage(dataUri, filename)
end

local function NormalizeHostedUrl(imageUrl, skipValidation)
    local host = GetUrlHost(imageUrl)
    if not host or not IsAllowedHost(host) then
        return nil, 'image_not_allowed_host'
    end

    if not skipValidation and not ValidateStoredRemoteImage(imageUrl) then
        return nil, 'image_remote_unreachable'
    end

    return imageUrl, nil
end

local function PrepareRemoteImage(imagePath)
    local config = GetImageConfig()

    if config.requireHttps and imagePath:find('^http://') then
        return nil, 'image_https_required'
    end

    local host = GetUrlHost(imagePath)
    if not host then
        return nil, 'image_invalid_url'
    end

    if config.requireImageExtension and not IsAllowedExtension(imagePath) then
        return nil, 'image_invalid_extension'
    end

    if IsAllowedHost(host) then
        return NormalizeHostedUrl(imagePath)
    end

    if config.mirrorExternalUrlsToFivemanage then
        local cachedUrl = preparedRemoteImages[imagePath]
        if cachedUrl then
            return NormalizeHostedUrl(cachedUrl, true)
        end

        local uploadedUrl, uploadReason = RehostRemoteImage(imagePath)
        if not uploadedUrl then
            return nil, uploadReason
        end

        local normalizedUrl, reason = NormalizeHostedUrl(uploadedUrl, true)
        if not normalizedUrl then
            return nil, reason
        end

        preparedRemoteImages[imagePath] = normalizedUrl
        return normalizedUrl, nil
    end

    if config.allowDirectRemoteUrls then
        if not ValidateStoredRemoteImage(imagePath) then
            return nil, 'image_remote_unreachable'
        end

        return imagePath, nil
    end

    return nil, 'image_upload_not_configured'
end

local function ValidateImagePath(imagePath)
    local config = GetImageConfig()
    imagePath = Trim(imagePath)

    if imagePath == '' then
        return {
            ok = true,
            imagePath = '',
            sourceType = 'none'
        }
    end

    if imagePath:find('^https?://') then
        local preparedUrl, reason = PrepareRemoteImage(imagePath)
        if not preparedUrl then
            return {
                ok = false,
                reason = reason or 'image_validation_failed'
            }
        end

        return {
            ok = true,
            imagePath = preparedUrl,
            sourceType = 'remote'
        }
    end

    if not config.allowLocalFiles then
        return {
            ok = false,
            reason = 'image_local_disabled'
        }
    end

    imagePath = imagePath:gsub('^/+', '')
    if not imagePath:find('^ui/images/') then
        return {
            ok = false,
            reason = 'image_local_path_invalid'
        }
    end

    if config.requireImageExtension and not IsAllowedExtension(imagePath) then
        return {
            ok = false,
            reason = 'image_invalid_extension'
        }
    end

    if not LoadResourceFile(GetCurrentResourceName(), imagePath) then
        return {
            ok = false,
            reason = 'image_local_missing'
        }
    end

    return {
        ok = true,
        imagePath = imagePath,
        sourceType = 'local'
    }
end

local function CloneScene(scene)
    local clone = {}
    for key, value in pairs(scene or {}) do
        if type(value) == 'table' then
            local nested = {}
            for nestedKey, nestedValue in pairs(value) do
                nested[nestedKey] = nestedValue
            end
            clone[key] = nested
        else
            clone[key] = value
        end
    end

    return clone
end

local function BuildSceneLogLabel(scene)
    local label = Trim(scene.text)
    if label ~= '' then
        return label
    end

    label = Trim(scene.imagePath)
    if label ~= '' then
        return label
    end

    return 'Untitled scene'
end

local function BuildScenePayload(source, data, existingScene)
    data = data or {}
    existingScene = existingScene and CloneScene(existingScene) or {}

    local imageValidation = ValidateImagePath(data.imagePath or existingScene.imagePath)
    if not imageValidation.ok then
        return nil, imageValidation.reason
    end

    local text = Trim(data.text or existingScene.text)
    if text == '' and imageValidation.imagePath == '' then
        return nil, 'scene_content_required'
    end

    local coords = NormalizeCoords(data.coords or existingScene.coords)
    if not coords then
        return nil, 'scene_invalid_coords'
    end

    local ownerIdentifier = existingScene.ownerIdentifier
    if not ownerIdentifier and source and source > 0 then
        ownerIdentifier = GetIdentifier(source, 'license')
    end

    if source and source > 0 and not ownerIdentifier then
        return nil, 'failed'
    end

    local expiresAt, durationMinutes = BuildExpiresAt(data.durationMinutes ~= nil and data.durationMinutes or existingScene.durationMinutes)
    local font = Trim(data.font or existingScene.font or 'chalet_london')
    local textEffect = Trim(data.textEffect or existingScene.textEffect or 'outline')
    local textAnimation = Trim(data.textAnimation or existingScene.textAnimation or 'none')

    if font == '' then
        font = 'chalet_london'
    end

    if textEffect == '' then
        textEffect = 'outline'
    end

    if textAnimation == '' then
        textAnimation = 'none'
    end

    return {
        text = text,
        coords = coords,
        color = NormalizeColor(data.color or existingScene.color),
        distance = Clamp(data.distance or existingScene.distance or GetDefaultDistance(), 1.0, 20.0),
        imagePath = imageValidation.imagePath,
        imageScale = Clamp(data.imageScale or existingScene.imageScale or GetDefaultImageScale(), 0.5, 8.0),
        imageAspectRatio = Clamp(data.imageAspectRatio or existingScene.imageAspectRatio or 1.0, 0.2, 5.0),
        textScale = Clamp(data.textScale or existingScene.textScale or GetDefaultTextScale(), 0.2, 1.25),
        durationMinutes = durationMinutes,
        expiresAt = expiresAt,
        font = font,
        textEffect = textEffect,
        textAnimation = textAnimation,
        ownerIdentifier = ownerIdentifier,
        ownerName = Trim(existingScene.ownerName) ~= '' and existingScene.ownerName or ((source and source > 0) and (GetPlayerName(source) or 'Unknown') or 'Legacy Scene'),
        createdAt = existingScene.createdAt or os.time(),
        updatedAt = os.time(),
    }, nil
end

local function NormalizeLoadedScene(scene)
    local payload, reason = BuildScenePayload(0, scene, scene)
    if not payload then
        if reason == 'failed' or reason == 'scene_invalid_coords' or reason == 'scene_content_required' then
            return nil
        end

        payload = CloneScene(scene or {})
        payload.coords = NormalizeCoords(payload.coords)
        payload.color = NormalizeColor(payload.color)
        payload.distance = Clamp(payload.distance or GetDefaultDistance(), 1.0, 20.0)
        payload.imageScale = Clamp(payload.imageScale or GetDefaultImageScale(), 0.5, 8.0)
        payload.imageAspectRatio = Clamp(payload.imageAspectRatio or 1.0, 0.2, 5.0)
        payload.textScale = Clamp(payload.textScale or GetDefaultTextScale(), 0.2, 1.25)
        payload.durationMinutes = NormalizeDurationMinutes(payload.durationMinutes)
        payload.expiresAt = tonumber(payload.expiresAt) or nil
        payload.font = Trim(payload.font)
        if payload.font == '' then
            payload.font = 'chalet_london'
        end

        payload.textEffect = Trim(payload.textEffect)
        if payload.textEffect == '' then
            payload.textEffect = 'outline'
        end
        payload.textAnimation = Trim(payload.textAnimation)
        if payload.textAnimation == '' then
            payload.textAnimation = 'none'
        end
        payload.ownerIdentifier = type(payload.ownerIdentifier) == 'string' and payload.ownerIdentifier or nil
        payload.ownerName = Trim(payload.ownerName) ~= '' and payload.ownerName or 'Legacy Scene'
        payload.createdAt = payload.createdAt or os.time()
        payload.updatedAt = payload.updatedAt or payload.createdAt

        if not payload.coords then
            return nil
        end
    end

    if not payload.ownerIdentifier and type(scene.owner) == 'string' and scene.owner:find('license:') then
        payload.ownerIdentifier = scene.owner
    end

    if not payload.ownerName or payload.ownerName == '' then
        payload.ownerName = 'Legacy Scene'
    end

    if IsSceneExpired(payload) then
        return nil
    end

    return payload
end

local function RefreshScenes()
    PruneExpiredScenes()
    TriggerClientEvent('qb-scenes:client:refreshScenes', -1, scenes)
end

QBCore.Commands.Add('sceneban', Lang:t('commands.ban_description'), {
    name = 'player',
    description = Lang:t('commands.player_id')
}, false, function(source, args)
    local target = tonumber(args[1])
    if not target then
        return
    end

    local identifier = GetIdentifier(target, 'license')
    if not identifier then
        return
    end

    BanIdentifier(identifier)

    TriggerClientEvent('chat:addMessage', source, {
        args = { 'Scene Ban', Lang:t('chatMessages.banned') }
    })
end, 'admin')

lib.callback.register('qb-scenes:server:getScenes', function()
    PruneExpiredScenes()
    return scenes
end)

lib.callback.register('qb-scenes:server:getMediaProviders', function()
    return GetEnabledMediaProviders()
end)

lib.callback.register('qb-scenes:server:searchMedia', function(_, provider, query)
    provider = Trim(provider):lower()
    query = Trim(query)

    if provider == 'tenor' then
        local results, reason = SearchTenorMedia(query)
        if not results then
            return {
                ok = false,
                reason = reason or 'browser_search_failed',
                results = {},
            }
        end

        return {
            ok = true,
            results = results,
        }
    end

    return {
        ok = false,
        reason = 'browser_provider_unavailable',
        results = {},
    }
end)

lib.callback.register('qb-scenes:server:prepareImagePath', function(_, imagePath)
    return ValidateImagePath(imagePath)
end)

lib.callback.register('qb-scenes:server:newScene', function(source, data)
    local identifier = GetIdentifier(source, 'license')
    if not identifier then
        return { ok = false, reason = 'failed' }
    end

    if IsBanned(identifier) then
        return { ok = false, reason = 'scene_banned' }
    end

    local scene, reason = BuildScenePayload(source, data)
    if not scene then
        return { ok = false, reason = reason or 'failed' }
    end

    scenes[#scenes + 1] = scene
    RefreshScenes()

    TriggerEvent('qb-log:server:CreateLog', 'scenes', 'New Scene', 'green',
        ('**%s** (%s) created a new scene: **%s**'):format(GetPlayerName(source), source, BuildSceneLogLabel(scene)))

    return { ok = true }
end)

lib.callback.register('qb-scenes:server:updateScene', function(source, id, data)
    id = tonumber(id)
    local scene = scenes[id]
    if not scene then
        return { ok = false, reason = 'scene_missing' }
    end

    local identifier = GetIdentifier(source, 'license')
    if not identifier then
        return { ok = false, reason = 'failed' }
    end

    if IsBanned(identifier) then
        return { ok = false, reason = 'scene_banned' }
    end

    if not CanManageScene(source, scene) then
        return { ok = false, reason = 'scene_no_permission' }
    end

    local updatedScene, reason = BuildScenePayload(source, data, scene)
    if not updatedScene then
        return { ok = false, reason = reason or 'failed' }
    end

    scenes[id] = updatedScene
    RefreshScenes()

    TriggerEvent('qb-log:server:CreateLog', 'scenes', 'Updated Scene', 'blue',
        ('**%s** (%s) updated the scene: **%s**'):format(GetPlayerName(source), source, BuildSceneLogLabel(updatedScene)))

    return { ok = true }
end)

lib.callback.register('qb-scenes:server:destoryScene', function(source, id)
    id = tonumber(id)
    local scene = scenes[id]
    if not scene then
        return { ok = false, reason = 'scene_missing' }
    end

    local identifier = GetIdentifier(source, 'license')
    if not identifier then
        return { ok = false, reason = 'failed' }
    end

    if IsBanned(identifier) then
        return { ok = false, reason = 'scene_banned' }
    end

    if not CanManageScene(source, scene) then
        return { ok = false, reason = 'scene_no_permission' }
    end

    TriggerEvent('qb-log:server:CreateLog', 'scenes', 'Removed Scene', 'red',
        ('**%s** (%s) removed the scene: **%s** owned by **%s**'):format(
            GetPlayerName(source),
            source,
            BuildSceneLogLabel(scene),
            scene.ownerName or 'Unknown'
        )
    )

    table.remove(scenes, id)
    RefreshScenes()
    return { ok = true }
end)

RegisterNetEvent('djonstnix-scenes:server:LoadScenes', function()
    local reqScenes = GetSavedScenes()

    scenes = {}
    for _, scene in pairs(reqScenes) do
        local normalized = NormalizeLoadedScene(scene)
        if normalized then
            scenes[#scenes + 1] = normalized
        end
    end

    RefreshScenes()
end)

CreateThread(function()
    while true do
        Wait(60000)

        if PruneExpiredScenes() then
            RefreshScenes()
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end

    SaveScenes(scenes)
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end

    TriggerEvent('djonstnix-scenes:server:LoadScenes')
end)
