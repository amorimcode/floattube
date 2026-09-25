// Copia a tela de Mac da página inicial para os quadros [data-mac], congelada no ponto pedido.
// data-mode: "floattube" | "chrome" · data-offset: deslocamento dos desktops (0 a 50, em %).
// data-lang="en": troca os textos da tela para inglês (imagens do portfólio, que é em inglês).
const english = {
  '.menus': '<span>File</span><span>Edit</span><span>View</span><span>History</span><span>Bookmarks</span><span>Window</span><span>Help</span>',
  '.browser .tab': 'Swift lesson · YouTube',
  '.paused-video span': '<b>Playing in FloatTube</b>come back to this tab to continue here',
  '[data-clock]': 'Thu Sep 25  4:52 PM'
};
function translate(root) {
  for (const [selector, html] of Object.entries(english)) root.querySelector(selector).innerHTML = html;
}

(async () => {
  const html = await (await fetch('/site/index.html')).text();
  const mac = new DOMParser().parseFromString(html, 'text/html').querySelector('.mac');
  for (const slot of document.querySelectorAll('[data-mac]')) {
    const copy = document.importNode(mac, true);
    slot.dataset.active = slot.dataset.mode || 'floattube';
    slot.classList.add('frozen');
    copy.querySelector('.spaces').style.transform = `translateX(-${slot.dataset.offset || 0}%)`;
    copy.querySelector('[data-clock]').textContent = 'qui. 25 de set. 16:52';
    if (slot.dataset.lang === 'en') translate(copy);
    slot.appendChild(copy);
  }
  document.documentElement.dataset.ready = 'true';
})();
