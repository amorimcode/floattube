// Demonstração da página: troca de desktop automática e comparação FloatTube × PiP do Chrome.

const stage = document.querySelector('[data-stage]');

if (stage) {
  const mac = stage.querySelector('.mac');
  const hud = stage.querySelector('.hud');
  const hudKey = stage.querySelector('[data-hud-key]');
  const hudLabel = stage.querySelector('[data-hud-label]');
  const buttonKey = stage.querySelector('[data-key]');
  const appName = stage.querySelector('[data-app]');
  const caption = stage.querySelector('[data-caption]');
  const modeButtons = stage.querySelectorAll('[data-mode]');
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');

  const captions = {
    floattube: 'O player vive num Space próprio, acima dos desktops. Eles deslizam; ele não se move.',
    chrome: 'O PiP do Chrome pertence ao desktop: desliza junto na troca e só reaparece no lugar no fim.',
  };

  let timer = null;
  let hudTimer = null;
  let visible = false;

  const setMode = (mode) => {
    stage.dataset.active = mode;
    for (const button of modeButtons) button.setAttribute('aria-pressed', String(button.dataset.mode === mode));
    caption.textContent = captions[mode];
  };

  const switchSpace = () => {
    const toSecond = !mac.classList.contains('at-2');
    hudKey.textContent = toSecond ? '→' : '←';
    hudLabel.textContent = toSecond ? 'Desktop 2' : 'Desktop 1';
    buttonKey.textContent = toSecond ? '←' : '→';
    hud.classList.add('show');
    mac.classList.toggle('at-2', toSecond);
    appName.textContent = toSecond ? 'Xcode' : 'Google Chrome';
    clearTimeout(hudTimer);
    hudTimer = setTimeout(() => hud.classList.remove('show'), 900);
  };

  const schedule = () => {
    clearInterval(timer);
    timer = visible && !reduceMotion.matches ? setInterval(switchSpace, 3400) : null;
  };

  for (const button of modeButtons) {
    button.addEventListener('click', () => setMode(button.dataset.mode));
  }

  stage.querySelector('[data-switch]').addEventListener('click', () => {
    switchSpace();
    schedule();
  });

  new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    stage.classList.toggle('paused', !visible);
    schedule();
  }, { threshold: 0.25 }).observe(mac);

  reduceMotion.addEventListener('change', schedule);

  const clock = stage.querySelector('[data-clock]');
  const format = new Intl.DateTimeFormat('pt-BR', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
  const tick = () => { clock.textContent = format.format(new Date()).replace(/,/g, ''); };
  tick();
  setInterval(tick, 30000);
}

for (const button of document.querySelectorAll('[data-copy]')) {
  button.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(document.getElementById(button.dataset.copy).textContent);
      button.textContent = 'Copiado';
      setTimeout(() => { button.textContent = 'Copiar'; }, 1600);
    } catch {}
  });
}

const topbar = document.querySelector('.topbar');
const onScroll = () => topbar.classList.toggle('scrolled', scrollY > 8);
addEventListener('scroll', onScroll, { passive: true });
onScroll();
