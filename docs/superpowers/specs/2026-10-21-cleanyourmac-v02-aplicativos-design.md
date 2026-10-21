# CleanYourMac v0.2 — Módulo Aplicativos (design)

Data: 2026-10-21 · Repo: https://github.com/guigx7/CleanYourMac ·
Antecessor: [v1 — Limpeza](2026-10-20-cleanyourmac-v1-limpeza-design.md) (publicada como v0.1.1)

## Intenção

O usuário usa o CleanMyMac todo dia e, depois da Limpeza, a página que mais abre
é **Aplicativos** — e usa todas as funções dela. A v0.2 reimplementa essa página
no CleanYourMac, com o mesmo processo da Limpeza: estudar o comportamento do
CleanMyMac 5.7.2 (clean room, REA), escrever specs com nossas palavras, TDD e
paridade medida nesta máquina. Código, textos e arte são nossos.

## O que o CleanMyMac mostra (reconhecimento de 2026-10-21, só análise)

Evidência: árvore de Acessibilidade (`re-notes/ax/apps-*`) e textos/símbolos dos
frameworks `ApplicationsModule`, `ApplicationsModuleDomain`, `ApplicationsService`,
`UninstallerScanning`, `UpdaterScanning`, `AppInfoNetworkService`,
`SparkleUpdaterService`, `MASUpdaterService`, `ApplicationsTerminator`
(`re-notes/static/`, fora do git).

- **Intro**: título, subtítulo, três categorias (Desinstalador, Atualizador,
  Sobras), botão Analisar.
- **Resultados**: "N apps encontrados no Mac", botão **Gerenciar Aplicativos** e
  cartões condicionais. Vistos nesta máquina: Sobras de Apps (Revisar + Remover),
  "Considere remover alguns aplicativos" (Revisar), Arquivos de Instalação
  (Revisar). Existentes no binário: Atualizações de Apps (Atualizar), Apps
  Não Usados, Apps de 32 bits, Atualizações do macOS (Ver Atualização).
- **Gerenciador de Aplicativos** (três seções na barra lateral):
  - **Desinstalador** — 26 apps. Filtros com contagem: Todos, Não Usados (sem
    abrir há mais de 6 meses), Suspeitos, Selecionados; Lojas (App Store,
    Setapp, Steam, Battle.net, Outro); Fornecedores (Apple, Google, JetBrains,
    MacPaw, Microsoft, Adobe, Outros); Plug-ins (Plug-ins de Áudio). Linha:
    checkbox, nome, última abertura, tamanho total (app + arquivos relacionados),
    botão para abrir os itens incluídos, agrupados por tipo: Binários,
    Preferências, Arquivos de Suporte, Contêiner, Caches, Registros, Relatórios
    de Falha, Itens de Início, Plug-ins, Ícone no Dock, Ajuda, Dados do Usuário,
    Instaladores, Outro. Ordenar por Nome, Tamanho, Última Abertura, Última
    Atualização. Rodapé "N selecionado(s) | tamanho" + Desinstalar.
  - **Atualizador** — nesta máquina, 1 item (GarageBand, App Store,
    10.4.13 → 10.4.14). Painel de detalhe: fonte, versão atual → nova, data de
    lançamento, tamanho, novidades. Menu Selecionar, rodapé + Atualizar. Quando
    não consegue atualizar, manda abrir o app, a App Store ou os Ajustes.
  - **Sobras** — grupos "Arquivos de Sobras" (49,2 KB) e "Instaladores"
    (DMGs não usados; 1 DMG do Warp, 187 MB). Rodapé + Remover.
- Apps de sistema protegidos não podem ser removidos, mas seus arquivos podem
  (o que equivale a **redefinir** o app). Apps da App Store protegidos pela Apple
  aparecem com explicação. Antes de desinstalar/atualizar, pede para fechar apps
  abertos.
- **De onde vêm as atualizações**: catálogo privado da MacPaw
  (`CheckAppsUpdatesRequest`), feeds Sparkle dos próprios apps (`SUFeedURL`) e a
  App Store (serviço XPC com APIs internas). **Não podemos usar o catálogo da
  MacPaw nem APIs privadas.**

## Objetivos

1. Fluxo completo: Intro → Análise → Resultados → Gerenciador (3 seções) →
   ação → Concluído/registro, com a mesma cara e as mesmas peças da Limpeza.
2. **Desinstalador** completo, com os filtros (exceto Suspeitos), a ordenação,
   os itens incluídos por tipo e a opção de **redefinir** (apagar só os
   arquivos e manter o app).
