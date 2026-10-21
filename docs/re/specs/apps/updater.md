# Atualizador (`appUpdates`, etapa 1)

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83). Reconhecimento AX de
2026-10-21 (`re-notes/ax/apps-Atualizador-*`). Consultas públicas feitas em
2026-10-21 para conferir o nosso desenho.

## Visão geral

### O que o CleanMyMac faz
- Monta uma lista de **candidatos** a partir de duas fontes locais
  (`UpdaterScanOptions` = `mas` | `sparkle`) [E1]:
  - apps da Mac App Store (`isFromAppStore`, recibo em
    `Contents/_MASReceipt/receipt`) [E2];
  - apps que usam Sparkle: um app conta como "Sparkle" quando o `Info.plist`
    tem **qualquer uma** de 13 chaves do Sparkle (`SUFeedURL`, `SUPublicEDKey`,
    `SUAllowedURLSchemes`, `SUAllowsAutomaticUpdates`, `SUAutomaticallyUpdate`,
    `SUBundleName`, `SUDefaultsDomain`, `SUEnableAutomaticChecks`,
    `SUEnableJavaScript`, `SUEnableSystemProfiling`, `SURelaunchHostBundle`,
    `SUScheduledCheckInterval`, `SUShowReleaseNotes`) ou embute
    `Contents/Frameworks/Sparkle.framework` [E3]. O feed vem do `Info.plist` ou
    das preferências do próprio app (há um acessor de preferências do usuário e
    um campo `feedURLPath`) [E3]. Há um caso especial para
    `com.mediaatelier.grandtotal` [E3].
- Com o mesmo bundle ID instalado em mais de um lugar, os caminhos são
  ordenados e fica a cópia de **maior versão** [E4].
- Envia os candidatos ao **servidor da MacPaw** (`/api/v1/apps/check`). Por app
  vão bundle ID, versão, versão curta, tipo de instalação, canal, URL do feed
  Sparkle e o ID da loja; também vão versão do sistema, arquitetura, idioma e
  modelo. A resposta traz a última versão (e a curta), a data, as novidades, o
  tamanho, o fluxo de atualização, a importância, o logo e as capturas [E5].
  **A comparação é feita no servidor**; o app só mostra o que voltou.
- Atualizações do macOS: outra consulta ao mesmo servidor (`/api/v1/os/check`)
  com o modelo (`hw.model`) e a versão do sistema [E6]. Não usa
  `softwareupdate`.
- Para instalar, ele usa o Sparkle embutido, controlando o updater do app-alvo
  (programático), e a App Store por APIs privadas (CommerceKit, código derivado
  do `mas`) [E7]. Quando não dá (`canBeUpdatedProgrammatically` falso), mostra
  um aviso com um botão que abre o próprio app, a App Store ou os Ajustes do
  Sistema [E8].

**Não podemos usar** o servidor da MacPaw nem as APIs privadas (design).
Logo, o desenho abaixo é nosso, com fontes públicas, e a lista **pode não bater
100%** com a dele.

## Locais varridos (candidatos)
- Os apps do inventário do Desinstalador (`inventory.md`), exceto apps de
  sistema protegidos (`/System/Applications`, com selo da Apple), que só
  entram pela fonte macOS.
- Por app, lemos do `Info.plist`: `CFBundleIdentifier`,
  `CFBundleShortVersionString`, `CFBundleVersion`, `LSMinimumSystemVersion`,
  `SUFeedURL` e a presença das chaves Sparkle acima. Também lemos a presença de
  `Contents/_MASReceipt/receipt` e de `Contents/Frameworks/Sparkle.framework`.
- Duplicatas (mesmo bundle ID): fica a cópia de maior versão (regra de
  comparação abaixo). Com versões iguais, fica o primeiro caminho em ordem
  alfabética, como no CleanMyMac [E4].
- Homebrew: `/opt/homebrew/Caskroom` e `/usr/local/Caskroom`. Cada pasta
  `<token>/<versão>/` diz que o cask `<token>` está instalado naquela versão.

## Fontes (nosso desenho)

### F1: App Store (apps com recibo)
- Requisição: `GET https://itunes.apple.com/lookup?bundleId=<id>&entity=macSoftware&country=<cc>`.
  Vai só o bundle ID, um por app, ou vários separados por vírgula, até 50 por
  requisição. `<cc>` = região do usuário (`Locale.current.region`, em
  minúsculas). Sem resultado na região, tentamos `us` uma vez.
