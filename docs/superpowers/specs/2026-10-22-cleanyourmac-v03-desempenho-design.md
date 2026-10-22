# CleanYourMac v0.3 — Módulo Desempenho (design)

Data: 2026-10-22 · Repo: https://github.com/guigx7/CleanYourMac ·
Antecessores: [v1 — Limpeza](2026-10-20-cleanyourmac-v1-limpeza-design.md),
[v0.2 — Aplicativos](2026-10-21-cleanyourmac-v02-aplicativos-design.md)

## Intenção

Terceiro módulo do CleanYourMac: **Desempenho**, reimplementando a página de mesmo nome do CleanMyMac 5.7.2 com o
mesmo processo (RE clean room, specs com nossas palavras, TDD, paridade nesta máquina, teste real controlado,
release). O usuário pediu para analisar e planejar a parte de Desempenho logo depois da v0.2.

## O que o CleanMyMac mostra (reconhecimento de 2026-10-22, só análise)

Evidência: textos de `PerformanceModule` (98 chaves), símbolos de `PerformanceModule`, `PerformanceScanning`,
`PerformanceService`, `HealthMonitoringCore`, `CleanMyMacLoginItems` (`re-notes/static/`), e a árvore de
Acessibilidade da análise (`re-notes/ax/perf-*`). O `dump-ax` recusa cliques em executar, liberar, diminuir,
reindexar, acelerar, reparar, desativar, remover etc.

- **Intro:** título, subtítulo, três categorias (Tarefas de manutenção, Itens de início de sessão, Itens em segundo
  plano), Analisar.
- **Resultados:** frase de cabeçalho + **Ver Todas as Tarefas** + cartões. Vistos: "Você Tem 4 Itens de Início"
  (Revisar), "5 Tarefas de Manutenção Recomendadas" (Revisar + Executar Tarefas), "9 Itens em Segundo Plano
  Encontrados" (Revisar). Existentes no binário: Liberar RAM, Diminuir Capturas do Time Machine; estados
  "concluído" de cada cartão; estado "não há tarefas recomendadas".
- **Gerenciador de Desempenho** (três seções):
  - **Tarefas de Manutenção:** lista com checkbox, nome, subtítulo opcional ("Até 3,8 GB" no espaço purgável) e
    descrição; rodapé "N Tarefa Selecionada" + **Executar**. Nesta máquina: Acelerar o Mail, Esvaziar Cache do
    DNS, Liberar Espaço Purgável, Reindexar o Spotlight, Reparar Permissões do Disco. No binário também: Liberar
    RAM, Executar Scripts Periódicos, Diminuir Capturas do Time Machine (não apareceram aqui).
  - **Itens de Início:** GlucoTracker, Hidden Bar, Vorssaint, Warp; menu Selecionar; rodapé + **Remover**.
  - **Itens em Segundo Plano:** 9 itens (agentes/daemons do launchd de terceiros, ex.: GoogleUpdater,
    Logi Options+ ×2, LogiRightSight, Setapp e seus auxiliares, um plist do instalador do iStat Menus); rodapé +
    **Remover**.
- Fluxo extra no binário: **Capturas do Time Machine** (remover capturas locais sem afetar os backups).
- Erros previstos no binário: tarefa cancelada, sem pasta do Mail, sem autorização de administrador, tempo
  esgotado; o Acelerar o Mail pede Acesso Total ao Disco.

## Objetivos

1. Fluxo completo: Intro → Análise → Resultados → Gerenciador (3 seções) → ação → Concluído/registro, no visual
   dos outros módulos (gradiente laranja já previsto no `Theme`, arte própria do módulo).
2. **Tarefas de Manutenção** com a mesma lista e as mesmas regras de "recomendada"/"aplicável" do CleanMyMac,
   executadas de verdade (com administrador quando preciso, via ajudante ou senha), com progresso, cancelamento,
   tempo-limite e resultado por tarefa.
3. **Itens de Início** e **Itens em Segundo Plano** com **duas ações** (decisão do usuário):
   - **Desativar** — reversível; o item continua no Mac; lista de desativados com **Reativar**;
   - **Remover** — como o CleanMyMac, mas para o **Lixo** (padrão do projeto desde a v0.2).
4. **Capturas do Time Machine** (listar e remover capturas locais), quando houver.
5. Paridade da análise com o CleanMyMac nesta máquina (tarefas aplicáveis e recomendadas, itens de início e em
   segundo plano).
6. pt-BR e en; commits curtos e frequentes em `main`, com push; release v0.3.0 ao final, com o ok do usuário.

## Não-objetivos

- Monitor de saúde em tempo real, menu na barra, agendamento automático de tarefas.
- Mexer em itens da Apple (`com.apple.*`) ou em serviços do sistema.
- Instalar/atualizar algo (isso é do Atualizador, etapa 2).

## Anti-objetivos

