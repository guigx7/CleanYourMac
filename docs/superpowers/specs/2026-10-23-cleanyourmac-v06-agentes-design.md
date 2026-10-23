# CleanYourMac v0.6 — Sobras de agentes de IA (design)

Data: 2026-10-23 · Antecessores: v0.1–v0.5.

## Intenção

Os agentes de IA (Claude Code, Codex, Cursor, Gemini e outros) criam muitas **worktrees** do git e guardam **sessões**
que se acumulam. O usuário limpa isso à mão com frequência, e o medo dele é **apagar trabalho que ainda não entrou no
remoto**. A feature resolve a dor sem esse risco: das worktrees ela tira só o que se recria sozinho (`node_modules` e
pastas de build); o código, os commits e as alterações sem commit **nunca** são tocados. Ela também limpa as sessões
antigas dos agentes.

Não é uma reimplementação do CleanMyMac: ele não tem essa função (o grupo de IA dele, já feito na v0.1 em
`docs/re/specs/ai-agents-junk.md`, cobre só caches, logs e versões). Por isso não há etapa de RE nem de paridade.
Valem as regras de sempre do projeto: TDD, teste real só com itens criados por nós e release só com o ok do usuário.

## O que a máquina do usuário mostrou (2026-10-23, só leitura)

- **Worktrees:** 9 só no `organizacao10x`, em três tipos de lugar: pastas irmãs do repositório (`org10x-pr495`…),
  `<repo>/.claude/worktrees/<nome>` e `~/.claude/jobs/<id>/tmp/wt-sim` (6,8 GB). Juntas passam de 50 GB, quase tudo
  `node_modules` (1,4 GB numa só).
- Quase todas têm alterações sem commit, e "mergeada" depende da branch base (`develop` × `main`). Isso confirma a
  decisão de **não apagar worktrees nem branches**.
- **Sessões:** Claude Code com 113 conversas, 72 com mais de 7 dias (272 MB); Codex com 171 sessões, 149 com mais de 7
  dias. As do OpenCode ficam num banco SQLite próprio.

## Objetivos

1. Achar todas as worktrees **ligadas** (não o checkout principal) dos repositórios do usuário, onde quer que estejam.
2. Em cada worktree, listar as pastas recriáveis com o tamanho: `node_modules` e as pastas de build (lista abaixo).
3. Achar as sessões com mais de 7 dias dos agentes conhecidos, com quantidade e tamanho por agente.
4. Fluxo de **um clique** igual ao dos outros módulos: Intro → Analisar (com Parar) → Resultados com cartões e botão de
   limpar → Gerenciador com seções, seleção e rodapé → remoção → Concluído com registro.
5. Remover para o **Lixo**, revalidando cada item antes.
6. Textos em pt-BR e en, commits curtos em `main`, release só com o ok do usuário.

## Não-objetivos