- Campos usados de `results[0]`: `bundleId`, `kind`, `version`,
  `currentVersionReleaseDate` (ISO 8601), `releaseNotes`, `fileSizeBytes`
  (string com o número), `trackId`, `trackViewUrl` e `minimumOsVersion`.
- **Validação**: `bundleId` igual ao instalado, sem diferenciar maiúsculas, e
  `kind == "mac-software"`. Qualquer outro `kind` (ex.: `software`, de iOS)
  torna o resultado **não confiável**. Caso real nesta máquina: o WhatsApp
  (`net.whatsapp.WhatsApp`) devolve um app de iOS com outra versão [E12].
- Compara `version` (loja) com `CFBundleShortVersionString` (instalado).
- `minimumOsVersion` maior que o macOS atual → não gera item (a loja não
  ofereceria).

### F2: feed do próprio app (Sparkle)
- URL: `SUFeedURL` das preferências do app (`~/Library/Preferences/<bundleID>.plist`,
  ou o domínio em `SUDefaultsDomain`), se houver; senão, a do `Info.plist`.
  Esquemas aceitos: `https` e `http`. A etapa 1 só lê o feed. Apps Sparkle sem
  URL de feed legível (ex.: ChatGPT, que define o feed em tempo de execução)
  **não** geram consulta [E13].
- Formato (documentação pública do Sparkle, *Publishing an update*): RSS 2.0
  com o namespace `http://www.andymatuschak.org/xml-namespaces/sparkle`. Para
  cada `<item>`:
  - versão de máquina: `sparkle:version`, como elemento filho do `item` (Sparkle
    2) ou atributo do `enclosure` (Sparkle 1). Comparamos com
    `CFBundleVersion`;
  - versão legível: `sparkle:shortVersionString` (elemento ou atributo), só
    para exibição;
  - sem `sparkle:version`, o item é **não confiável** e é ignorado. O Sparkle 1
    tentava tirar a versão do nome do arquivo; nós não fazemos isso;
  - `sparkle:minimumSystemVersion` / `sparkle:maximumSystemVersion`: item fora
    da faixa do macOS atual é descartado;
  - `sparkle:hardwareRequirements` (ex.: `arm64`): descartado se a máquina não
    atender;
  - `sparkle:channel`: itens **com** canal são descartados, porque só o próprio
    app sabe em que canal o usuário está. Itens sem canal são o canal padrão;
  - `enclosure` com `sparkle:os` diferente de `macos` é descartado;
  - `sparkle:deltas` (atualizações delta) é ignorado. Usamos o `enclosure`
    completo;
  - `sparkle:informationalUpdate` (sem download) é aceito para exibir; o botão
    abre o `link` do item;
  - `sparkle:criticalUpdate` vira só uma marcação no modelo (sem selo na v0.2);
  - `sparkle:phasedRolloutInterval` é ignorado (mostramos assim que publicado);
  - `pubDate` (RFC 822) é a data;
  - novidades: `description` (HTML) ou o link de `sparkle:releaseNotesLink`. O
    link não é baixado na análise: só abre no clique;
  - tamanho: atributo `length` do `enclosure`.
- Escolha: entre os itens válidos, o de maior `sparkle:version` (regra abaixo).
  Gera item só se for maior que `CFBundleVersion`.
- Para a etapa 2, o modelo já guarda `enclosure url`, `sparkle:edSignature`,
  `SUPublicEDKey` do app e o tipo de instalação (`sparkle:installationType`).

### F3: Homebrew
- Catálogo: `GET https://formulae.brew.sh/api/cask.json` (cerca de 2 MB com
  gzip; uns 19 MB sem compressão), baixado **inteiro**. Nenhum dado de app sai da
  máquina. Fica em cache em `~/Library/Caches/<nosso bundle ID>/` por 24 h,
  revalidado com `ETag`/`If-None-Match`. Comparação 100% local.
- Campos usados: `token`, `name`, `version`, `artifacts` (objetos com a chave
  `app`, uma lista de nomes `X.app`, e `target` opcional), `auto_updates`,
  `homepage`, `url`, `depends_on.macos`, `deprecated` e `disabled`.
  `bundle_short_version`/`bundle_version` são **ignorados** (podem estar
  atrasados em relação a `version`; ex.: no Chrome, 155.x × 156.x em
  2026-10-21) [E14].
