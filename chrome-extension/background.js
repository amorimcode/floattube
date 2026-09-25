// Liga as abas do YouTube ao player flutuante do app FloatTube (WebSocket local).
//
// Fluxo: você sai de uma aba com vídeo tocando → a aba pausa e o app abre o vídeo no mesmo ponto.
// Você volta pra aba → o app fecha e a aba continua de onde o player flutuante parou.

const APP_URL = 'ws://127.0.0.1:38917';
const store = chrome.storage.session;

let socket = null;
let connecting = null;
let nextId = 1;
let keepAliveTimer = null;
const pending = new Map();

// Eventos de abas chegam em rajadas (trocar e voltar rápido); processar um por vez evita corridas.
let queue = Promise.resolve();
function serial(task) {
  const run = queue.then(task);
  queue = run.catch((error) => console.warn('FloatTube:', error));
  return run;
}

// MARK: conexão com o app

function connect() {
  if (socket?.readyState === WebSocket.OPEN) return Promise.resolve(socket);
  if (connecting) return connecting;
  connecting = new Promise((resolve, reject) => {
    const ws = new WebSocket(APP_URL);
    ws.onopen = () => {
      socket = ws;
      connecting = null;
      setOnline(true);
      resolve(ws);
    };
    ws.onclose = () => {
      if (socket === ws) socket = null;
      else {
        connecting = null;
        reject(new Error('app FloatTube fechado'));
      }
      setOnline(false);
      stopKeepAlive();
      for (const request of pending.values()) request.reject(new Error('conexão encerrada'));
      pending.clear();
    };
    ws.onmessage = (event) => onAppMessage(JSON.parse(event.data));
  });
  return connecting;
}

async function request(message, timeout = 4000) {
  const ws = await connect();
  const id = nextId++;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error('o app não respondeu'));
    }, timeout);
    const settle = (fn) => (value) => {
      clearTimeout(timer);
      pending.delete(id);
      fn(value);
    };
    pending.set(id, { resolve: settle(resolve), reject: settle(reject) });
    ws.send(JSON.stringify({ ...message, id }));
  });
}

function onAppMessage(message) {
  if (message.id != null) return pending.get(message.id)?.resolve(message);
  if (message.type === 'returnToTab') serial(() => returnToTab(message.tabId));
  else if (message.type === 'closed') serial(() => onPlayerClosed(message));
}

// O service worker dorme após ~30s sem atividade; com o player aberto, mantém a conexão viva.
function startKeepAlive() {
  if (keepAliveTimer) return;
  keepAliveTimer = setInterval(() => {
    if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: 'ping' }));
    else stopKeepAlive();
  }, 20000);
}

function stopKeepAlive() {
  clearInterval(keepAliveTimer);
  keepAliveTimer = null;
}

function setOnline(online) {
  chrome.action.setBadgeBackgroundColor({ color: '#d93025' });
  chrome.action.setBadgeText({ text: online ? '' : 'off' });
  chrome.action.setTitle({
    title: online
      ? 'FloatTube: enviar vídeo para o player flutuante (Alt+Shift+P)'
      : 'FloatTube: abra o app FloatTube no Mac',
  });
}

// MARK: estado (sobrevive ao service worker dormir)

async function getSession() {
  return (await store.get('session')).session ?? null;
}

async function setSession(session) {
  if (session) await store.set({ session });
  else await store.remove('session');
}

async function rememberActive(windowId, tabId) {
  const { lastActive = {} } = await store.get('lastActive');
  const previous = lastActive[windowId];
  lastActive[windowId] = tabId;
  await store.set({ lastActive });
  return previous;
}

// MARK: ida e volta

