local import = require('server.json')
local BanIdentifier, IsBanned, SaveScenes, GetSavedScenes = import[1], import[2], import[3], import[4]

local scenes = {}
local preparedRemoteImages = {}
local persistQueued = false
local persistDirty = false
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

local GetExtensionFromContentType

local function NormalizeContentType(contentType)
    contentType = Trim(contentType)
    if contentType == '' then
        return nil
    end

    return (contentType:match('^[^;]+') or contentType):lower()
end

local function GetMediaKindFromExtension(extension)
    extension = Trim(extension):lower()

    if extension == 'mp4' or extension == 'webm' then
        return 'video'
    end

    return 'image'
end

local function GetMediaKindFromContentType(contentType)
    contentType = NormalizeContentType(contentType)
    if not contentType then
        return 'image'
    end

    if contentType == 'video/mp4' or contentType == 'video/webm' then
        return 'video'
    end

    return 'image'
end

local function BuildMediaMetadata(path, contentTypeOrExtension)
    local normalizedContentType = NormalizeContentType(contentTypeOrExtension)
    local normalizedExtension = nil

    if normalizedContentType and normalizedContentType:find('/', 1, true) == nil then
        normalizedExtension = normalizedContentType
        normalizedContentType = nil
    end

    local extension = normalizedContentType and GetExtensionFromContentType(normalizedContentType) or Trim(normalizedExtension or GetPathExtension(path) or ''):lower()
    local mediaKind = normalizedContentType and GetMediaKindFromContentType(normalizedContentType) or GetMediaKindFromExtension(extension)

    if extension == '' then
        extension = mediaKind == 'video' and 'mp4' or 'png'
    end

    return {
        mediaKind = mediaKind,
        mediaExtension = extension,
        mediaAnimated = mediaKind == 'video' or extension == 'gif',
    }
end

GetExtensionFromContentType = function(contentType)
    contentType = NormalizeContentType(contentType)
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
        ['video/mp4'] = 'mp4',
        ['video/webm'] = 'webm',
    }

    return extensions[contentType] or 'png'
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

local function IsSupportedMediaContentType(contentType)
    contentType = NormalizeContentType(contentType)
    if not contentType then
        return false
    end

    if contentType:find('image/', 1, true) ~= nil then
        return true
    end

    return contentType == 'video/mp4' or contentType == 'video/webm'
end

local function IsAnimatedMediaMetadata(mediaMeta)
    return type(mediaMeta) == 'table' and mediaMeta.mediaAnimated == true
end

local function ParseContentLength(headers)
    local contentLength = tonumber(GetHeader(headers, 'content-length'))
    if contentLength and contentLength > 0 then
        return contentLength
    end

    return nil
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

local function BuildMediaResult(provider, id, title, mediaUrl, previewUrl, width, height, mediaMeta, previewMeta)
    mediaUrl = Trim(mediaUrl)
    previewUrl = Trim(previewUrl)

    if mediaUrl == '' then
        return nil
    end

    mediaMeta = mediaMeta or BuildMediaMetadata(mediaUrl)
    previewMeta = previewMeta or BuildMediaMetadata(previewUrl ~= '' and previewUrl or mediaUrl)

    return {
        provider = provider,
        id = Trim(id),
        title = Trim(title),
        url = mediaUrl,
        previewUrl = previewUrl ~= '' and previewUrl or mediaUrl,
        width = tonumber(width) or 0,
        height = tonumber(height) or 0,
        mediaKind = mediaMeta.mediaKind,
        mediaExtension = mediaMeta.mediaExtension,
        mediaAnimated = mediaMeta.mediaAnimated,
        previewKind = previewMeta.mediaKind,
    }
end