- Casamento cask ↔ app: o nome do bundle instalado (`Visual Studio Code.app`)
  precisa ser igual a um nome em `artifacts[].app`, ou ao último componente de
  `target`. Nome ambíguo (dois casks com o mesmo `.app`) → não casa.
- Quando vale (design):
  - o app está no Caskroom (o token casou e existe `Caskroom/<token>/`): fonte
    principal desse app, comparando a **versão da pasta do Caskroom** com
    `version` do cask (as duas no formato do Homebrew);
  - o app **não** tem F1 nem F2: comparação de `CFBundleShortVersionString` com
    a parte de `version` antes da primeira vírgula;
  - fica de fora: `auto_updates == true`, `deprecated`/`disabled`,
    `version == "latest"` e casks cujo `depends_on.macos` exclui o sistema atual.
- Sem tamanho nem novidades (o catálogo não traz). Data: não há; o campo fica
  vazio.

### F4: macOS
- **Sem root e na hora:** ler `/Library/Preferences/com.apple.SoftwareUpdate.plist`
  (legível por todos). A chave `RecommendedUpdates` é uma lista de dicionários com
  `Display Name`, `Display Version`, `Identifier`, `Product Key` e, nas
  atualizações do sistema, `MobileSoftwareUpdate = true`. Também lemos
  `LastSuccessfulDate` (quando o sistema checou pela última vez) [E15].
- Se `LastSuccessfulDate` tiver **mais de 24 h** ou não existir, rodamos
  `/usr/sbin/softwareupdate --list` **em segundo plano** (sem root), com limite
  de 60 s e sem bloquear a análise. Nesta máquina ele levou **5,7 s** e
  devolveu as mesmas 3 entradas do plist, com tamanho (`Size: …KiB`) [E15].
  Quando termina, o grupo é atualizado. Se passar do limite, ficamos com o plist.
- Itens: um por entrada. Entradas com `MobileSoftwareUpdate` (macOS) e
  apps da Apple atualizados pelo sistema (ex.: Safari) entram todas. A
  atualização de **versão principal** (ex.: 27.x sobre 26.x) entra também, mas
  marcada no modelo como `major`, para a UI poder separá-la.

## Regra de comparação de versões
Uma única função `compareVersions(a, b) -> menor | igual | maior | nãoConfiável`:

1. **Normalizar**: tirar espaços nas pontas e um `v`/`V` inicial. No Homebrew,
   usar só o que vem antes da primeira `,` e trocar `_` por `.`.
2. **Não confiável** (nenhum item é gerado, e a falha vai para o registro) se
   qualquer lado:
   - estiver vazio, não tiver dígitos, for `latest` ou passar de 64
     caracteres;
   - tiver espaços no meio ou caracteres fora de `[0-9A-Za-z.+-]`;
   - tiver forma diferente da do outro: um lado começa com um número de 8 ou
     mais dígitos (versão por data, ex.: `20261020`) e o outro não; ou o
     primeiro número de um lado é mais de 100 vezes o do outro (ex.:
     `2026.10` × `1.24`);
   - for pré-lançamento (`alpha`, `beta`, `b<n>`, `rc`, `preview`, `pre`, `dev`,
     `nightly`, `canary`) do lado **remoto** sem que o instalado também seja.
     Nunca oferecemos beta a quem usa versão estável.
3. **Comparar** por segmentos, no mesmo algoritmo do comparador padrão do
   Sparkle (público, licença MIT), que é também o que o CleanMyMac usa
   localmente [E4][E9]:
   - quebrar a string em segmentos de três tipos: número (dígitos seguidos),
     texto (outros caracteres seguidos) e ponto (`.`, sempre sozinho);
   - comparar segmento a segmento: número × número pelo valor; texto × texto
     em ordem lexicográfica; com tipos diferentes, **número > ponto** e
     **qualquer coisa > texto** (`1.0 > 1.0b1`);
   - se todos os segmentos em comum forem iguais, o mais longo é maior, salvo
     quando o primeiro segmento a mais é texto (`1.0 > 1.0a`);
   - números com mais de 18 dígitos são comparados como texto alinhado à
     direita, para não estourar.
4. **Par de campos** (sempre o mesmo tipo de versão dos dois lados):
   - App Store: `version` × `CFBundleShortVersionString`;
   - Sparkle: `sparkle:version` × `CFBundleVersion`;
   - Homebrew no Caskroom: `version` × nome da pasta do Caskroom;
   - Homebrew sem Caskroom: `version` (antes da vírgula) ×
     `CFBundleShortVersionString`;
   - macOS: `Display Version` × `sw_vers -productVersion`. Só listamos o que o
     sistema mostra, então a comparação é apenas uma conferência.
