# Acúmulos: Downloads (`downloads`)

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83), Apple Silicon (arm64), 2026-10-23.
Só análise estática (`DownloadsScanning`, em Objective-C; `SharedObjcUtils`, onde mora o leitor do
Safari; `OrganizeModule`), dump AX (`re-notes/ax/clutter-20261023/downloads.txt`) e leitura do
disco (`ls`, `xattr`, `mdls`, sem abrir nenhum histórico). Nada foi clicado no CleanMyMac.

Legenda: **[E*n*]** = evidência (lista no fim). **(inferência)** = conclusão nossa.

## 1. De onde vêm os itens

### O que o CleanMyMac faz
**Não** olha `kMDItemWhereFroms` nem o `com.apple.quarantine` dos arquivos: lê o **histórico de
downloads de cada app** e mantém só os arquivos que ainda existem no disco [E1][E2].
Três tarefas (`DownloadsScanTasksFactory.chromeDownloadsTask/safariDownloadsTask/
slackDownloadsTask`), uma por app [E1]:

| App | Bundle ID | Fonte | Campos usados |
|---|---|---|---|
| Google Chrome | `com.google.Chrome` | `~/Library/Application Support/Google/Chrome/` → arquivo `Local State` (JSON; `profile` → `info_cache`, para listar os perfis e o nome da conta) e, em cada perfil, o banco SQLite **`History`**, consultado com `SELECT current_path, start_time, end_time, received_bytes, total_bytes FROM downloads` (pela biblioteca FMDB) | caminho, início, fim, bytes recebidos, bytes totais |
| Safari | `com.apple.Safari` | `~/Library/Safari/Downloads.plist`, lista `DownloadHistory` (leitor `CMSafariDownloadsHistoryDataController` em `SharedObjcUtils`) | `DownloadEntryPath`, `DownloadEntryPostPath`, `DownloadEntryProgressBytesSoFar`, `DownloadEntryProgressTotalToLoad`, `DownloadEntryDateAddedKey`, `DownloadEntryIdentifier` |
| Slack | `com.tinyspeck.slackmacgap` | `~/Library/Application Support/Slack/storage/root-state.json` ou, na versão da App Store, `~/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Application Support/Slack/storage/` (há leitura de formato antigo e "novo formato", em `Library` e em `Containers`) | por download: caminho, início, fim, estado, progresso, pausado; por equipe: `team_id`, `team_name` (chaves `slack-downloads`, `slack-teams`, `workspaces`) |

- O banco do Chrome é **copiado para a pasta temporária** antes de abrir (`copyItemAtPath:toPath:`,
  `NSTemporaryDirectory`), para não brigar com a trava do navegador aberto (inferência pela
  presença das duas chamadas) [E1].
- **Permissões:** `~/Library/Safari/Downloads.plist` é protegido pelo TCC; sem Acesso Total ao
  Disco o grupo do Safari fica vazio. Nesta máquina, o nosso processo sem FDA recebeu "você não
  tem permissão" ao tentar ler o plist [E3].
- **O que entra** (inferência pelos nomes): só downloads **concluídos**
  (`fullyDownloaded`; no Chrome, `received_bytes` = `total_bytes`; no Slack, estado
  `completed` e não pausado) cujo arquivo **ainda existe** (`fileExistsAtPath:`); caminhos
  repetidos no histórico viram um item só (`compareAndRemoveDuplicate(s):`) [E1].
- **Exclusões:** a base de conhecimento do app pode ignorar um app, uma conta ou um caminho
  (`shouldIgnoreApplication:`, `shouldIgnoreAccount:ofApplication:`, `shouldIgnoreURL:`); o
  conteúdo da base não foi decifrado [E1].
- **Pasta:** não há filtro por pasta; vale o caminho gravado no histórico (observado: todos os
  itens do Chrome estavam em `~/Downloads`) [E4].
- `NSWorkspace.runningApplications` é consultado (inferência: saber se o app está aberto; o
  efeito não foi lido).

### Prova nesta máquina (só leitura)
- `~/Downloads`: 457 arquivos com o agente "Chrome" no `com.apple.quarantine`, 49 "WhatsApp",
  10 "Preview", 221 sem atributo [E3]. Os de WhatsApp/Preview não entram em grupo nenhum, porque
  não há leitor para esses apps.
- Não há Slack instalado (`~/Library/Application Support/Slack/storage` não existe), mas o grupo
  do Slack aparece com **0 KB** [E4].

## 2. Agrupamento
- `DownloadsApplicationModel` (app: `applicationBundleID`, `name`, `date`) →
  `DownloadsAccountModel` (conta/perfil/equipe: `accountID`, `title`, `items`) →
  `DownloadsItemModel` (`url`, `name`, `size`, `date`, `isAutoselected`) [E1].
  - Chrome: uma conta por **perfil** (nome da conta do `info_cache`); identificador
    `ChromeDownloads-<perfil>-<…>`.
  - Slack: uma conta por **equipe** (workspace).
  - Safari: uma conta só (inferência).
