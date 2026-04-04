const params = new URLSearchParams(window.location.search);
const src = params.get('src');
const kind = params.get('kind');
const image = document.getElementById('scene-image');
const canvas = document.getElementById('scene-canvas');
const video = document.getElementById('scene-video');
const VIDEO_KEEPALIVE_MS = 1000;

let gifPlaybackTimer = null;
let gifFrames = [];
let gifFrameIndex = 0;
let gifPlaybackNonce = 0;
let gifCanvasWidth = 0;
let gifCanvasHeight = 0;

let videoKeepaliveTimer = null;
let lastVideoTime = -1;
let stalledVideoTicks = 0;
let pendingVideoResumeAt = 0;
let activeVideoSource = '';

const canvasContext = canvas.getContext('2d', { alpha: true });
const gifFrameCanvas = document.createElement('canvas');
const gifFrameContext = gifFrameCanvas.getContext('2d', { alpha: true });

function isVideoSource(value, explicitKind) {
    if ((explicitKind || '').toLowerCase() === 'video') {
        return true;
    }

    return /\.(mp4|webm)(?:$|[?#])/i.test(value || '');
}

function isGifSource(value) {
    return /\.gif(?:$|[?#])/i.test(value || '');
}

function applyImageOptions(element) {
    element.referrerPolicy = 'no-referrer';
    element.loading = 'eager';
    element.decoding = 'sync';
    element.crossOrigin = 'anonymous';
    element.draggable = false;
}

function clearVideoKeepalive() {
    if (videoKeepaliveTimer) {
        window.clearInterval(videoKeepaliveTimer);
        videoKeepaliveTimer = null;
    }
}

function clearGifPlayback() {
    gifPlaybackNonce += 1;

    if (gifPlaybackTimer) {
        window.clearTimeout(gifPlaybackTimer);
        gifPlaybackTimer = null;
    }

    gifFrames = [];
    gifFrameIndex = 0;
    gifCanvasWidth = 0;
    gifCanvasHeight = 0;

    if (gifFrameContext) {
        gifFrameContext.clearRect(0, 0, gifFrameCanvas.width || 0, gifFrameCanvas.height || 0);
    }

    if (canvasContext) {
        canvasContext.clearRect(0, 0, canvas.width || 0, canvas.height || 0);
    }
}

function clearMediaState() {
    clearGifPlayback();
    clearVideoKeepalive();
    lastVideoTime = -1;
    stalledVideoTicks = 0;
    pendingVideoResumeAt = 0;
    activeVideoSource = '';
    image.classList.remove('hidden');
    canvas.classList.add('hidden');
    video.classList.add('hidden');
    image.removeAttribute('src');
    image.onload = null;
    image.onerror = null;
    video.pause();
    video.removeAttribute('src');
    video.load();
}

function resizeCanvas() {
    const width = Math.max(1, window.innerWidth || 1);
    const height = Math.max(1, window.innerHeight || 1);

    if (canvas.width !== width || canvas.height !== height) {
        canvas.width = width;
        canvas.height = height;
    }
}

function loadBinarySource(source) {
    return new Promise((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        xhr.open('GET', source, true);
        xhr.responseType = 'arraybuffer';

        xhr.onload = () => {
            if (xhr.status >= 200 && xhr.status < 400 && xhr.response) {
                resolve(xhr.response);
                return;
            }

            reject(new Error(`Binary load failed: ${xhr.status}`));
        };

        xhr.onerror = () => {
            reject(new Error('Binary load failed'));
        };

        xhr.send();
    });
}

function renderGifFrame(frame) {
    if (!frame || !canvasContext || canvas.classList.contains('hidden')) {
        return;
    }

    resizeCanvas();

    if (gifFrameCanvas.width !== gifCanvasWidth || gifFrameCanvas.height !== gifCanvasHeight) {
        gifFrameCanvas.width = gifCanvasWidth;
        gifFrameCanvas.height = gifCanvasHeight;
    }

    gifFrameContext.putImageData(frame.imageData, 0, 0);
    canvasContext.clearRect(0, 0, canvas.width, canvas.height);
    canvasContext.drawImage(gifFrameCanvas, 0, 0, canvas.width, canvas.height);
}

function scheduleGifPlayback(nonce) {
    if (nonce !== gifPlaybackNonce || gifFrames.length === 0) {
        return;
    }

    const frame = gifFrames[gifFrameIndex];
    renderGifFrame(frame);

    gifFrameIndex = (gifFrameIndex + 1) % gifFrames.length;
    gifPlaybackTimer = window.setTimeout(() => {
        scheduleGifPlayback(nonce);
    }, Math.max(20, frame.delayMs || 100));
}

async function mountGif(source) {
    clearGifPlayback();
    video.classList.add('hidden');
    image.classList.add('hidden');
    canvas.classList.remove('hidden');

    const nonce = gifPlaybackNonce;

    try {
        const buffer = await loadBinarySource(source);
        if (nonce !== gifPlaybackNonce) {
            return;
        }

        const animation = window.GifDecoder && window.GifDecoder.parse
            ? window.GifDecoder.parse(buffer)
            : null;

        if (!animation || !animation.frames || animation.frames.length === 0) {
            throw new Error('GIF decode failed');
        }

        gifCanvasWidth = animation.width;
        gifCanvasHeight = animation.height;
        gifFrames = animation.frames.map((frame) => ({
            delayMs: frame.delayMs,
            imageData: new ImageData(frame.pixels, animation.width, animation.height),
        }));

        scheduleGifPlayback(nonce);
    } catch (_) {
        canvas.classList.add('hidden');
        image.classList.remove('hidden');
        requestAnimationFrame(() => {
            image.src = source;
        });
    }
}

function reloadVideoSource() {
    if (!activeVideoSource) {
        return;
    }

    const resumeAt = Number(video.currentTime || pendingVideoResumeAt || 0);
    pendingVideoResumeAt = resumeAt > 0.05 ? resumeAt : 0;
    lastVideoTime = -1;
    stalledVideoTicks = 0;

    video.pause();
    video.src = activeVideoSource;
    video.load();
}

function ensureVideoPlayback() {
    if (!activeVideoSource || video.classList.contains('hidden')) {
        return;
    }

    if (video.ended) {
        try {
            video.currentTime = 0;
        } catch (_) {}
    }

    const currentTime = Number(video.currentTime || 0);
    if (!video.paused && currentTime === lastVideoTime) {
        stalledVideoTicks += 1;
    } else {
        stalledVideoTicks = 0;
    }

    lastVideoTime = currentTime;

    if (stalledVideoTicks >= 3) {
        reloadVideoSource();
        return;
    }

    video.play().catch(() => {});
}

function applyPendingVideoResume() {
    if (pendingVideoResumeAt <= 0) {
        return;
    }

    try {
        video.currentTime = pendingVideoResumeAt;
    } catch (_) {}

    pendingVideoResumeAt = 0;
}

function startVideoKeepalive(source) {
    clearVideoKeepalive();
    activeVideoSource = source;
    lastVideoTime = -1;
    stalledVideoTicks = 0;

    videoKeepaliveTimer = window.setInterval(() => {
        ensureVideoPlayback();
    }, VIDEO_KEEPALIVE_MS);
}

function mountVideo(source) {
    clearGifPlayback();
    image.classList.add('hidden');
    canvas.classList.add('hidden');
    video.classList.remove('hidden');
    activeVideoSource = source;

    const onReady = () => {
        applyPendingVideoResume();
        video.play().catch(() => {});
    };

    video.addEventListener('loadedmetadata', onReady, { once: true });
    video.addEventListener('canplay', onReady, { once: true });

    requestAnimationFrame(() => {
        video.src = source;
        video.load();
        video.play().catch(() => {});
    });

    startVideoKeepalive(source);
}

function mountImage(source) {
    if (isGifSource(source)) {
        mountGif(source);
        return;
    }

    clearGifPlayback();
    video.classList.add('hidden');
    canvas.classList.add('hidden');
    image.classList.remove('hidden');

    requestAnimationFrame(() => {
        image.src = source;
    });
}

applyImageOptions(image);
video.crossOrigin = 'anonymous';
video.playsInline = true;
video.muted = true;
video.loop = true;
video.autoplay = true;
video.preload = 'auto';

video.addEventListener('stalled', ensureVideoPlayback);
video.addEventListener('suspend', ensureVideoPlayback);
video.addEventListener('waiting', ensureVideoPlayback);
video.addEventListener('ended', () => {
    try {
        video.currentTime = 0;
    } catch (_) {}
    ensureVideoPlayback();
});

document.addEventListener('visibilitychange', () => {
    if (!document.hidden) {
        ensureVideoPlayback();
        if (gifFrames.length > 0) {
            renderGifFrame(gifFrames[(gifFrameIndex + gifFrames.length - 1) % gifFrames.length]);
        }
    }
});

window.addEventListener('focus', ensureVideoPlayback);
window.addEventListener('pageshow', ensureVideoPlayback);
window.addEventListener('beforeunload', clearMediaState);
window.addEventListener('resize', () => {
    if (gifFrames.length > 0) {
        renderGifFrame(gifFrames[(gifFrameIndex + gifFrames.length - 1) % gifFrames.length]);
    }
});

if (src) {
    const decodedSrc = decodeURIComponent(src);
    clearMediaState();

    if (isVideoSource(decodedSrc, kind)) {
        mountVideo(decodedSrc);
    } else {
        mountImage(decodedSrc);
    }
}