5. Só `remoto > instalado` gera item. `menor` ou `igual` não gera nada (nunca
   sugerimos voltar de versão).

## Prioridade entre fontes
- App com recibo da App Store: **só F1**. A App Store é a única que pode
  atualizar esse app; feeds e Homebrew são ignorados.
- Demais apps, nesta ordem: **F2 (feed do app) → F3 (Homebrew)**. Vale a
  primeira fonte com resposta **confiável** (`menor`, `igual` ou `maior`). A
  seguinte só é consultada se a anterior não existir, falhar (rede, HTTP,
  XML) ou for não confiável.
- Exceção do design: app instalado pelo `brew` (no Caskroom) usa **F3 como
  principal** e F2 como plano B, porque quem atualiza é o Homebrew.
- **Quando duas fontes concordam** (as duas dizem `maior`, o que só acontece
  quando a segunda é consultada como plano B): o item é **um só**. Versão nova,
  fonte exibida e botão vêm da fonte de maior prioridade. Campos vazios dela
  (data, tamanho, novidades) são completados pela outra, **só se** a versão nova
  das duas for `igual` pela regra acima. Se as versões novas divergirem, vale só
  a de maior prioridade.
- Uma fonte que diz `igual`/`menor` encerra a busca: não procuramos "uma
  segunda opinião" que diga o contrário.

## Inclusão
- Um item por app com `remoto > instalado` e por entrada de F4.
- Campos: nome exibido, ícone do app, fonte, versão instalada (a curta, mesmo
  quando a comparação usou `CFBundleVersion`), versão nova (curta quando
  existir), data, tamanho, novidades (texto puro; HTML do Sparkle convertido
  para texto) e a ação do botão.

## Exclusão
- O próprio CleanYourMac fica fora do Atualizador na v0.2.
- Apps em volumes que não são o de inicialização ou em pastas de outros
  usuários.
- Apps "agentes" sem interface (`LSUIElement`) entram normalmente se tiverem
  fonte.
- Apps do sistema protegidos (`/System/Applications`): só por F4.

## Recomendado
- Nada marcado por padrão na etapa 1. Não há instalação, e "Atualizar" é uma ação
  por item (ver Botões). Observado no CleanMyMac: o menu de seleção começa em
  "nenhum" [E10].

## Agrupamento e nome exibido
- Lista plana na seção Atualizador. Detalhe à direita com fonte, versão atual →
  nova, data, tamanho e novidades (mesmas peças do CleanMyMac, com textos
  nossos) [E10].
- Ordenação padrão: pela data da última abertura (observado) [E10].

## Cálculo de tamanho
- O tamanho exibido é o **da atualização**: `fileSizeBytes` (F1), `length` do
  `enclosure` (F2) e `Size` de `softwareupdate` em KiB × 1024 (F4). Sem dado,
  fica vazio, nunca 0. Formatação decimal (`common.md` §2). GarageBand:
  731 861 599 → 732 MB [E11].

## Botões (o que cada um abre)
| Fonte | Ação |
|---|---|
| App Store | `macappstore://apps.apple.com/app/id<trackId>`; se falhar, `trackViewUrl` no navegador. O CleanMyMac usa `macappstore://itunes.apple.com/app/id<id>` [E8]. |
| Sparkle | Abre o **próprio app**, que tem a opção de procurar atualizações. Um link secundário abre as novidades (`releaseNotesLink`) ou o `link` do item. Na etapa 2, este botão passa a instalar. |
| Homebrew | Mostra o comando `brew upgrade --cask <token>` com um botão de copiar e um link para `homepage`. O app não roda o `brew`. |
| macOS | `x-apple.systempreferences:com.apple.preferences.softwareupdate`, o mesmo destino do CleanMyMac [E8]. |

Antes de abrir o app para atualizar (Sparkle), nada é encerrado. A lista de
apps abertos que precisam fechar só entra na etapa 2 (ver `removal.md`, Apps
abertos).

## Rede e privacidade
- Só durante a análise do módulo. Limite de 10 s por requisição; até 4 feeds
  em paralelo; no máximo 1 requisição de lookup por lote de 50 bundle IDs.