- **Na tela** [E4]: categoria "Downloads" ("Arquivos que você usa apenas uma vez podem se acumular
  nos downloads…") com um grupo por app — **Google Chrome**, **Slack**, **Safari** —, cada um com
  o total e a frase "Revise os arquivos que você baixou com o %@"; os títulos internos são
  "Downloads do Google Chrome/Safari/Slack". Observado: Chrome 591 MB, Slack 0 KB, Safari 0 KB.
  Linhas: caixa, nome, caminho (`guigx › Downloads`), tamanho. Ordem por tamanho.
- Contagem por conta: "%d item" / "%d itens" (`downloads_account_items_count`).

## 3. Marcação automática
- `_kMoreThanMonthAgo = 30` (dias) e `isAutoselected` nos modelos [E1][E5] (inferência: vêm
  marcados os downloads concluídos há mais de 30 dias). No Gerenciador a seleção começa vazia
  ("Selecionar: Nenhum") [E4].

## 4. Cartão
- **"%@ de Downloads do %@ Encontrados"** (1º `%@` = tamanho; 2º = nome do app), texto "Revise e
  remova os downloads desnecessários para recuperar um espaço significativo"; após a limpeza
  "%@ de Downloads do %@ Removidos" [E5]. Observado: **"591 MB de Downloads do Google Chrome
  Encontrados"** [E4]. Um cartão só, com o app de maior total (inferência: Slack e Safari tinham
  0 KB).

## 5. Para o CleanYourMac (forma proposta)
- **Fonte principal: o atributo `com.apple.quarantine`** dos arquivos em `~/Downloads` (e em
  `~/Desktop`, opcional). O 3º campo é o nome do agente ("Chrome", "Safari", "Slack", …). É
  leitura de atributo estendido (`getxattr`), sem FDA e sem abrir bancos de outros apps. Grupo =
  agente; ícone pelo bundle ID conhecido; agentes sem bundle conhecido vão para "Outros apps".
- **Complemento:** `kMDItemWhereFroms` (via `MDItemCopyAttribute`) para mostrar a origem
  (domínio) na linha, **sem** guardar nem enviar a URL.
- Ler o `History` do Chrome / o `Downloads.plist` do Safari fica como modo opcional de paridade
  (o plist exige FDA; o banco do Chrome é copiado para o scratch antes de abrir, só leitura).
- Grupos vazios **não** aparecem (divergência: o CleanMyMac mostra Slack/Safari com 0 KB).
- Marcação automática: baixados há mais de 30 dias **e** não abertos desde então
  (`kMDItemLastUsedDate` nulo ou anterior ao download).
- Remoção: Lixo.

## requiresAdmin
- Análise: não (mas o Safari precisa de Acesso Total ao Disco no CleanMyMac).
- Limpeza: não.

## Evidências
- **E1** — `re-notes/static/DownloadsScanning/strings.txt` e `symbols.txt`: classes
  `CMChromeDownloadsHistoryDataController`, `CMSlackDownloadsHistoryDataController`,
  `CMChromeDownloadsScanTask`, `CMSafariDownloadsScanTask`, `CMSlackDownloadsScanTask`; strings
  `Application Support/Google/Chrome`, `Local State`, `History`, `info_cache`, `profile`, a
  consulta SQL citada, `Application Support/Slack/storage`,
  `Application Support/Slack/storage/root-state.json`,
  `Containers/com.tinyspeck.slackmacgap/Data/Library/Application Support/Slack/storage`,
  `slack-downloads`, `slack-teams`, `workspaces`, `team_id`, `team_name`,
  `fetchNewFormatDownloadsHistoryFromContainersWithError:`,
  `fetchDownloadsHistoryFromLibraryWithError:`, `fullyDownloaded`, `fileExistsAtPath:`,
  `compareAndRemoveDuplicate(s):`, `copyItemAtPath:toPath:error:`, `runningApplications`,
  `shouldIgnore…`, `ChromeDownloads-%@-%@`, `_kMoreThanMonthAgo`; símbolos dos modelos Swift
  `DownloadsApplicationModel`, `DownloadsAccountModel`, `DownloadsItemModel`.
- **E2** — `dyld_info -fixups` de `DownloadsScanning`: importa `FMDB/FMDatabase`,
  `SharedObjcUtils/CMSafariDownloadsHistoryDataController` e as chaves
  `_CMSafariDownloadsHistoryKey{Path,PostPath,ProgressBytesSoFar,TotalToLoad}`; `strings` de
  `SharedObjcUtils`: `Downloads.plist`, `DownloadHistory`, `DownloadEntry*`. Nenhuma importação
  de `kMDItemWhereFroms` nem leitura de `com.apple.quarantine`.
- **E3** — `xattr -p com.apple.quarantine` (contagem por agente) e `plutil -p
  ~/Library/Safari/Downloads.plist` (negado pelo TCC), só leitura.
- **E4** — `re-notes/ax/clutter-20261023/downloads.txt` e `results.txt`.
- **E5** — `_kMoreThanMonthAgo` em `__TEXT,__const` @0xe648 = 30 (inteiro de 64 bits);
  `localizable-pt-BR.json`: `downloads_*`, `tile_downloads_*`, `chrome_title`, `safari_title`,
  `slack_title`; `Localizable.stringsdict`: `downloads_account_items_count`.

## Divergências conhecidas
- Fonte: atributo de quarentena (nós) × histórico de cada app (CleanMyMac). Nós achamos também
  downloads de apps sem leitor dedicado; o CleanMyMac acha arquivos baixados para fora de
  `~/Downloads` que o histórico conhece.
- Grupos vazios escondidos.

## Dúvidas em aberto
- O tamanho exibido: `Godot_v4.7.2-stable_macos.universal.zip` aparece com **185 MB** em
  Downloads, mas tem 170.622.178 bytes (171 MB, valor que o Fundo do Baú mostra). Hipóteses: duas
  entradas do histórico somadas antes da deduplicação, ou tamanho vindo do banco do Chrome.
- Efeito de `runningApplications` (avisar? pular?).
- Regra exata do `isAutoselected` (30 dias contados de `end_time`/`DateAdded`?).