3. **Atualizador, etapa 1**: listar o que está desatualizado (versão atual e
   nova, data, novidades, fonte) a partir de fontes públicas; "Atualizar" abre o
   lugar certo (App Store, Ajustes, o próprio app ou a página do fornecedor).
4. **Sobras**: arquivos de apps já apagados e instaladores não usados.
5. Paridade da análise com o CleanMyMac nesta máquina (lista de apps, tamanhos,
   itens relacionados, sobras, instaladores, contagens dos filtros).
6. pt-BR e en; commits curtos e frequentes em `main`, com push.

## Não-objetivos (v0.2)

- **Instalar atualizações sozinho** (baixar, conferir, trocar o app). Fica para
  a **etapa 2** do módulo, decidida com o usuário; a v0.2 deve deixar o modelo
  de atualização pronto para recebê-la (fonte, URL do arquivo, assinatura
  esperada).
- Atualizar apps da App Store ou o macOS pelo app (não há forma pública; sempre
  abriremos a App Store/Ajustes, também na etapa 2).
- Filtro **Suspeitos** (depende da base de ameaças do módulo Proteção, fora do
  projeto).
- Catálogo próprio de atualizações em servidor; "Atualizações Vitais"/IA dos
  Cuidados Inteligentes.
- Lista de ignorados por app.

## Anti-objetivos

- **Apagar arquivo de outro app** ao desinstalar, redefinir ou remover sobras
  (falso positivo de "relacionado" ou de "sobra"). Na dúvida, o item não entra
  ou entra desmarcado.
- Apagar algo não selecionado, ou fora dos locais definidos pela spec.
- Deixar o sistema quebrado: nunca remover apps da Apple protegidos pelo sistema
  nem arquivos do sistema; nunca desinstalar o próprio CleanYourMac por acidente.
- Enviar ao exterior mais do que o necessário para checar atualizações.
- Copiar código, textos, ícones ou dados do CleanMyMac; usar o servidor da
  MacPaw ou APIs privadas da Apple.

## Restrições herdadas (valem como na v1)

- **Testes só simulação**: no CleanMyMac, apenas a análise (nunca Desinstalar,
  Remover, Atualizar, Redefinir — o `dump-ax` recusa esses cliques). Nossa
  remoção é testada em árvores falsas e **apps de teste criados por nós** em
  pasta temporária; Debug continua em simulação por padrão. Um teste real
  controlado (app de teste instalado de propósito) só com o usuário, no fim.
- Caminhos e regras são fatos técnicos e podem coincidir; o resto é nosso.
- Não decifrar `Resources/info.cmmkb`.
- Permissões (Acesso Total ao Disco, Gerenciamento de Apps, aprovação do
  ajudante) são concedidas pelo usuário, nunca por nós.

## Decisões do usuário

- Módulo escolhido: **Aplicativos**, a página inteira.
- **Atualizador em duas etapas**: etapa 1 mostra e abre; etapa 2 instala sozinho
  os apps de site próprio (Sparkle e afins) e do Homebrew, só se a assinatura da
  versão nova for do mesmo desenvolvedor (Team ID) da instalada. App Store e
  macOS sempre abrem a loja/Ajustes.
- A lista do Atualizador pode não bater 100% com a do CleanMyMac (ele usa
  catálogo privado); a diferença é aceita e documentada.
- Resumo aprovado: sem filtro Suspeitos, com Redefinir, nunca mexer em apps da
  Apple protegidos, pedir para fechar apps antes de desinstalar/atualizar.
- **Destino do que é removido** (aceitou a recomendação): apps e arquivos de
  apps (Desinstalar, Redefinir, Sobras) vão para o **Lixo** — do volume do
  item; itens de sistema movidos pelo helper vão para o Lixo do usuário que
  pediu. **Instaladores** (DMG/pkg não usados) são apagados na hora, como na
  Limpeza. Isso difere do CleanMyMac se ele apagar de vez; a diferença é
  intencional e fica documentada.
- **Helper ganha duas operações** (aceitou a recomendação): descarregar um job
  do launchd (`launchctl bootout`) antes de remover o plist dele, e esquecer o
  recibo de um pacote (`pkgutil --forget`). Mesmas travas das atuais: só para
  itens do app selecionado, revalidados como root, nunca `com.apple.*` nem
  recibos da Apple, nunca através de links. Mover para o Lixo também passa a
  existir no helper.

## Fontes públicas do Atualizador (etapa 1)

1. **Feed do próprio app**: `SUFeedURL` no `Info.plist` (Sparkle) — lê o
   appcast e compara a maior versão válida para este macOS com a instalada.