- O `User-Agent` identifica o CleanYourMac, sem dados da máquina.
- Sem rede: o grupo mostra que não foi possível checar, e o resto do módulo segue.

## Alertas e selos
- Nenhum selo na v0.2. Os campos `critical` (Sparkle) e `major` (macOS) ficam
  no modelo.

## requiresAdmin
- Análise: não
- Ação: não (só abre apps, a loja, os Ajustes ou copia um comando)

## Evidências
- **E1**: símbolos `UpdaterScanOptions.mas` / `.sparkle`,
  `UpdaterScanTaskFactory.applicationsUpdates(options:)` e `.systemUpdate()`, e
  classes `MASApplicationsDataSource`, `SparkleApplicationsDataSource`,
  `SparkleAppValidator` e `SparkleAppFeedProvider` (UpdaterScanning).
- **E2**: strings `isFromAppStore` (UpdaterScanning) e `Contents/_MASReceipt/receipt`
  (ApplicationsService).
- **E3**: função decompilada em UpdaterScanning que abre
  `<app>/Contents/Info.plist` e devolve verdadeiro se alguma das 13 chaves
  `SU…` da tabela existir. Strings `Contents/Frameworks/Sparkle.framework`,
  `com.mediaatelier.grandtotal`, `FileSystemUserPreferencesAccessor`,
  `userPreferences` e o campo `feedURLPath`.
- **E4**: funções decompiladas `findHighestAppVersion(applications:)` e
  `sortApplicationsByPath` (UpdaterScanning). Elas ordenam por caminho e
  mantêm o maior pelo comparador de versões.
- **E5**: strings de AppInfoNetworkService: `/api/v1/apps/check`,
  `CheckAppsUpdatesRequest` e as chaves `bundle_id`, `version`, `short_version`,
  `installation_type`, `channel`, `sparkle_feed_url`, `track_id`, `os_version`,
  `cpu_arch`, `lang`, `model_id`, `latest_version`, `latest_short_version`,
  `release_date`, `release_notes`, `update_flow`, `version_importance`,
  `logo_url` e `screenshot_urls`.
- **E6**: `/api/v1/os/check` e `CheckSystemUpdateRequest` (AppInfoNetworkService);
  a função decompilada `SystemUpdateScanTask.execute()` lê `hw.model` (constante
  de 8 bytes) e a versão do sistema.
- **E7**: SparkleUpdaterService (métodos de `SPUUpdaterDelegate`/`SPUUserDriver`,
  `allowedChannelsForUpdater:` e `bestValidUpdateInAppcast:forUpdater:`) e
  MASUpdaterService (`CKPurchaseController`, `CKDownloadQueue`, `MasKit` e uma
  mensagem que aponta para o projeto `mas-cli`).
- **E8**: strings de ApplicationsModule
  `macappstore://itunes.apple.com/app/id` e
  `x-apple.systempreferences:com.apple.preferences.softwareupdate`;
  as chaves `popover_update_app_manually_*`, `popover_update_mas_app_manually_text`
  e `popover_system_update_*`; o símbolo
  `ApplicationUpdate.canBeUpdatedProgrammatically`.
- **E9**: funções decompiladas `CMVersionComparator compareVersion:toVersion:`,
  `splitVersionString:` e `typeOfCharacter:` (SharedObjcUtils). Três tipos de
  segmento (número, texto, ponto), com as regras de desempate descritas acima.
- **E10**: observação AX `apps-Atualizador-v-2026-10-21T140522Z.txt`: 1 item
  (GarageBand), fonte App Store, 10.4.13 → 10.4.14, data 22 de abril de 2026,
  732 MB, novidades em inglês; seleção "nenhum"; ordenado pela última abertura.
- **E11**: consulta pública
  `itunes.apple.com/lookup?bundleId=com.apple.garageband10&country=br` em
  2026-10-21: `kind` `mac-software`, `version` 10.4.14,
  `currentVersionReleaseDate` 2026-04-22T16:59:44Z, `fileSizeBytes`
  731861599, `minimumOsVersion` 15.6 e `trackId` 682658836. Instalado:
  `CFBundleShortVersionString` 10.4.13, com recibo.
- **E12**: consulta pública com `bundleId=net.whatsapp.WhatsApp&entity=macSoftware`:
  o único resultado tem `kind` `software` (iOS) e `version` 26.41.74. O
  instalado é 26.40.77. O CleanMyMac não lista o WhatsApp.
