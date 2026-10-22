# CleanYourMac v0.4 — Lupa de Espaço (design)

Data: 2026-10-22 · Repo: https://github.com/guigx7/CleanYourMac ·
Antecessores: [v1 — Limpeza](2026-10-20-cleanyourmac-v1-limpeza-design.md),
[v0.2 — Aplicativos](2026-10-21-cleanyourmac-v02-aplicativos-design.md),
[v0.3 — Desempenho](2026-10-22-cleanyourmac-v03-desempenho-design.md)

## Intenção

Quarto módulo e último do roadmap: **Lupa de Espaço**, reimplementando a página de mesmo nome do CleanMyMac 5.7.2
com o mesmo processo (RE clean room, specs com nossas palavras, TDD, paridade nesta máquina, teste real controlado).
O usuário pediu para "planejar, testar, encontrar os erros e só parar quando terminar", sem rodada de perguntas:
as decisões abaixo são do construtor e ficam registradas como tal.

## O que o CleanMyMac mostra (reconhecimento de 2026-10-22, só análise)

Evidência: textos de `SpaceLensModule` (33 chaves) e `SpaceLensUI` (19), símbolos de `SpaceLensModule`,
`SpaceLensScanning`, `SpaceLensUI` (`re-notes/static/`) e dumps de Acessibilidade (`re-notes/ax/spacelens-20261022/`).

- **Intro:** título, subtítulo, três categorias (mapa visual do armazenamento, descoberta de arquivos ocultos, visão
  geral de pastas grandes), seletor de alvo ("Macintosh HD" ou "Escolher pasta…") e Analisar.
- **Análise:** "Visualizando o espaço de armazenamento…"; o disco inteiro (~3 milhões de itens) em ~20 s nesta máquina.
- **Resultados:** cabeçalho com o volume e "X de Y usados", tamanho e contagem de itens da pasta atual; à esquerda a
  lista dos filhos por tamanho (ocultos incluídos), com "Outros itens" agrupando os pequenos e, na raiz do disco, a
  linha "Espaço Purgável"; à direita o mapa de bolhas (um círculo por item, proporcional ao tamanho); caminho clicável,
  voltar/avançar; seleção por caixa e rodapé "N item selecionado · tamanho" + **Revisar e Remover**.
- **Revisão e remoção:** lista dos selecionados de todas as pastas, Remover, progresso, conclusão (sucesso/falha) e
  registro. Itens essenciais do sistema não podem ser apagados; pastas do sistema pedem confirmação; arquivos na nuvem
  têm alerta próprio.
- "Pouco conteúdo para visualizar…" quando a pasta analisada tem pouca coisa.

## Objetivos

1. Fluxo completo: Intro (disco ou pasta) → Análise com progresso e Parar → Resultados (lista + mapa de bolhas,
   navegação por pastas, caminho, voltar/avançar) → Revisão → Remoção → Concluído/registro, no visual dos outros
   módulos (gradiente roxo/azul próprio, arte própria).
2. **Análise rápida e correta** só com API pública: varredura paralela, sem seguir links, sem cruzar volumes (exceto
   os firmlinks do volume de dados), tamanho como o do CleanMyMac (a spec define alocado ou lógico e hard links).
3. **Paridade** nesta máquina: os filhos da raiz, de `/Users` e da pasta pessoal, com os tamanhos dentro do
   arredondamento da tela do CleanMyMac; "Outros itens" pela mesma regra; "usados" e o purgável.
4. **Remover = mover para o Lixo** (padrão do projeto desde a v0.2), nunca itens essenciais do sistema, aviso em pastas
   do sistema, e o que precisar de root pelo ajudante (as mesmas travas da v0.2).
5. pt-BR e en; commits curtos em `main` com push; release ao final, com o ok do usuário.

## Não-objetivos

- Limpeza de Nuvem (o CleanMyMac manda os itens só na nuvem para outro módulo): aqui eles aparecem, mas não são
  removíveis.
- Monitorar o disco em segundo plano ou manter um índice permanente.
- Apagar de vez (sem Lixo).

## Anti-objetivos

- Travar o Mac ou o app numa varredura de milhões de itens (memória e tempo limitados, Parar sempre funciona).
- Remover algo do sistema (SIP, `/System`, `/usr`, `/bin`, `/sbin`, `/private/var/db`…), a pasta pessoal inteira ou
  pastas vitais dela.
- Contar duas vezes o mesmo dado (firmlinks, hard links) e com isso mostrar números maiores que o disco.
- Copiar código, textos, ícones ou dados do CleanMyMac; decifrar `info.cmmkb`; APIs privadas.

## Decisões do construtor

- **Paridade × honestidade:** os números seguem a regra do CleanMyMac quando ela é verificável; se a regra dele contar
  duas vezes (ex.: firmlinks), seguimos a correta e a diferença vai para "Divergências conhecidas".
- **Proteção:** essenciais (não removíveis) = a lista da spec; mais as travas do projeto (`PathPolicy.isVital`, a
  pasta pessoal e as pastas vitais dela). Itens de root só pelo ajudante (`.trash`, mesmas validações) ou pela senha.
- **Memória:** a árvore guarda por nó só nome, tamanho, contagem e filhos; filhos pequenos de pastas grandes podem ser
  resumidos (spec define), para caber 3 milhões de itens.
- **Mapa:** circle packing próprio, desenhado em SwiftUI `Canvas`; só o nível atual (com os netos como bolhas menores
  se a spec mostrar isso).
- **Simulação:** respeita `CYM_DRY_RUN`; o teste real usa só pastas de teste criadas por nós.

## Processo

Specs em `docs/re/specs/spacelens/` → baseline (AX) → Core (`SpaceLens/`: árvore, scanner, agrupamento, proteção,
remoção) + `cym spacelens [--json] [caminho]` → app (`App/SpaceLens/`) → paridade → revisão final → teste real com
pasta de teste → release.
