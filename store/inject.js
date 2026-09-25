// Copia a tela de Mac da página inicial para os quadros [data-mac], congelada no ponto pedido.
// data-mode: "floattube" | "chrome" · data-offset: deslocamento dos desktops (0 a 50, em %).
(async () => {
  const html = await (await fetch('/site/index.html')).text();
  const mac = new DOMParser().parseFromString(html, 'text/html').querySelector('.mac');
  for (const slot of document.querySelectorAll('[data-mac]')) {
    const copy = document.importNode(mac, true);
    slot.dataset.active = slot.dataset.mode || 'floattube';
    slot.classList.add('frozen');
    copy.querySelector('.spaces').style.transform = `translateX(-${slot.dataset.offset || 0}%)`;
    copy.querySelector('[data-clock]').textContent = 'qui. 25 de set. 16:52';
    slot.appendChild(copy);
  }
  document.documentElement.dataset.ready = 'true';
})();
