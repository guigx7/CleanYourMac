# CleanYourMac v1 — Módulo Limpeza (design)

Data: 2026-10-20 · Repo: https://github.com/guigx7/CleanYourMac

## Intenção

CleanYourMac é um app macOS **open source, para estudo**, que reimplementa as
funcionalidades do CleanMyMac (MacPaw) com código e arte próprios. O app final
terá os módulos Limpeza, Desempenho, Aplicativos e Lupa de Espaço. Proteção,
Nuvem, Cuidados Inteligentes, Ferramentas e Atividades estão fora do projeto.

A **v1 entrega só o módulo Limpeza, funcionando 100%**: o comportamento (onde
procura, o que entra em cada grupo, o que vem marcado como recomendado, como
remove) deve ser **o mesmo do CleanMyMac 5.7.2**, que está instalado nesta
máquina em `/Applications/Setapp/CleanMyMac.app`.

## Objetivos

1. Fluxo completo de Limpeza: Intro → Análise → Resultados → Gerenciador de
   Limpeza (revisão) → Limpeza → Concluído.
2. Paridade de comportamento com o CleanMyMac em todos os grupos listados abaixo,
   verificada nesta máquina.
3. UI simples, mas boa: cara de app nativo, com animações simples que mostram o
   que está acontecendo (o que está sendo varrido, o total subindo, o progresso
   da remoção).
4. Interface em **pt-BR e en** desde a v1.
5. Commits pequenos e frequentes, um por etapa curta, enviados para `main`.

## Não-objetivos (v1)

- Outros módulos (Desempenho, Aplicativos, Lupa de Espaço). A navegação lateral
  pode mostrá-los desabilitados ou com "em breve", mas eles não são implementados.
- Proteção/malware, Limpeza de Nuvem, menu na barra, monitor de saúde, agendamentos.
- Lista de exclusões / ajustes por grupo (o CleanMyMac tem; fica para depois).
- Distribuição assinada/notarizada, auto-update, App Store.
- Helper privilegiado instalado permanentemente (SMAppService/launchd).

## Anti-objetivos (seria fracasso mesmo funcionando)

- **Apagar algo que o usuário não selecionou**, ou qualquer coisa fora dos locais
  que a especificação define. Segurança vem antes de paridade.
- Deixar um app quebrado (assinatura inválida, app não abre) após remover
  Binários Universais ou Arquivos de Idioma.
- Copiar código, ícones, imagens, animações (`.heif`, Rive) ou textos descritivos
  do CleanMyMac. Nomes funcionais de categorias ("Caches do Usuário",
  "Lixos") podem coincidir; **descrições, títulos de cartões e mensagens são
  escritos por nós**.
- Publicar no repo dados extraídos do CleanMyMac (listas de regras deles
  copiadas literalmente). A especificação descreve o comportamento com nossas
  palavras; as regras do nosso app são nossas, montadas a partir dela e de
  fontes públicas.

## Taxonomia (levantada dos textos do `JunkCleanupModule`)

Categorias e grupos que o CleanMyMac exibe. A v1 implementa **todos**:

**Detritos do Sistema**
- Arquivos de Cache do Usuário
- Arquivos de Cache do Sistema
- Arquivos de Registro do Usuário
- Arquivos de Registro do Sistema
- Binários Universais (binários extras)
- Arquivos de Idioma
- Itens de Início Defeituosos
- Preferências Defeituosas
- Versões de Documentos
- Usuários Apagados
- Backups de Dispositivos iOS (com selo "Mais recente" e alerta ao remover o mais recente)
- Detritos do Xcode (Caches do Xcode, Registros de Dispositivos iOS, dados derivados, …)

**Acúmulos de IA**
- Detritos de IA: caches, registros, arquivos temporários e versões defasadas de
  ferramentas de IA (ex.: Claude, Codex, Gemini, Cursor), agrupados por ferramenta
- Modelos locais (Ollama, LM Studio), com alerta antes de remover

**Anexos do Mail**
- Downloads do Mail / anexos do Mail (mantendo arquivos modificados pelo usuário)

**Lixos**
- Lixo do usuário, lixos de volumes externos, Lixos do Mail

Na tela de Resultados aparecem cartões: Detritos do Sistema (Revisar + Limpar),
Acúmulos de IA (Revisar), e cartões de destaque para grupos específicos quando
houver algo encontrado (Binários Extras, Backups do iOS, Detritos do Xcode,
Versões de Documentos, Usuários Apagados, Anexos do Mail, Lixos). Quais cartões
aparecem e em que ordem é definido pela especificação de engenharia reversa.

## Fluxo e telas

1. **Intro**: arte do módulo, título, subtítulo, lista das 4 categorias com
   ícones, botão circular **Analisar**. Fundo em gradiente verde.
2. **Análise**: animação contínua na arte + texto do que está sendo varrido
   agora (categoria e pasta) + total encontrado subindo. Botão Parar.
