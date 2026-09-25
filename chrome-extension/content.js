// Roda nas páginas do YouTube: entrega o estado do vídeo para o background e, enquanto o app
// FloatTube estiver aberto, desativa o PiP nativo do Chrome (inclusive o automático ao trocar de aba).

function currentVideoId() {
  const url = new URL(location.href);
  if (url.pathname === '/watch') return url.searchParams.get('v');
  return url.pathname.match(/^\/(?:shorts|live|embed)\/([\w-]{11})/)?.[1] ?? null;
}

function mainVideo() {
  const playing = [...document.querySelectorAll('video')].find((v) => !v.paused && !v.ended);
  return playing || document.querySelector('#movie_player video') || document.querySelector('video');
}

// Durante um anúncio o <video> está no tempo do anúncio; a barra de progresso guarda o do vídeo.
function contentTime(video) {
  if (!document.querySelector('#movie_player.ad-showing')) return video.currentTime;
  return Number(document.querySelector('.ytp-progress-bar')?.getAttribute('aria-valuenow')) || 0;
}

function grab(onlyIfPlaying) {
  const videoId = currentVideoId();
  const video = mainVideo();
  if (!videoId || !video) return null;
  const playing = !video.paused && !video.ended;
  if (onlyIfPlaying && !playing) return null;

  const slider = Number(document.querySelector('.ytp-volume-panel')?.getAttribute('aria-valuenow'));
  const info = {
    videoId,
    list: new URL(location.href).searchParams.get('list'),
    time: contentTime(video),
    playing,
    rate: video.playbackRate,
    volume: Number.isFinite(slider) ? slider : Math.round(video.volume * 100),
    muted: video.muted,
    title: document.title.replace(/^\(\d+\)\s*/, '').replace(/\s*-\s*YouTube$/, ''),
  };
  video.pause();
  return info;
}

function resume({ videoId, time, play }) {
  if (videoId && videoId !== currentVideoId()) return; // a aba já está em outro vídeo
  const video = mainVideo();
  if (!video) return;
  if (Number.isFinite(time) && Math.abs(video.currentTime - time) > 1) video.currentTime = time;
  if (play) video.play().catch(() => {});
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message.type === 'ft:grab') sendResponse(grab(message.onlyIfPlaying));
  else if (message.type === 'ft:resume') resume(message);
});

// `play` não borbulha, mas passa pela captura no document.
document.addEventListener('play', async (event) => {
  if (!(event.target instanceof HTMLVideoElement) || !currentVideoId()) return;
  let online = false;
  try {
    online = (await chrome.runtime.sendMessage({ type: 'ft:hello' }))?.online === true;
  } catch {}
  for (const video of document.querySelectorAll('video')) video.disablePictureInPicture = online;
}, true);
