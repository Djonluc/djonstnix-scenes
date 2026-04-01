const previewRoot = document.getElementById('preview-root');
const previewImage = document.getElementById('preview-image');
const browserRoot = document.getElementById('browser-root');
const browserTitle = document.getElementById('browser-title');
const browserSubtitle = document.getElementById('browser-subtitle');
const browserTabs = document.getElementById('browser-tabs');
const browserStatus = document.getElementById('browser-status');
const browserGrid = document.getElementById('browser-grid');
const browserForm = document.getElementById('browser-search-form');
const browserQuery = document.getElementById('browser-query');
const browserSubmit = document.getElementById('browser-submit');
const browserClose = document.getElementById('browser-close');

let activePreviewRequestId = 0;
let activeBrowserProvider = '';
let browserProviders = [];
let browserStrings = {
    title: 'Scene Media Browser',
    subtitle: 'Search hosted GIFs and bring them straight into scene creation.',
    search_placeholder: 'Search for a GIF or image idea...',
    search_button: 'Search',
    empty: 'Search to load media results.',
    searching: 'Searching...',
    no_results: 'No results found for that search.',
    close: 'Close',
};

previewImage.referrerPolicy = 'no-referrer';
previewImage.decoding = 'async';
previewImage.fetchPriority = 'high';

function postJson(callbackName, payload) {
    return fetch(`https://${GetParentResourceName()}/${callbackName}`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json; charset=UTF-8',
        },
        body: JSON.stringify(payload || {}),
    })
        .then((response) => response.json())
        .catch(() => ({ ok: false }));
}

function hidePreview() {
    previewRoot.classList.add('hidden');
    previewRoot.setAttribute('aria-hidden', 'true');
    activePreviewRequestId += 1;
    previewImage.onload = null;
    previewImage.onerror = null;
    previewImage.removeAttribute('src');
}

function setBrowserStatus(message, state) {
    browserStatus.textContent = message || '';
    browserStatus.className = 'browser-status';

    if (state === 'error') {
        browserStatus.classList.add('state-error');
    }
}

function closeBrowserUi() {
    document.body.classList.remove('browser-open');
    browserRoot.classList.add('hidden');
    browserRoot.setAttribute('aria-hidden', 'true');
    browserGrid.innerHTML = '';
    browserTabs.innerHTML = '';
    browserQuery.value = '';
    activeBrowserProvider = '';
    browserProviders = [];
    setBrowserStatus('', '');
}

function renderBrowserTabs() {
    browserTabs.innerHTML = '';

    browserProviders.forEach((provider) => {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = `browser-tab${provider.id === activeBrowserProvider ? ' active' : ''}`;
        button.textContent = provider.label || provider.id;
        button.addEventListener('click', () => {
            activeBrowserProvider = provider.id;
            renderBrowserTabs();
        });
        browserTabs.appendChild(button);
    });
}

function renderBrowserResults(results) {
    browserGrid.innerHTML = '';

    results.forEach((result) => {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'browser-card';

        const image = document.createElement('img');
        image.alt = result.title || result.provider || 'Media result';
        image.loading = 'lazy';
        image.referrerPolicy = 'no-referrer';
        image.src = result.previewUrl || result.url;

        const title = document.createElement('strong');
        title.textContent = result.title || 'Untitled result';

        const meta = document.createElement('span');
        meta.textContent = `${result.provider || 'media'}${result.width > 0 && result.height > 0 ? ` | ${result.width}x${result.height}` : ''}`;

        button.appendChild(image);
        button.appendChild(title);
        button.appendChild(meta);

        button.addEventListener('click', async () => {
            await postJson('sceneMediaSelect', result);
            closeBrowserUi();
        });

        browserGrid.appendChild(button);
    });
}

function applyBrowserStrings(strings) {
    browserStrings = {
        ...browserStrings,
        ...(strings || {}),
    };

    browserTitle.textContent = browserStrings.title;
    browserSubtitle.textContent = browserStrings.subtitle;
    browserQuery.placeholder = browserStrings.search_placeholder;
    browserSubmit.textContent = browserStrings.search_button;
    browserClose.textContent = browserStrings.close;
}

function openBrowser(data) {
    browserProviders = Array.isArray(data.providers) ? data.providers : [];
    activeBrowserProvider = browserProviders.some((provider) => provider.id === data.defaultProvider)
        ? data.defaultProvider
        : (browserProviders[0] && browserProviders[0].id) || '';

    applyBrowserStrings(data.strings || {});
    renderBrowserTabs();
    browserGrid.innerHTML = '';
    setBrowserStatus(browserStrings.empty, '');
    browserRoot.classList.remove('hidden');
    browserRoot.setAttribute('aria-hidden', 'false');
    document.body.classList.add('browser-open');

    window.setTimeout(() => {
        browserQuery.focus();
        browserQuery.select();
    }, 0);
}

async function performBrowserSearch() {
    const query = browserQuery.value.trim();

    if (!activeBrowserProvider) {
        setBrowserStatus(browserStrings.no_results, 'error');
        return;
    }

    if (!query) {
        browserGrid.innerHTML = '';
        setBrowserStatus(browserStrings.empty, '');
        return;
    }

    browserGrid.innerHTML = '';
    setBrowserStatus(browserStrings.searching, '');

    const response = await postJson('sceneMediaSearch', {
        provider: activeBrowserProvider,
        query,
    });

    if (!response || response.ok !== true) {
        setBrowserStatus(browserStrings.no_results, 'error');
        return;
    }

    const results = Array.isArray(response.results) ? response.results : [];
    if (results.length === 0) {
        setBrowserStatus(browserStrings.no_results, '');
        return;
    }

    setBrowserStatus('', '');
    renderBrowserResults(results);
}

browserForm.addEventListener('submit', (event) => {
    event.preventDefault();
    performBrowserSearch();
});

browserClose.addEventListener('click', async () => {
    await postJson('sceneMediaClose', {});
    closeBrowserUi();
});

window.addEventListener('keydown', async (event) => {
    if (event.key === 'Escape' && !browserRoot.classList.contains('hidden')) {
        event.preventDefault();
        await postJson('sceneMediaClose', {});
        closeBrowserUi();
    }
});

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || !data.action) {
        return;
    }

    if (data.action === 'hidePreview') {
        hidePreview();
        return;
    }

    if (data.action === 'openBrowser') {
        openBrowser(data);
        return;
    }

    if (data.action === 'closeBrowser') {
        closeBrowserUi();
        return;
    }

    if (data.action !== 'showPreview' || !data.src) {
        return;
    }

    activePreviewRequestId = Number(data.requestId) || (activePreviewRequestId + 1);
    const requestId = activePreviewRequestId;

    previewRoot.classList.remove('hidden');
    previewRoot.setAttribute('aria-hidden', 'false');
    previewImage.onload = null;
    previewImage.onerror = null;
    previewImage.removeAttribute('src');

    previewImage.onload = () => {
        if (requestId !== activePreviewRequestId) {
            return;
        }

        const width = previewImage.naturalWidth || 0;
        const height = previewImage.naturalHeight || 0;

        postJson('scenePreviewStatus', {
            source: data.src,
            requestId,
            loaded: true,
            width,
            height,
        });
    };

    previewImage.onerror = () => {
        if (requestId !== activePreviewRequestId) {
            return;
        }

        postJson('scenePreviewStatus', {
            source: data.src,
            requestId,
            loaded: false,
        });
    };

    previewImage.src = data.src;
});