3. **Resultados**: "O Mac tem X de detritos.", botão **Revisar Todos os
   Detritos**, grade de cartões. Botão **Recomeçar** na barra. Se nada for
   encontrado: estado "Mac limpo".
4. **Gerenciador de Limpeza** (tela clara, padrão macOS), três colunas:
   - categorias;
   - grupos da categoria, com ícone e tamanho;
   - itens do grupo: checkbox, ícone (do app ou pasta), nome, tamanho, chevron
     para abrir os filhos (ex.: arquivos dentro de uma pasta de cache), e
     marcação dos itens recomendados.
   - Menu **Selecionar** (Nenhum / Recomendados / Todos), **busca**, **Ordenar
     por** (Tamanho / Nome), botão Voltar.
   - Rodapé: "N itens selecionados | tamanho" e botão **Limpar** (desabilitado
     sem seleção). Os checkboxes propagam (pai ↔ filhos, estado misto).
5. **Limpeza**: animação de progresso com o item sendo removido agora; ao fim,
   "Limpeza concluída!" com o total removido, ou estado de falha parcial com
   **Registro de Limpeza** listando o que falhou e por quê.
6. Alertas de confirmação nos casos que o CleanMyMac alerta (backup iOS mais
   recente, modelos locais).

Visual: inspirado no CleanMyMac (gradiente, vidro/material, ícones grandes),
com **arte própria** (SF Symbols + formas desenhadas em SwiftUI). Animações
simples em SwiftUI (pulsar/girar durante a análise, contadores animados,
transições entre telas). Sem bibliotecas de animação externas.

## Como o comportamento será descoberto (processo clean room)

Fontes de evidência, nesta ordem de preferência:

1. **Observação de comportamento**: rodar a análise e a limpeza do CleanMyMac
   com `fs_usage`/`eslogger`/`opensnoop` capturando os acessos, e comparar com o
   que a UI dele mostra (tamanhos por grupo, itens listados, o que vem marcado).
2. **Inspeção estática leve**: textos localizados, `Info.plist`, `strings`,
   símbolos Swift (`nm`/`swift-demangle`) dos frameworks
   `SystemJunkScanning`, `AIToolScanning`, `LocalModelScanning`,
   `MailJunkScanning`, `TrashJunkScanning`, `UnusedDiskImagesScanning`,
   `CleaningCore`, `PrivilegedRoutines`, `KnowledgeBaseService`,
   `LegacyScanningCore`.
3. **REA + Ghidra**: para regras que só aparecem no código (critérios de
   "recomendado", exclusões, idade/tamanho mínimo, como detecta preferência
   defeituosa, como remove arquitetura de binário e o que faz com a assinatura).
   REA (`rea-agents`, MCP) e Ghidra (com Java) precisam ser instalados.
4. Se alguma regra vier de servidor (`KnowledgeBaseService`), documentar o
   comportamento observado e criar nossa própria regra equivalente.

Saída: uma especificação por grupo em `docs/re/specs/<grupo>.md`, escrita com
nossas palavras, contendo: locais varridos, regra de inclusão/exclusão, regra de
"recomendado", agrupamento e nome exibido de cada item, como o tamanho é
calculado, como a remoção é feita (apagar definitivamente vs. Lixo, precisa de
admin?), alertas, e a evidência que sustenta cada afirmação. Notas brutas de
investigação (saídas do REA, pseudocódigo) ficam **fora do repositório**
(scratchpad local / `.gitignore`), e o código do app é escrito a partir das
especificações, não do pseudocódigo.

## Arquitetura (decisões tomadas)

- **Swift 6 + SwiftUI**, macOS 14+, projeto Xcode, fora do sandbox, Hardened
  Runtime ligado, assinatura de desenvolvimento local.
- **Acesso Total ao Disco**: o app detecta se tem, e mostra uma tela guiando o
  usuário a conceder (abre o painel certo de Ajustes do Sistema).
- **Operações de administrador** (caches/registros do sistema, Usuários
  Apagados, Versões de Documentos, Binários Universais em `/Applications`, etc.):
  na v1, pedir a senha no momento da limpeza, uma vez por limpeza, executando um
  lote de operações com privilégio. Sem helper permanente.
- Separação em camadas:
  - **Core** (pacote Swift, sem UI, testável): modelos (Categoria, Grupo, Item),
    um `Scanner` por grupo, motor de análise com progresso por stream, motor de
    limpeza com resultado por item, cálculo de tamanho (alocado em disco).
  - **App** (SwiftUI): telas, view models, animações, localização.
- Regras de cada grupo descritas como dados no nosso repo sempre que possível
  (caminhos, padrões, exclusões), para facilitar revisão e futuras atualizações.

## Segurança

- Remoção só de itens selecionados e só dentro de raízes permitidas definidas
  por grupo; qualquer caminho fora delas é recusado pelo motor de limpeza.
- Nunca seguir symlinks para fora da raiz; nunca apagar a raiz em si quando a
  regra é "conteúdo da pasta".