local function SelectMediaFormat(mediaFormats, preferredKeys)
    for _, key in ipairs(preferredKeys or {}) do
        local candidate = mediaFormats[key]
        if type(candidate) == 'table' and Trim(candidate.url) ~= '' then
            return key, candidate
        end
    end

    return nil, nil
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
        local primaryKey, primary = SelectMediaFormat(mediaFormats, {
            'mp4',
            'tinymp4',
            'nanomp4',
            'webm',
            'tinywebm',
            'nanowebm',
            'gif',
            'mediumgif',
            'tinygif',
            'nanogif',
            'webp',
            'gifpreview',
        })
        local previewKey, preview = SelectMediaFormat(mediaFormats, {
            'gifpreview',
            'tinygif',
            'nanogif',
            'mediumgif',
            'gif',
            'webp',
            primaryKey,
        })

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
            dims[2],
            BuildMediaMetadata(type(primary) == 'table' and primary.url or '', primaryKey),
            BuildMediaMetadata(type(preview) == 'table' and preview.url or '', previewKey)
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
    local removedIds = {}

    for uid, scene in pairs(scenes) do
        if IsSceneExpired(scene) then
            scenes[uid] = nil
            removedIds[#removedIds + 1] = uid
        end
    end

    return removedIds
end

local function QueueScenePersist()
    persistDirty = true
    if persistQueued then
        return
    end

    persistQueued = true
    CreateThread(function()
        Wait(750)
        persistQueued = false

        if not persistDirty then
            return
        end

        persistDirty = false
        SaveScenes(scenes)
    end)
end

local function PersistScenesNow()
    persistDirty = false
    persistQueued = false
    SaveScenes(scenes)
end

local function BroadcastSceneSet(target)
    TriggerClientEvent('qb-scenes:client:setScenes', target or -1, scenes)
end

local function BroadcastSceneUpsert(scene, target)
    TriggerClientEvent('qb-scenes:client:upsertScene', target or -1, scene)
end

local function BroadcastSceneRemove(sceneIds, target)
    if not sceneIds or #sceneIds == 0 then
        return
    end

    TriggerClientEvent('qb-scenes:client:removeScenes', target or -1, sceneIds)
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
        return true, BuildMediaMetadata(url), nil
    end

    local headResponse = PerformHttpRequestAwait(url, 'HEAD', '', {
        ['Accept'] = 'image/*,video/mp4,video/webm,*/*;q=0.8',
        ['User-Agent'] = 'djonstnix-scenes/1.0',
    })

    local headContentType = GetHeader(headResponse.headers, 'content-type')
    local headOk = headResponse.statusCode and headResponse.statusCode >= 200 and headResponse.statusCode < 400 and IsSupportedMediaContentType(headContentType)
    if headOk then
        return true, BuildMediaMetadata(url, headContentType), ParseContentLength(headResponse.headers)
    end

    local response = PerformHttpRequestAwait(url, 'GET', '', {
        ['Accept'] = 'image/*,video/mp4,video/webm,*/*;q=0.8',
        ['User-Agent'] = 'djonstnix-scenes/1.0',
        ['Range'] = 'bytes=0-1024',
    })

    local contentType = GetHeader(response.headers, 'content-type')
    local ok = response.statusCode and response.statusCode >= 200 and response.statusCode < 400 and IsSupportedMediaContentType(contentType)
    if ok then
        return true, BuildMediaMetadata(url, contentType), ParseContentLength(response.headers)
    end

    response = PerformHttpRequestAwait(url, 'GET', '', {
        ['Accept'] = 'image/*,video/mp4,video/webm,*/*;q=0.8',
        ['User-Agent'] = 'djonstnix-scenes/1.0',
    })

    contentType = GetHeader(response.headers, 'content-type')
    ok = response.statusCode and response.statusCode >= 200 and response.statusCode < 400 and IsSupportedMediaContentType(contentType)
    return ok, ok and BuildMediaMetadata(url, contentType) or nil, ok and ParseContentLength(response.headers) or nil
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
        ['Accept'] = 'image/*,video/mp4,video/webm,*/*;q=0.8',
        ['User-Agent'] = 'djonstnix-scenes/1.0',
    })

    if not response.statusCode or response.statusCode < 200 or response.statusCode >= 300 then
        return nil, 'image_remote_unreachable'
    end

    local contentType = GetHeader(response.headers, 'content-type')
    if not IsSupportedMediaContentType(contentType) then
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
    local uploadedUrl, reason = UploadImageDataToFivemanage(dataUri, filename)
    if not uploadedUrl then
        return nil, reason
    end

    return uploadedUrl, nil, BuildMediaMetadata(uploadedUrl, contentType)
end