2. **App Store**: apps com recibo (`Contents/_MASReceipt`) consultados na busca
   pública da loja por bundle ID (`itunes.apple.com/lookup`).
3. **Homebrew**: catálogo público de casks (`formulae.brew.sh/api`), casando
   pelo app que o cask instala. Útil para apps sem feed (ex.: Chrome, VS Code,
   Discord).
4. **macOS**: atualizações disponíveis do sistema (equivalente a
   `softwareupdate --list`), com botão que abre Ajustes › Atualização de Software.

Privacidade: só essas consultas, só durante a análise do módulo, enviando apenas
o necessário (bundle ID na busca da App Store; nenhuma lista de apps vai para o
Homebrew — baixamos o catálogo e comparamos localmente). Sem rede, o Atualizador
mostra que não pôde checar, e o resto do módulo funciona.

## Segurança

- Raízes permitidas por tipo de item (app em `/Applications`, `~/Applications`
  e subpastas de lojas; arquivos relacionados nas pastas de `Library` definidas
  pela spec; instaladores nas pastas definidas pela spec). O motor de limpeza e
  o helper revalidam; links nunca são seguidos.
- "Relacionado a um app" exige vínculo forte (bundle ID, Team ID/grupo de app,
  nome do app com regra da spec). Vínculo fraco → item desmarcado ou fora.
- Sobras: só arquivos cujo dono identificável não existe mais entre os apps
  instalados; em dúvida, não entra.
- Apps abertos: antes de desinstalar/redefinir, listar os abertos e pedir para
  fechá-los (fechar normal; forçar só com confirmação).
- O próprio CleanYourMac aparece na lista mas não pode ser desinstalado por ele
  mesmo na v0.2.
- Toda operação gera registro em `~/Library/Logs/CleanYourMac/`.

## Processo

- Specs em `docs/re/specs/apps/<tema>.md` (mesmo template), escritas por
  subagentes a partir da evidência: inventário de apps e tamanhos; arquivos
  relacionados por tipo; filtros (lojas, fornecedores, não usados, plug-ins de
  áudio, 32 bits); redefinir; sobras; instaladores; atualizador (fontes,
  comparação de versões, apps abertos); tela de resultados/cartões.
- Baseline de paridade da análise do CleanMyMac (AX + `fs_usage`) e comparação
  com a nossa via `scripts/parity/`.
- Core + testes por tema → UI → integração → paridade → revisão final → release
  v0.2.0.

## Decisões do construtor (podem ser revistas)

- **Paridade × vínculo forte: a segurança ganha.** Critério de aceite: para
  cada app, nossos itens relacionados são um subconjunto dos do CleanMyMac
  (mesmos caminhos e tamanhos onde coincidem, tolerância de 1% ou 1 MB para
  arquivos que mudam); onde ele acha mais (provavelmente pela base `info.cmmkb`
  ou casamentos de nome mais frouxos), a diferença é documentada na spec e
  **não** é falha. Ter item que ele não tem é falha, salvo justificativa escrita.
  Para lista de apps, sobras, instaladores e contagens dos filtros, a paridade
  é exata.
- **Redefinir**: vale para qualquer app (para apps da Apple protegidos é a
  única opção). A marcação segue a do CleanMyMac; se a redefinição incluir
  Dados do Usuário ou Contêiner, aparece uma confirmação extra dizendo o que se
  perde (ex.: e-mails, fototeca, histórico).
- **Homebrew**:
  - Atualizador: a fonte Homebrew só vale para apps instalados pelo `brew`
    (presentes no Caskroom) ou sem outra fonte; casks com `auto_updates` ficam
    de fora; versões que não dá para comparar com segurança não geram item.
  - O botão Atualizar desses itens mostra o comando `brew upgrade --cask <nome>`
    (para copiar) e o link do fornecedor; o app não roda o `brew`.
  - Desinstalar app vindo do `brew`: removemos app e arquivos normalmente e
    avisamos que o registro no Homebrew continua (`brew uninstall --cask`
    limpa).

## Deixado para quem for construir

- Nomes de tipos, organização em `Core/` e `App/`, como reaproveitar
  `CleanEngine`, `PathPolicy`, `ReviewView` e o helper.
- Algoritmo de comparação de versões, cache do catálogo do Homebrew,
  paralelismo da checagem de atualizações.
- Arte do módulo (nova, no estilo da Limpeza) e paleta.
- Ordem dos cartões e das linhas quando a RE não deixar claro.