- Apagar worktrees, branches ou o registro de worktrees do git (`git worktree remove`/`prune`).
- Saber o que está no remoto (precisaria de login no GitHub/GitLab).
- Limpar `node_modules`/build do checkout principal ou de projetos que não são worktrees (decisão do usuário: "só de
  worktrees").
- Editar bancos de dados dos agentes (ex.: `opencode.db`, o `thread_history` do Codex).

## Anti-objetivos (seria um fracasso mesmo funcionando)

- Remover qualquer arquivo rastreado pelo git ou alteração sem commit.
- Quebrar um agente que está rodando agora (apagar o `node_modules` de uma worktree em uso, ou a sessão aberta).
- Apagar memórias, configurações, skills, plugins ou o histórico de comandos dos agentes (ex.: `~/.claude/projects/*/memory`,
  `~/.claude/settings.json`, `~/.claude/history.jsonl`).

## Decisões do usuário

- Das worktrees, só `node_modules` **e as pastas de build**.
- Só worktrees; o projeto principal fica de fora.
- Sessões com mais de 7 dias entram.
- Precisa servir para várias IAs, não só para o Claude.

## Decisões do construtor (podem ser revistas)

- **Lugar no app:** módulo novo na barra lateral, **"Agentes de IA"**, depois de Acúmulos, com o mesmo fluxo e o mesmo visual
  dos outros. A Limpeza continua cuidando dos caches de IA, como hoje.
- **Achar os repositórios sem rodar o git:** varrer a pasta pessoal com as exclusões de sempre (`~/Library` fica de fora,
  exceto as pastas de agentes, `node_modules` não é descido, ocultos só os conhecidos: `.claude`, `.codex`…) atrás de
  pastas `.git`. Em cada uma, ler `.git/worktrees/<nome>/gitdir`: o conteúdo aponta para o `.git` (arquivo) da worktree
  ligada. Entram as worktrees cujo caminho existe e cujo arquivo `.git` aponta de volta para aquele repositório. Também
  entram diretórios-raiz conhecidos dos agentes (`~/.claude/jobs/*/tmp/*`, `<repo>/.claude/worktrees/*`,
  `~/.codex/worktrees/*` se existir…). Uma pasta só é tratada como worktree se tiver o arquivo `.git` com `gitdir:`.
- **Pastas recriáveis**, procuradas até 4 níveis dentro da worktree (monorepos): `node_modules` (sempre), e as de build
  `.next`, `.nuxt`, `.svelte-kit`, `.turbo`, `.parcel-cache`, `.vite`, `.angular/cache`, `.expo`, `dist`, `build`, `out`,
  `coverage`, `.output`, `target` (Rust), `.gradle`, `DerivedData`, `__pycache__`, `.pytest_cache`, `.mypy_cache`,
  `.venv`/`venv`.
  - **Regra de segurança:** uma pasta de build só entra se o git a ignora (`git check-ignore`). Exceção: `node_modules`,
    que entra mesmo sem `.gitignore`. Se não houver git utilizável na máquina (sem Command Line Tools, o `/usr/bin/git`
    abre um instalador), entra **só** o `node_modules`, e a tela avisa.
  - Também ficam de fora pastas que contêm algum arquivo rastreado (confirmado por `git ls-files <pasta>` vazio). Pastas
    dentro de outra recriável não são listadas à parte.
- **Worktree em uso:** worktree com algum arquivo de fora das pastas recriáveis modificado nas últimas **24 h** aparece,
  mas desmarcada e com o aviso "em uso recentemente". O cartão de um clique só leva as paradas há mais de 24 h. Na hora de
  remover, se o agente voltou a mexer (data nova), o item é recusado.
- **Sessões por agente** (só arquivos; com mais de 7 dias pela data de modificação):
  - **Claude Code:** `~/.claude/projects/<projeto>/<sessão>.jsonl` e a pasta `<sessão>/` ao lado, se houver (subagentes). Também
    entram os restos da mesma sessão em `~/.claude/todos`, `~/.claude/file-history/<sessão>` e
    `~/.claude/session-env/<sessão>`, se existirem. **Nunca** a pasta `memory/` de cada projeto nem `history.jsonl`.
    `~/.claude/jobs/<id>` parado há mais de 7 dias entra como sessão (é onde fica o `wt-sim` de 6,8 GB). Se ele tiver uma
    worktree dentro, o node_modules dela é contado uma vez só.
  - **Codex:** `~/.codex/sessions/AAAA/MM/DD/*.jsonl` (e `~/.codex/archived_sessions` se existir). Antes de implementar,
    conferir se apagar o arquivo deixa o Codex com entrada quebrada no `thread_history_*.sqlite`. Se deixar, o Codex fica
    de fora e isso vira divergência anotada.
  - **Gemini CLI:** `~/.gemini/tmp/<hash>/chats/*.json` e `checkpoints`, se existirem.
  - **Outros** (OpenCode, Cursor, Copilot): ficam de fora nesta versão, porque guardam as conversas em bancos ou em
    formatos não confirmados. A tela informa "não suportado ainda".
  - A lista de agentes e caminhos fica num arquivo de regras (JSON, como as regras da Limpeza), para crescer sem mexer em
    código.
- **Remover:** tudo para o **Lixo** (`FileManager.trashItem`, que é um `rename` rápido no mesmo volume, mesmo com milhares de
  arquivos). O espaço só volta ao esvaziar o Lixo, e a tela de conclusão diz isso. Revalidação por item, como no Acúmulos:
  ainda existe, não virou link, nenhuma pasta do caminho virou link, a data de modificação é a mesma, e continua dentro da
  worktree ou da pasta do agente analisada.
- **Seleção e um clique:**
  - **Cartões:** "node_modules e builds em N worktrees paradas · X GB" e "N sessões com mais de 7 dias · Y MB" (um cartão
    por agente com sessões, ou um só com o detalhe). O botão do cartão já remove o que é seguro, depois da confirmação.
  - **Gerenciador:** seções "Worktrees" (grupo por repositório → worktree → pastas, com a branch, a data da última mudança,
    o caminho e se tem alterações sem commit, só como informação) e "Sessões" (grupo por agente → projeto → sessões, com
    data e tamanho).
- **Simulação:** `CYM_DRY_RUN` no Debug, como sempre. Teste real só com uma worktree e sessões falsas criadas por nós
  (prefixo `io.github.guigx7.cymtest`), com o ok do usuário.
- **CLI:** `cym agents [--json]` só de leitura, para diagnóstico.

## Decisões tomadas depois da revisão do construtor (minhas, a conferir pelo usuário)

1. **Jobs do Claude Code (`~/.claude/jobs/<id>`) com worktree dentro nunca saem inteiros.** A worktree entra só pela seção
   Worktrees (node_modules e builds), como qualquer outra. O job só sai como sessão se ao mesmo tempo:
   - não tiver nenhuma worktree ligada nem pasta `backup/` dentro;
   - o estado (`state.json`) não estiver ativo (`blocked`, `running`, `waiting`… ficam);
   - estiver parado há mais de 7 dias.

   O cartão de um clique, portanto, **não** leva os 6,8 GB do `wt-sim` como sessão; leva só o node_modules/build dele.
2. **Estado ativo por agente:** cada agente do catálogo pode ter um marcador de "ainda vivo" (Claude Code: `state.json` dos
   jobs). Sessão com marcador ativo fica de fora, seja qual for a idade.
3. **Uma sessão do Claude Code é um item só:** o `.jsonl` mais a pasta de subagentes, `todos`, `file-history/<id>` e
   `session-env/<id>` do mesmo id. A idade é a data mais nova do conjunto, e a revalidação confere essa mesma data. Restos
   órfãos (sem `.jsonl`) com mais de 7 dias entram como "restos de sessões já apagadas".
4. **Referências quebradas:** apagar a sessão faz ela sumir do `/resume`, que é o efeito pedido (o histórico de comandos
   `history.jsonl` nunca é tocado). O usuário já aceitou isso ("resto ok"); a tela de confirmação diz "não dá mais para
   retomar essas conversas". Para o Codex vale o mesmo critério. Se o `thread_history_*.sqlite` só ficar com uma entrada que
   não abre, é aceitável. O Codex só fica de fora se o app dele quebrar ao abrir, e isso tem que ser conferido antes de
   implementar a parte dele.
   - **Conferência do Codex (2026-10-23, só leitura, numa cópia):** `~/.codex/state_5.sqlite` tem a tabela `threads`, com 171
     conversas. Cada uma guarda o `rollout_path` do seu `.jsonl` em `~/.codex/sessions`, e hoje todos os arquivos existem.
     Também há um `session_index.jsonl`. Apagar o `.jsonl`, portanto, deixa a conversa listada no Codex sem o conteúdo.
     Ainda não sabemos se o Codex mostra um erro, esconde a conversa ou quebra a lista. Isso exige um teste com uma sessão
     falsa nossa, com o ok do usuário. Até lá o Codex fica, e a confirmação avisa que "o Codex pode continuar listando
     essas conversas".
5. **Catálogo em Swift**, no padrão do `AICatalog` que já existe (`Core/Sources/CleanYourMacCore/Scanners/AIToolsScanner.swift`),
   e não em JSON: o mesmo tipo de regra fica no mesmo tipo de lugar. Ele guarda os caminhos de sessões, os marcadores de
   estado e as raízes de worktrees de cada agente.
6. **Só dentro da pasta pessoal.** Worktree cujo caminho cai fora de `~` (`/tmp`, `/var/folders`, outro volume) fica de fora.
   Worktree **órfã** (achada pelas raízes dos agentes, com o repositório principal sumido ou o `gitdir` quebrado) entra só
   com o `node_modules`, como no caso "sem git", com o aviso "repositório principal não encontrado".

## O que fica para o construtor

- A ordem e o texto dos cartões, a arte do módulo, a cor e o ícone.
- Como medir os tamanhos de forma rápida (pastas grandes: reaproveitar o medidor da Lupa de Espaço).
- Se roda o `git check-ignore` em lote (`--stdin`) por worktree.
- Como conferir "em uso nas últimas 24 h" sem varrer a worktree inteira (ex.: data do índice `.git` da worktree, mais as
  datas de primeiro nível).

## Riscos

- Algum agente usar `node_modules` com conteúdo à mão (pacote editado localmente): fica coberto pela regra "nada
  rastreado"; um pacote editado e não rastreado se perde, mas vai para o Lixo e dá para recuperar.
- Formato das sessões mudar entre versões dos agentes: os caminhos ficam nas regras em JSON e há testes com fixtures.