async function sendToFloat(tabId, { onlyIfPlaying }) {
  try {
    await connect();
  } catch {
    return false; // app fechado: deixa a aba como está
  }
  let info;
  try {
    info = await chrome.tabs.sendMessage(tabId, { type: 'ft:grab', onlyIfPlaying });
  } catch {
    return false; // não é uma aba do YouTube
  }
  if (!info) return false;

  const current = await getSession();
  if (current && current.tabId !== tabId) await bringBack(current, { resume: false });

  try {
    await request({ type: 'open', tabId, ...info });
  } catch {
    chrome.tabs.sendMessage(tabId, { type: 'ft:resume', time: info.time, play: info.playing }).catch(() => {});
    return false;
  }
  const tab = await chrome.tabs.get(tabId);
  await setSession({ tabId, windowId: tab.windowId, videoId: info.videoId });
  startKeepAlive();
  return true;
}

async function bringBack(session, { resume = true } = {}) {
  await setSession(null);
  stopKeepAlive();
  let state = null;
  try {
    state = await request({ type: 'close' });
  } catch {}
  if (state?.time == null) return;
  chrome.tabs
    .sendMessage(session.tabId, { type: 'ft:resume', videoId: state.videoId, time: state.time, play: resume && state.playing })
    .catch(() => {});
}

// Botão "voltar" no player: foca a aba; o onActivated faz o resto.
async function returnToTab(tabId) {
  const session = await getSession();
  const tab = await chrome.tabs.get(tabId).catch(() => null);
  if (!tab) {
    // A aba foi fechada: abre o vídeo numa aba nova, no ponto onde estava.
    await setSession(null);
    stopKeepAlive();
    const state = await request({ type: 'close' }).catch(() => null);
    if (state?.videoId) {
      await chrome.tabs.create({ url: `https://www.youtube.com/watch?v=${state.videoId}&t=${Math.floor(state.time ?? 0)}s` });
    }
    return;
  }
  await chrome.windows.update(tab.windowId, { focused: true });
  if (!tab.active) await chrome.tabs.update(tabId, { active: true });
  else if (session) await bringBack(session);
}

// Player fechado no X: a aba fica pausada, mas no ponto certo.
async function onPlayerClosed(message) {
  const session = await getSession();
  if (session?.tabId === message.tabId) {
    await setSession(null);
    stopKeepAlive();
  }
  chrome.tabs
    .sendMessage(message.tabId, { type: 'ft:resume', videoId: message.videoId, time: message.time, play: false })
    .catch(() => {});
}

async function toggle(tab) {
  if (!tab) return;
  const session = await getSession();
  if (session?.tabId === tab.id) return bringBack(session);
  const sent = await sendToFloat(tab.id, { onlyIfPlaying: false });
  if (!sent && session) await returnToTab(session.tabId);
}

// MARK: eventos

chrome.tabs.onActivated.addListener(({ tabId, windowId }) =>
  serial(async () => {
    const previous = await rememberActive(windowId, tabId);
    const session = await getSession();
    if (session?.tabId === tabId) return bringBack(session);
    if (previous != null && previous !== tabId) await sendToFloat(previous, { onlyIfPlaying: true });
  })
);

chrome.action.onClicked.addListener((tab) => serial(() => toggle(tab)));

chrome.commands.onCommand.addListener((command, tab) => {
  if (command === 'toggle-float') serial(() => toggle(tab));
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type !== 'ft:hello') return;
  if (sender.tab?.active) serial(() => rememberActive(sender.tab.windowId, sender.tab.id));
  connect().then(
    () => sendResponse({ online: true }),
    () => sendResponse({ online: false })
  );
  return true; // resposta assíncrona
});

// Ao acordar: descobre as abas ativas e, se havia um vídeo no player, reata a conexão.
serial(async () => {
  const { lastActive = {} } = await store.get('lastActive');
  for (const tab of await chrome.tabs.query({ active: true })) lastActive[tab.windowId] ??= tab.id;
  await store.set({ lastActive });
  if (await getSession()) {
    try {
      await connect();
      startKeepAlive();
    } catch {}
  }
});
