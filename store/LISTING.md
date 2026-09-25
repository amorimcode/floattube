# Chrome Web Store: textos do anúncio

Pacote: `dist/FloatTube-Chrome-Extension.zip` (gerado por `./macos/build.sh release`).

## Informações do produto

**Nome:** FloatTube

**Resumo** (até 132 caracteres):
> Troque de aba e o vídeo do YouTube continua num player flutuante no Mac que não se mexe ao trocar de desktop.

**Categoria:** Ferramentas (Tools)

**Idioma:** Português (Brasil)

**Descrição:**
> O FloatTube leva o vídeo do YouTube para um mini player flutuante no Mac, e esse player fica parado no mesmo lugar quando você troca de desktop (Space), inclusive durante a animação de troca.
>
> Como funciona:
> • Com um vídeo tocando, troque de aba: ele pausa e continua no player flutuante, no mesmo segundo.
> • Volte para a aba: o player fecha e a aba continua de onde ele parou.
> • Também dá para enviar manualmente pelo ícone da extensão ou com Alt+Shift+P.
>
> O player tem controles em Liquid Glass, pode ser arrastado de qualquer ponto e redimensionado pelas bordas ou com pinça no trackpad.
>
> IMPORTANTE: esta extensão funciona junto com o app gratuito FloatTube para macOS, que desenha o player flutuante. Baixe em https://floattube.vercel.app
>
> Privacidade: tudo acontece no seu computador. A extensão só conversa com o app no endereço local 127.0.0.1. Nenhum dado é coletado ou enviado para servidores.
>
> Código aberto: https://github.com/amorimcode/floattube
>
> Não é afiliado ao YouTube nem ao Google.

## Imagens

- Ícone da loja (128×128): `chrome-extension/icons/icon128.png`
- Capturas de tela (1280×800): `store/screenshot-1.png`, `store/screenshot-2.png`
- Bloco promocional pequeno (440×280): `store/promo-small.png`

## Links

- Site: https://floattube.vercel.app
- Suporte: https://github.com/amorimcode/floattube/issues
- Política de privacidade: https://floattube.vercel.app/privacy

## Práticas de privacidade

**Finalidade única:**
> Enviar o vídeo do YouTube que está tocando para o player flutuante do app FloatTube no Mac e trazê-lo de volta para a aba no mesmo ponto.

**Justificativa das permissões:**
- `storage`: guarda, no armazenamento de sessão, qual aba está com o vídeo no player e qual aba estava ativa, para devolver o vídeo à aba certa. É apagado quando o navegador fecha.
- Acesso a `https://www.youtube.com/*` (content script): ler o estado do vídeo (identificador, tempo, volume, se está tocando) para enviá-lo ao app local, e pausar ou retomar o vídeo na aba.

**Código remoto:** Não. Todo o código está no pacote.

**Uso de dados:** marcar que **nenhum** dado do usuário é coletado. A extensão envia o identificador e o tempo do vídeo apenas para um app no próprio computador do usuário (127.0.0.1); nada sai do computador.

Certificações a marcar:
- Não vendo nem transfiro dados de usuários para terceiros.
- Não uso nem transfiro dados para finalidades não relacionadas à finalidade única.
- Não uso nem transfiro dados para determinar crédito ou para empréstimos.