- Encerrar/avisar quando um app relacionado está aberto, se o CleanMyMac fizer
  isso.
- Toda limpeza gera um registro local (o que removeu, quanto, falhas).
- Testes do Core rodam contra árvores de diretórios falsas em pasta temporária,
  nunca contra o disco real.

## Testes: só simulação (decisão do usuário)

Durante o desenvolvimento **nada é limpo de verdade nesta máquina**: nem a
limpeza do CleanMyMac, nem a nossa sobre dados reais.

- Do CleanMyMac, usamos apenas a **análise** (sem clicar em Limpar). Para saber
  *como* ele remove (definitivo vs. Lixo, com admin, como trata assinatura),
  usamos RE estática/REA e textos, não execução da limpeza.
- A **paridade é medida só na análise**: itens encontrados, tamanhos,
  recomendados.
- A **remoção** é testada em árvores falsas em pasta temporária. Para Binários
  Universais e Arquivos de Idioma, testamos em **cópias** de apps em pasta
  temporária (remover, reassinar se for o caso, `codesign --verify`, abrir a
  cópia).
- O motor de limpeza tem um **modo simulação** (dry-run) que lista o que seria
  removido, usado no desenvolvimento contra o disco real.

## Definição de "funcionando 100%"

- Todos os grupos da taxonomia analisam e limpam (limpeza comprovada em
  árvores falsas/cópias e em dry-run contra o disco real).
- **Paridade da análise**: nesta máquina, para cada grupo, os itens encontrados
  e o tamanho batem com a análise do CleanMyMac (feitas em sequência), com
  tolerância pequena para arquivos que mudam entre as execuções. Diferenças
  restantes ficam documentadas e explicadas na especificação do grupo.
- Itens "recomendados" batem com os do CleanMyMac.
- Cópias de apps tratadas por Binários Universais/Idiomas continuam válidas
  (`codesign --verify`) e abrindo.
- Testes do Core passando; app compila sem warnings relevantes.
- UI completa em pt-BR e en.

## Decisões adicionais

Do usuário:
- **Regras e caminhos são fatos técnicos.** Nossas regras podem coincidir com as
  do CleanMyMac (mesmos caminhos/padrões), desde que escritas por nós e
  sustentadas por evidência própria (observação, documentação pública, RE do
  comportamento). Não copiamos arquivos, tabelas ou estruturas de dados deles.
- **Binários Universais seguem o CleanMyMac**: fazemos o que a RE mostrar (quais
  apps pula, se reassina e como). Se houver risco de quebrar o app, o item não
  vem marcado como recomendado.

Do construtor (podem ser revistas):
- **Admin durante a análise**: com Acesso Total ao Disco a maior parte é legível
  sem root. Se a especificação mostrar que algum grupo precisa de root para
  medir, a análise pede a senha uma vez no início, só se esses grupos estiverem
  envolvidos; a limpeza pede de novo. Sem helper permanente na v1.
- **App Management (TCC)**: para alterar bundles de outros apps (Binários
  Universais, Idiomas), o app detecta e orienta o usuário a conceder a
  permissão "Gerenciamento de Apps", como faz com o Acesso Total ao Disco.
- **Grupos vazios nesta máquina** (Usuários Apagados, backups iOS, lixo de
  volume externo, modelos locais…): a paridade fica nas árvores falsas mais a
  evidência de RE. Quando for seguro e reversível, criamos fixtures reais (ex.:
  imagem de disco montada com lixo, pasta de backup falsa) para comparar com a
  análise do CleanMyMac.
- **Versão de referência**: CleanMyMac 5.7.2 (Setapp). Registramos a versão em
  cada especificação; se o Setapp atualizar, revalidamos o que mudou.
- **Grupos fora da taxonomia** (ex.: `UnusedDiskImagesScanning`): entram na v1 só
  se aparecerem no módulo Limpeza do CleanMyMac; caso contrário, ficam
  documentados para módulos futuros.
- **REA**: pacote npm `rea-agents` (https://github.com/morluto/rea) como servidor
  MCP do Claude Code, com Ghidra (Homebrew) + JDK. Se não funcionar, seguimos com
  Ghidra direto + observação + inspeção estática.

## Processo

- Commits pequenos e frequentes (uma etapa curta = um commit), com push para
  `origin main`.
- Ordem sugerida: setup do repo e ferramentas → especificação de RE por
  categoria → Core + testes por grupo → UI das telas → integração → paridade.

## Deixado para quem for construir

- Estrutura exata de pastas/targets, nomes de tipos, estratégia de concorrência
  da análise.
- Mecanismo exato de privilégio (ex.: `osascript ... with administrator
  privileges` vs. Authorization Services), desde que peça a senha uma vez por
  limpeza.
- Desenho dos ícones e da arte das telas, paleta exata.
- Ferramenta de comparação de paridade (script, alvo de teste, etc.).
- Ordem dos grupos dentro de cada categoria, se a RE não deixar claro.