- **E13**: leitura do disco: ChatGPT e Setapp embutem `Sparkle.framework`
  sem `SUFeedURL` no `Info.plist`; nenhum app desta máquina tem `SUFeedURL` no
  `Info.plist`.
- **E14**: `formulae.brew.sh/api/cask/google-chrome.json` e `warp.json` em
  2026-10-21: os dois com `auto_updates: true`; Chrome com `version`
  156.0.8078.48 e `bundle_short_version` 155.0.8059.40. `cask.json`:
  2 083 012 bytes transferidos com gzip, `content-length` 19 170 177.
- **E15**: `plutil -p /Library/Preferences/com.apple.SoftwareUpdate.plist`
  (sem root) mostra `RecommendedUpdates` com Safari 27.0, macOS Tahoe 26.7.1 e
  macOS 27.0.1, além de `LastSuccessfulDate` 2026-10-21. `softwareupdate --list`
  sem root: 5,73 s, as mesmas 3 entradas, com tamanhos.

## Divergências conhecidas
- **Catálogo privado × fontes públicas**: a lista pode diferir (aceito pelo
  usuário). Conferência nesta máquina: a nossa regra também dá exatamente
  **1 item (GarageBand 10.4.13 → 10.4.14, App Store)**. O WhatsApp sai por
  `kind`; o Xcode (27.1 = 27.1) e os apps com `auto_updates` no Homebrew
  (Chrome, Warp) também ficam de fora; os apps com Sparkle não têm feed legível.
  Casks no Caskroom desta máquina: `codex` 0.163.0 = 0.163.0 no catálogo (e sem
  artefato `app`); `macicns` não está no catálogo oficial (vem de outro tap, então
  não casa); `openlogi` tem `auto_updates: true`. Nenhum gera item [E14].
- **Novidades em outro idioma**: o CleanMyMac mostrou o texto em inglês; a nossa
  busca na região `br` devolve o texto da loja em português. A diferença é
  aceita.
- **macOS**: nesta máquina, o CleanMyMac **não** mostrou cartão de
  atualizações do macOS na tela de resultados, mesmo com 26.7.1 e 27.0.1
  disponíveis no sistema (a decisão dele vem do servidor). Nós listaremos as
  3 entradas. A diferença está documentada; ver em `results-screen.md` se o
  cartão deve aparecer só para atualizações do mesmo número principal.
- **Canais do Sparkle**: descartamos itens com `sparkle:channel`. Um app
  configurado para beta pode ver "sem atualização" conosco.
- **Feed definido em tempo de execução**: não temos como ler. Esses apps caem
  para F3.
- **Etapa 2** (instalar) não faz parte desta spec.

## Checklist de testes
1. `compareVersions`: `1.2.10 > 1.2.9`; `1.0 > 1.0b1`; `1.0 = 1.0`;
   `1.0 < 1.0.1`; `1.0a < 1.0`; `2.0 > 1.99`; `v1.2 = 1.2`; `1.2,345` (brew) =
   `1.2`; `20261020.1` × `1.24` → não confiável; `latest` → não confiável;
   `1.3-beta` remoto × `1.2` instalado → não confiável.
2. Lookup falso com `kind: software` → nenhum item.
3. Lookup com `version` igual → nenhum item.
4. Lookup com `minimumOsVersion` acima do sistema → nenhum item.
5. Appcast com três itens (um com `sparkle:channel=beta`, um com
   `minimumSystemVersion` acima do sistema, um válido) → escolhe o válido.
6. Item do appcast com versão só no atributo do `enclosure` (Sparkle 1) → lido.
7. Item sem `sparkle:version` → ignorado.
8. Feed fora do ar → cai para Homebrew, se houver casamento.
9. Cask com `auto_updates: true` → ignorado; com `version: latest` → ignorado.
10. App no Caskroom em `1.0` e cask em `1.1` → item com o comando
    `brew upgrade --cask <token>`.
11. Dois apps com o mesmo `.app` em casks diferentes → nenhum casamento.
12. Plist de SoftwareUpdate de teste com 2 entradas → 2 itens macOS, sem
    rodar `softwareupdate`; com `LastSuccessfulDate` antiga → roda em segundo
    plano (simulado nos testes).
13. Botões: App Store → URL `macappstore://apps.apple.com/app/id682658836`;
    macOS → URL dos Ajustes; Sparkle → abre o bundle do app.
14. Paridade nesta máquina: exatamente o GarageBand, com 732 MB e data de
    22/04/2026.