local function NormalizeHostedUrl(imageUrl, skipValidation)
    local host = GetUrlHost(imageUrl)
    if not host or not IsAllowedHost(host) then
        return nil, 'image_not_allowed_host'
    end

    if not skipValidation then
        local ok, mediaMeta = ValidateStoredRemoteImage(imageUrl)
        if not ok then
            return nil, 'image_remote_unreachable'
        end

        return imageUrl, nil, mediaMeta
    end

    return imageUrl, nil, BuildMediaMetadata(imageUrl)
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

    if IsAllowedHost(host) then
        return NormalizeHostedUrl(imagePath)
    end

    local remoteOk, remoteMediaMeta, remoteContentLength = ValidateStoredRemoteImage(imagePath)
    if not remoteOk then
        return nil, 'image_remote_unreachable'
    end

    local maxMirrorFileSize = math.min(tonumber(config.maxRemoteFileSize) or (8 * 1024 * 1024), 16 * 1024 * 1024)
    local shouldUseDirectRemote = config.allowDirectRemoteUrls
        or IsAnimatedMediaMetadata(remoteMediaMeta)
        or (remoteContentLength and remoteContentLength > maxMirrorFileSize)

    if shouldUseDirectRemote then
        return imagePath, nil, remoteMediaMeta
    end

    if config.mirrorExternalUrlsToFivemanage then
        local cachedUrl = preparedRemoteImages[imagePath]
        if cachedUrl then
            return NormalizeHostedUrl(cachedUrl, true)
        end

        local uploadedUrl, uploadReason, mediaMeta = RehostRemoteImage(imagePath)
        if not uploadedUrl then
            return nil, uploadReason
        end

        local normalizedUrl, reason = NormalizeHostedUrl(uploadedUrl, true)
        if not normalizedUrl then
            return nil, reason
        end

        preparedRemoteImages[imagePath] = normalizedUrl
        return normalizedUrl, nil, mediaMeta or BuildMediaMetadata(normalizedUrl)
    end

    if config.allowDirectRemoteUrls then
        return imagePath, nil, remoteMediaMeta or BuildMediaMetadata(imagePath)
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
            sourceType = 'none',
            mediaKind = 'image',
            mediaExtension = '',
            mediaAnimated = false,
        }
    end

    if imagePath:find('^https?://') then
        local preparedUrl, reason, mediaMeta = PrepareRemoteImage(imagePath)
        if not preparedUrl then
            return {
                ok = false,
                reason = reason or 'image_validation_failed'
            }
        end

        return {
            ok = true,
            imagePath = preparedUrl,
            sourceType = 'remote',
            mediaKind = mediaMeta and mediaMeta.mediaKind or GetMediaKindFromExtension(GetPathExtension(preparedUrl) or ''),
            mediaExtension = mediaMeta and mediaMeta.mediaExtension or Trim(GetPathExtension(preparedUrl) or ''):lower(),
            mediaAnimated = mediaMeta and mediaMeta.mediaAnimated == true or false,
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
        sourceType = 'local',
        mediaKind = GetMediaKindFromExtension(GetPathExtension(imagePath) or ''),
        mediaExtension = Trim(GetPathExtension(imagePath) or ''):lower(),
        mediaAnimated = Trim(GetPathExtension(imagePath) or ''):lower() == 'gif',
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

    local uid = existingScene.id
    if not uid then
        uid = ('scn_%d%d'):format(os.time(), math.random(1000, 9999))
    end

    return {
        id = uid, -- Stable UID
        text = text,
        coords = coords,
        color = NormalizeColor(data.color or existingScene.color),
        distance = Clamp(data.distance or existingScene.distance or GetDefaultDistance(), 1.0, 20.0),
        imagePath = imageValidation.imagePath,
        mediaKind = imageValidation.imagePath ~= '' and (imageValidation.mediaKind or existingScene.mediaKind or 'image') or 'image',
        mediaExtension = imageValidation.imagePath ~= '' and (imageValidation.mediaExtension or existingScene.mediaExtension or '') or '',
        mediaAnimated = imageValidation.imagePath ~= '' and (imageValidation.mediaAnimated == true) or false,
        imageScale = Clamp(data.imageScale or existingScene.imageScale or GetDefaultImageScale(), 0.1, 20.0),
        imageWidth = tonumber(data.imageWidth or existingScene.imageWidth) or 1024,
        imageHeight = tonumber(data.imageHeight or existingScene.imageHeight) or 1024,
        imageAspectRatio = Clamp(data.imageAspectRatio or existingScene.imageAspectRatio or 1.0, 0.2, 5.0),
        textScale = Clamp(data.textScale or existingScene.textScale or GetDefaultTextScale(), 0.2, 1.25),
        rotation = {
            x = tonumber(data.rotation and data.rotation.x or existingScene.rotation and existingScene.rotation.x) or 0.0,
            y = tonumber(data.rotation and data.rotation.y or existingScene.rotation and existingScene.rotation.y) or 0.0,
            z = tonumber(data.rotation and data.rotation.z or existingScene.rotation and existingScene.rotation.z) or 0.0,
        },
        faceCamera = (data.faceCamera ~= nil and data.faceCamera) or (data.faceCamera == nil and existingScene.faceCamera == true),
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
        payload.imageScale = Clamp(payload.imageScale or GetDefaultImageScale(), 0.1, 20.0)
        payload.mediaKind = Trim(payload.mediaKind) ~= '' and Trim(payload.mediaKind) or BuildMediaMetadata(payload.imagePath).mediaKind
        payload.mediaExtension = Trim(payload.mediaExtension) ~= '' and Trim(payload.mediaExtension):lower() or BuildMediaMetadata(payload.imagePath).mediaExtension
        payload.mediaAnimated = payload.mediaAnimated == true or BuildMediaMetadata(payload.imagePath).mediaAnimated
        payload.imageWidth = tonumber(payload.imageWidth) or 1024
        payload.imageHeight = tonumber(payload.imageHeight) or 1024
        payload.imageAspectRatio = Clamp(payload.imageAspectRatio or 1.0, 0.2, 5.0)
        payload.textScale = Clamp(payload.textScale or GetDefaultTextScale(), 0.2, 1.25)
        payload.rotation = type(payload.rotation) == 'table' and {
            x = tonumber(payload.rotation.x or payload.rotation[1]) or 0.0,
            y = tonumber(payload.rotation.y or payload.rotation[2]) or 0.0,
            z = tonumber(payload.rotation.z or payload.rotation[3]) or 0.0,
        } or { x = 0.0, y = 0.0, z = 0.0 }
        payload.faceCamera = payload.faceCamera ~= false
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

QBCore.Commands.Add('cleanscenes', Lang:t('commands.cleanup_description'), {
    { name = 'radius', help = Lang:t('commands.cleanup_radius') }
}, false, function(source, args)
    local radius = tonumber(args[1]) or 5.0
    local coords = GetEntityCoords(GetPlayerPed(source))
    local removedCount = 0
    local removedIds = {}

    for uid, scene in pairs(scenes) do
        local dist = #(coords - vec3(scene.coords.x, scene.coords.y, scene.coords.z))
        if dist <= radius then
            scenes[uid] = nil
            removedCount = removedCount + 1
            removedIds[#removedIds + 1] = uid
        end
    end

    if removedCount > 0 then
        QueueScenePersist()
        BroadcastSceneRemove(removedIds)
        TriggerClientEvent('QBCore:Notify', source, Lang:t('notify.cleaned_area'):format(removedCount), 'success')
        TriggerEvent('qb-log:server:CreateLog', 'scenes', 'Mass Cleanup', 'red',
            ('**%s** (%s) cleared **%d** scenes in a %.1fm radius'):format(GetPlayerName(source), source, removedCount, radius))
    else
        TriggerClientEvent('QBCore:Notify', source, Lang:t('notify.scene_nearby'), 'error')
    end
end, 'admin')

lib.callback.register('qb-scenes:server:hasAdminPermission', function(source)
    return HasAdminPermission(source)
end)

lib.callback.register('qb-scenes:server:getScenes', function()
    local removedIds = PruneExpiredScenes()
    if #removedIds > 0 then
        QueueScenePersist()
        BroadcastSceneRemove(removedIds)
    end

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
    if not scene or not scene.id then
        return { ok = false, reason = reason or 'failed' }
    end

    scenes[scene.id] = scene
    QueueScenePersist()
    BroadcastSceneUpsert(scene)

    TriggerEvent('qb-log:server:CreateLog', 'scenes', 'New Scene', 'green',
        ('**%s** (%s) created a new scene (ID: %s): **%s**'):format(GetPlayerName(source), source, scene.id, BuildSceneLogLabel(scene)))

    return { ok = true }
end)

lib.callback.register('qb-scenes:server:updateScene', function(source, id, data)
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
    QueueScenePersist()
    BroadcastSceneUpsert(updatedScene)

    TriggerEvent('qb-log:server:CreateLog', 'scenes', 'Updated Scene', 'blue',
        ('**%s** (%s) updated the scene: **%s**'):format(GetPlayerName(source), source, BuildSceneLogLabel(updatedScene)))

    return { ok = true }
end)

lib.callback.register('qb-scenes:server:destroyScene', function(source, id)
    local scene = scenes[id]
    if not scene then
        return { ok = false, reason = 'scene_missing' }
    end

    if not CanManageScene(source, scene) then
        return { ok = false, reason = 'scene_no_permission' }
    end

    scenes[id] = nil
    QueueScenePersist()
    BroadcastSceneRemove({ id })

    TriggerEvent('qb-log:server:CreateLog', 'scenes', 'Destroy Scene', 'orange',
        ('**%s** (%s) destroyed the scene (ID: %s): **%s**'):format(GetPlayerName(source), source, id, BuildSceneLogLabel(scene)))

    return { ok = true }
end)

lib.callback.register('qb-scenes:server:clearArea', function(source, radius)
    if not HasAdminPermission(source) then
        return { ok = false, reason = 'scene_no_permission' }
    end

    radius = tonumber(radius) or 5.0
    local coords = GetEntityCoords(GetPlayerPed(source))
    local removedCount = 0
    local removedIds = {}

    for uid, scene in pairs(scenes) do
        local dist = #(coords - vec3(scene.coords.x, scene.coords.y, scene.coords.z))
        if dist <= radius then
            scenes[uid] = nil
            removedCount = removedCount + 1
            removedIds[#removedIds + 1] = uid
        end
    end

    if removedCount > 0 then
        QueueScenePersist()
        BroadcastSceneRemove(removedIds)
        TriggerEvent('qb-log:server:CreateLog', 'scenes', 'Mass Cleanup', 'red',
            ('**%s** (%s) cleared **%d** scenes in a %.1fm radius'):format(GetPlayerName(source), source, removedCount, radius))
        return { ok = true, count = removedCount }
    end

    return { ok = false, reason = 'scene_nearby' }
end)

lib.callback.register('qb-scenes:server:updateSceneDimensions', function(source, id, width, height)
    local scene = scenes[id]
    if not scene then
        return false
    end

    if not CanManageScene(source, scene) then
        return false
    end

    local safeWidth = math.floor(Clamp(width, 1, 16384))
    local safeHeight = math.floor(Clamp(height, 1, 16384))

    print(('^5[DjonStNix Scenes]^7 Migrating legacy dimensions for ID: %s (%dx%d)'):format(id, safeWidth, safeHeight))
    scene.imageWidth = safeWidth
    scene.imageHeight = safeHeight
    scene.imageAspectRatio = scene.imageWidth / scene.imageHeight

    QueueScenePersist()
    BroadcastSceneUpsert(scene)
    return true
end)

RegisterNetEvent('djonstnix-scenes:server:LoadScenes', function()
    local reqScenes = GetSavedScenes()

    scenes = {}
    for _, scene in pairs(reqScenes) do
        local normalized = NormalizeLoadedScene(scene)
        if normalized and normalized.id then
            scenes[normalized.id] = normalized
        end
    end

    BroadcastSceneSet()
end)

CreateThread(function()
    while true do
        Wait(60000)

        local removedIds = PruneExpiredScenes()
        if #removedIds > 0 then
            QueueScenePersist()
            BroadcastSceneRemove(removedIds)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end

    PersistScenesNow()
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end

    TriggerEvent('djonstnix-scenes:server:LoadScenes')
end)
