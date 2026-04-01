Config = Config or {}

Config.SceneImages = {
    allowLocalFiles = true,
    requireHttps = true,
    requireImageExtension = true,
    validateStoredRemoteImages = true,
    previewTimeoutMs = 30000,
    previewRetryCount = 2,
    maxRemoteFileSize = 8 * 1024 * 1024,
    allowDirectRemoteUrls = false,
    disableAutoScale = false,
    mirrorExternalUrlsToFivemanage = true,
    fivemanageBase64ApiUrl = 'https://api.fivemanage.com/api/v3/file/base64',
    defaultImageScale = 2.5,
    defaultTextScale = 0.48,
    defaultDistance = 7.5,
    imagePreloadDistance = 40.0,
    allowedStoredHosts = {
        'r2.fivemanage.com',
        '*.fivemanage.com',
        'i.fmfile.com',
        '*.fmfile.com'
    },
    allowedExtensions = {
        png = true,
        jpg = true,
        jpeg = true,
        webp = true,
        gif = true,
    }
}

Config.ScenePermissions = {
    adminGroups = {
        'god',
        'admin',
    }
}

Config.SceneUI = {
    menuTitle = 'DjonStNix Scenes',
    keybindCommand = 'scene_menu',
    keybindDescription = 'Open the DjonStNix scenes menu',
    defaultKey = 'F7',
    accentColor = '#c5a059',
}

Config.SceneMedia = {
    defaultProvider = 'tenor',
    providers = {
        tenor = {
            enabled = true,
            label = 'Tenor',
            apiBaseUrl = 'https://tenor.googleapis.com/v2',
            clientKey = 'djonstnix-scenes',
            limit = 18,
            mediaFilter = 'gif,tinygif,mediumgif',
            contentFilter = 'medium',
        }
    }
}