- Desativar ou remover algo que não seja do app/item escolhido; qualquer item `com.apple.*`.
- Deixar o Mac inutilizável: tarefa que trava o sistema, apaga dados do usuário ou desliga serviços essenciais.
- "Otimizações" sem efeito real vendidas como melhoria (cada tarefa precisa fazer algo verificável).
- Copiar código, textos, ícones ou dados do CleanMyMac; não decifrar `info.cmmkb`.

## Decisões do usuário

- Itens de início e em segundo plano: **oferecer Desativar e Remover**.
- **Pode executar as tarefas de verdade** neste Mac durante o desenvolvimento (avisando antes das pesadas, como
  reindexar o Spotlight e liberar espaço purgável). No CleanMyMac continua só a análise.
- Herdadas: caminhos e regras são fatos técnicos; interface pt-BR e en; permissões concedidas pelo usuário;
  remoção vai para o Lixo; o Atualizador/instalação fica para outra etapa.

## Restrições técnicas (o que o macOS permite)

- **Agentes/daemons do launchd:** desativar = `launchctl disable` + `bootout` (reversível com `enable` +
  `bootstrap`); remover = `bootout` + plist para o Lixo. Domínio `gui/<uid>` sem root; `system` pelo ajudante.
  O ajudante ganha a operação de **desativar/reativar** com as mesmas travas das da v0.2 (nunca `com.apple.*`,
  revalidação como root, vínculo com o item).
- **Itens de início antigos** (lista de sessão, `LSSharedFileList`): remover tira da lista (o app fica);
  "desativar" = remover da lista guardando o registro para **Reativar** depois.
- **Itens de início e em segundo plano modernos** (registrados pelo app via `SMAppService`/Gerenciamento de Itens
  em Segundo Plano): não há API pública para outro app ligar/desligar. As ações abrem Ajustes › Itens de Início
  com o guia de permissões (padrão criado na v0.2). A spec de RE deve confirmar como o CleanMyMac os lista.
- **Tarefas** usam ferramentas do sistema; as que exigem root passam pelo ajudante (novas operações tipadas, sem
  shell livre) ou pela senha (AppleScript). Cada tarefa tem tempo-limite e pode ser cancelada.

## Decisões do construtor (podem ser revistas)

- **Paridade × "sem efeito real":** a lista de tarefas e a regra de quando cada uma aparece seguem o CleanMyMac
  (nesta máquina ele mostra só 5 das 8). Cada tarefa faz o que a ferramenta do macOS faz de verdade e a descrição
  é escrita por nós, sem prometer mais do que isso. Se a spec de RE mostrar que o método do CleanMyMac é arriscado
  (ex.: encher o disco para forçar a liberação do espaço purgável), usamos um método seguro equivalente ou a
  tarefa não entra, e a diferença fica em "Divergências conhecidas".
- **Sem APIs privadas** (regra do projeto desde a v0.2). Leitura com ferramentas que vêm no macOS (`launchctl`,
  `sfltool dumpbtm` só para ler, se a spec precisar) é permitida; escrever no banco de Itens em Segundo Plano ou no
  `Envelope Index` do Mail por fora, não (o Acelerar o Mail usa só o que o Mail/macOS oferecem; a spec define).
  Nesta máquina, os 4 itens de início estão na lista de sessão (removíveis/desativáveis por nós) e os 9 em segundo
  plano são plists do launchd (desativáveis/removíveis por nós); só itens modernos (`SMAppService`) caem no "abrir
  Ajustes".
- **O que "Remover" leva:** o plist do launchd e, se houver, o executável auxiliar ligado a ele
  (`/Library/PrivilegedHelperTools/<label>`), as mesmas regras de vínculo da v0.2. Nunca o app dono. Se o app dono
  continuar instalado, a confirmação avisa que ele pode recriar o item e oferece abrir o Desinstalador nele.
- **Lista de desativados:** para o launchd, a fonte é o próprio sistema (`launchctl print-disabled` dos domínios
  do usuário e do sistema, só itens de terceiros); para a lista de sessão, um registro nosso
  (`~/Library/Application Support/CleanYourMac/disabled-login-items.json`) com o necessário para recolocar o item.
  Item desligado por fora (Ajustes) aparece como está no sistema.
- **Simulação:** tudo respeita `CYM_DRY_RUN` (Debug simula por padrão); o teste real usa o Release instalado em
  `/Applications`, como na v0.2.

## Processo

- Specs em `docs/re/specs/performance/` (uma por tarefa ou grupo; itens de início; itens em segundo plano;
  capturas do Time Machine; tela de resultados), escritas por subagentes a partir da evidência.
- Baseline de paridade da análise (AX) e comparação com `cym performance --json`.
- Core + testes → ajudante (operações novas) → UI → paridade → teste real (tarefas reais avisando antes das
  pesadas; desativar/reativar/remover com itens de teste criados por nós) → revisão final → release v0.3.0.

## Deixado para quem for construir

- Nomes de tipos e organização em `Core/` e `App/`; como reaproveitar `CleanEngine`, `AppsSelection`, o guia de
  permissões e o ajudante.
- Como medir "recomendada" quando a regra depender de dados do sistema (a spec decide).
- Arte e paleta do módulo (laranja, já em `Theme`).
