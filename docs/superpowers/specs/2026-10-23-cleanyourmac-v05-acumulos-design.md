# CleanYourMac v0.5 — Acúmulos (design)

Data: 2026-10-23 · Repo: https://github.com/guigx7/CleanYourMac · Antecessores: v0.1–v0.4 (Limpeza, Aplicativos,
Desempenho, Lupa de Espaço).

## Intenção

Quinto módulo: **Acúmulos** ("My Clutter"), reimplementando o módulo de mesmo nome do CleanMyMac 5.7.2 com o mesmo
processo clean room. O usuário pediu "faça a função igual à do CleanMyMac" e dispensou as perguntas: as decisões abaixo
são do construtor.

## O que o CleanMyMac mostra (2026-10-23, só análise)

Specs em `docs/re/specs/clutter/` (evidência: textos e símbolos de `OrganizeModule`, `OrganizeScanning`,
`DownloadsScanning`; disassembly; dumps de Acessibilidade em `re-notes/ax/clutter-20261023/`).

- **Intro:** quatro categorias (Arquivos grandes, Duplicatas, Imagens similares, Downloads), alvo = pasta pessoal ou
  "Escolher pasta…", Analisar. Análise da pasta pessoal: ~20 s.
- **Resultados:** "Você tem N arquivos para revisar", **Revisar Todos os Arquivos** e cartões (vistos: "13 Imagens
  Similares Novas Encontradas", "45 Arquivos Duplicados Encontrados em Documentos", "591 MB de Downloads do Google Chrome
  Encontrados").
- **Gerenciador** com quatro seções: **Fundo do Baú** (5 arquivos, filtros por tipo, tamanho e data de acesso),
  **Duplicatas** (149 grupos, filtro "Mostrar:" por tipo), **Imagens Similares** (65 grupos por data), **Downloads**
  (grupos por app). Seleção começa vazia; menu "Selecionar" por grupo; remoção com revisão.

## Objetivos

1. Fluxo completo como nos outros módulos: Intro (pasta pessoal ou pasta escolhida) → Análise com Parar → Resultados
   (cartões) → Gerenciador (4 seções, filtros, seleção, "Selecionar Tudo" com alerta) → remoção → Concluído/registro.
2. Regras de cada parte iguais às da spec quando verificáveis: exclusões comuns, mínimos (100 KiB; 50 MiB), cadeia de
   desempate da cópia que sai, faixas dos filtros, cartões.
3. Paridade nesta máquina: Fundo do Baú e Duplicatas exatos (nomes, tamanhos, contagens); Downloads e Similares
   aproximados (fontes diferentes por regra do projeto), com as diferenças em "Divergências conhecidas".
4. Remover = Lixo; fototeca só pelo PhotoKit (Apagados Recentemente, confirmação do sistema).
5. pt-BR e en; commits curtos em `main`; release só com o ok do usuário.

## Não-objetivos

- Duplicatas dentro da fototeca (só imagens soltas e fototeca em Similares).
- Smart Care / Cuidados Inteligentes.

## Anti-objetivos

- Remover a única cópia de um arquivo, ou todas as cópias de um grupo sem confirmação explícita.
- Tocar `~/Library`, arquivos do sistema, pacotes de apps em uso, a fototeca por fora do PhotoKit.
- Copiar código/dados do CleanMyMac, decifrar `info.cmmkb`, APIs privadas (inclui as chaves KVC não documentadas do
  `PHAsset` que o CleanMyMac usa).

## Decisões do construtor

- **Duplicatas:** tamanho → SHA-256 (CryptoKit, blocos de 1 MiB) do arquivo inteiro; pacotes `.app` como um item (hash do
  conteúdo). Hard links contam como no CleanMyMac (paridade); clones idem. Cadeia de desempate da spec; exatamente uma
  cópia fica de fora na marcação automática.
- **Similares:** imagens soltas (≥ 100 KiB, `UTType.image`, sem psd/psb/xcassets, sem as cópias exatas de Duplicatas) +
  fototeca por PhotoKit (miniaturas locais, sem rede). Mesmo algoritmo do CleanMyMac reproduzido com a vImage (hash de
  gradientes em 4 orientações, soma ≤ 15, agrupamento guloso sem fusão); "melhor para manter" pela mesma pontuação
  (ruído, nitidez por Haar, faixa dinâmica, tamanho). Sem permissão do Fotos, analisa só as imagens soltas.
  *(Revisado: a ideia inicial de usar Vision foi trocada depois da RE do hash.)*
- **Fundo do Baú:** pasta pessoal, ≥ 50 MiB, data = último acesso (`contentAccessDate`), faixas da spec.
- **Downloads:** como o CleanMyMac, pelo histórico de downloads (Chrome: banco `History` de cada perfil, lido de uma
  cópia; Safari: `Downloads.plist`, com Acesso Total ao Disco); só concluídos cujo arquivo existe; marcação automática =
  mais de 30 dias. Slack sem leitor. *(Revisado: a ideia inicial da marca de quarentena dava resultado diferente.)*
- **Tamanhos:** os da tela do CleanMyMac (a spec define lógico × alocado por parte).
- **Simulação:** `CYM_DRY_RUN` como sempre; teste real só com pastas de teste `io.github.guigx7.cymtest`.
