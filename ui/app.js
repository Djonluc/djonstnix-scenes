const params = new URLSearchParams(window.location.search);
const src = params.get('src');
const image = document.getElementById('scene-image');

image.referrerPolicy = 'no-referrer';

if (src) {
    image.src = decodeURIComponent(src);
}
