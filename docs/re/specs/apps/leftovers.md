# Sobras de apps (`appLeftovers`)

> Spec só com a parte **estática** (strings, símbolos e decompilação). O que
> depende da baseline observada está em "A confirmar com a baseline".

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83). Reconhecimento AX de
2026-10-21 (`re-notes/ax/apps-*`). Grupo "arquivos de sobras" da seção Sobras
do Gerenciador de Aplicativos e cartão próprio na tela de resultados.

## Visão geral
O CleanMyMac não procura "arquivos órfãos" em geral. Ele faz o caminho
contrário: **descobre apps que já não existem** a partir de rastros
conhecidos, cria para cada um um "app fantasma" (bundle ID + nome) e roda
nele os **mesmos buscadores de arquivos relacionados do Desinstalador** [E1][E2][E7].
O resultado é uma lista de apps apagados, cada um com os arquivos dele.

Fluxo:
1. Montar o conjunto de bundle IDs **instalados** [E3].
2. Juntar candidatos de duas fontes: preferências do usuário e contêineres
   de sandbox [E4][E5].
3. Descartar candidatos cujo bundle ID está instalado ou repetido [E6].
4. Descartar os que a base de regras manda ignorar [E7].
5. Para cada sobrevivente, carregar os arquivos relacionados (em segundo plano;
   a tela mostra um estado de "buscando sobras" até terminar) [E8][E12].

## Locais varridos

### Conjunto de instalados
União dos bundle IDs de [E3]:
- todos os apps que o Desinstalador lista (o mesmo inventário filtrado, ver
  `inventory.md`);
- plug-ins (`CMPluginInfo`), painéis de preferências (`CMPrefPaneInfo`) e
  adições de scripting (`CMScriptingAdditionInfo`) instalados.

### Fonte 1: preferências do usuário
- Arquivos da pasta de preferências do usuário (`~/Library/Preferences`)
  cuja extensão é `plist` ou `xml` [E4][E9].
- Para cada arquivo [E10]:
  - se a base marcar o arquivo como "ignorar ou de sistema", ele é pulado;
  - os bundle IDs saem do **nome do arquivo** (serviço `bundleIDsForFileURL:`
    da base, cuja regra exata está cifrada); o nome do app sai de
    `applicationNameFor:`;
  - há uma checagem de existência baseada na extensão e no caminho do app
    (provavelmente `/Applications/<nome>.app` e `~/Applications/<nome>.app`,
    os dois modelos de caminho guardados no buscador) [E11].
- Não se sabe se a subpasta `ByHost` entra (o acessor de preferências não foi
  decompilado).

### Fonte 2: contêineres de sandbox
- Cada pasta de `~/Library/Containers` (acessor `userSandboxContainers`) [E5].
- O app dono vem dos metadados do contêiner: primeiro
  `<contêiner>/.com.apple.containermanagerd.metadata.plist`, na cadeia
  `MCMMetadataInfo` → `SandboxProfileDataValidationInfo` →
  `SandboxProfileDataValidationParametersKey` → `application_bundle`. Se não
  houver, vale o `Container.plist` legado, com a mesma cadeia [E5][E9].
- Se o caminho `application_bundle` **existe** no disco, o contêiner é de um app
  presente e é descartado. Se não existe (ou não foi lido), o contêiner vira
  candidato [E5].
- Ler esses metadados exige **Acesso Total ao Disco**. Sem ele, a fonte 2 não
  produz candidatos.

### Não varrido como fonte
`~/Library/Group Containers`, `Application Support`, `Caches`, `LaunchAgents`,
recibos e `/Library` **não** geram candidatos. Eles só aparecem **como
arquivos** de um candidato já descoberto, através dos buscadores do
Desinstalador [E2][E7].

## Inclusão
- Candidato = (bundle ID, nome do app, caminho de referência) [E6][E10].
- Entra se: o bundle ID **não** estiver no conjunto de instalados, **não**
  tiver aparecido antes (deduplicação no mesmo conjunto) e a base **não** o
  ignorar (`isAppIgnoredWithBundleId:`) [E6][E7].
- O app fantasma é um `CMApplicationInfo` criado com bundle ID e nome, com o
  caminho de referência atribuído. Ele marca se é "de sistema" e um sinalizador
  de "agressor" (`LeftoverUninstallerApplication(appInfo:isSystem:isAggressor:)`)
  [E1].
- A base usada pelas sobras é própria (`buildForLeftovers`) e recebe a
  preferência "ignorar apps de sistema" [E7].
- Arquivos do candidato: o carregamento de recursos usa a mesma família de
  buscadores do Desinstalador (preferências, contêiner, suporte, caches,
  cookies, registros, relatórios de falha, estado salvo, ajuda, itens de
  início, launchd, recibos, Dock, PDF Services, temporários, plug-ins e
  arquivos extras da base) [E2]. As pastas e regras de casamento estão em
  `related-files.md`.

## Exclusão
- Bundle IDs instalados (apps, plug-ins, painéis, adições) [E3][E6].
- O que a base cifrada manda ignorar: arquivos "de sistema ou ignorados" e
  bundle IDs ignorados [E7][E10]. Há também um tratamento especial para
  `com.valvesoftware.steam` no módulo [E13].
- Contêiner cujo app (`application_bundle`) ainda existe [E5].
- Arquivos de preferência com outras extensões (`.lockfile`, sem extensão) [E9].

## Recomendado
- Não está claro na estática se os filhos vêm marcados. O cartão de resultados
  oferece **remover direto**, além de revisar, o que indica que o conteúdo do
  grupo nasce selecionado [E12]. *A confirmar*.

## Agrupamento e nome exibido
- Grupo da seção Sobras com o total do grupo [E12].
- Dentro do grupo, um nó por app fantasma (nome = nome derivado do arquivo),
  com os arquivos agrupados pelos mesmos tipos do Desinstalador [E1][E8].

## Cálculo de tamanho
- O mesmo provedor de tamanho dos recursos do Desinstalador (alocado, ver
  `common.md` §1) [E2].
- Observado: 49,2 KB = 49 152 bytes = exatamente **12 blocos de 4096**. Isso
  é compatível com 12 arquivos pequenos (um bloco cada) [E12].

## Remoção
- CleanMyMac: os recursos passam pelos removedores por tipo do Desinstalador
  (arquivo, preferências, launchd, itens de início, recibo, Dock), que apagam
  **definitivamente** (ver `removal.md`) [E14].
- **Regra nossa (design):** os arquivos de sobras vão para o **Lixo** do volume
  do item. O que exigir root passa pelo helper (operação "mover para o Lixo",
  ver `removal.md`).
- Admin só para arquivos fora da pasta do usuário (ex.: `/Library/...` de um app
  fantasma). Sem helper, esses itens ficam desmarcados e com aviso.

## Alertas e selos
- Nenhum selo específico [E12].

## requiresAdmin
- Análise: não (a fonte 2 precisa de Acesso Total ao Disco, não de root)
- Limpeza: não (só para itens fora de `~`)

## Evidências
- **E1**: símbolos de UninstallerScanning:
  `LeftoversFetcher.fetchLeftovers() -> [CMApplicationInfo]`,
  `LeftoverUninstallerApplication(appInfo:isSystem:isAggressor:)`,
  `LeftoverUninstallerApplicationMapper.mapToApplications(from:)`,
  `UninstallerScanTaskFactory.leftoversDiscoveryTask()` e
  `makeLeftoversResourcesLoadingModel(leftovers:)`.
- **E2**: nomes de classes buscadoras em UninstallerScanning
  (`CMPreferencesFilesFetcher`, `CMApplicationContainerFetcher`,
  `CMSupportingFilesFetcher`, `CMCachesFetcher`, `CMCookiesFetcher`,
  `CMLogsFetcher`, `CMCrashLogsFetcher`, `CMApplicationSavedStateFetcher`,
  `CMApplicationHelpFetcher`, `CMLoginItemsFetcher`, `CMLaunchDemonsFetcher`,
  `CMReceiptFetcher`, `CMDockIconFetcher`, `CMPDFServicesFetcher`,
  `CMTempFilesFetcher`, `CMPluginsFetcher`, `CMResourcesFromKnowledgeBaseFetcher`)
  e a fábrica `resourceFetcherFactory` (usada por apps e por sobras).
- **E3**: função decompilada auxiliar de `fetchLeftovers` (UninstallerScanning).
  Ela junta `allFilteredApplications`, `plugins`, `prefPanes` e
  `scriptingAdditions` e extrai `bundleID` de cada um.
- **E4**: função decompilada que percorre `userPreferences` (UninstallerScanning),
  com filtro por extensão a partir de um vetor estático com dois valores.
- **E5**: função decompilada que percorre `userSandboxContainers`
  (UninstallerScanning). Para cada contêiner, lê os metadados (duas funções:
  uma com o plist do containermanagerd e outra com `Container.plist`) e usa
  `fileExistsAtPath:` no caminho do app; só segue como candidato quando o
  caminho não existe.
- **E6**: função decompilada principal de candidatos. Ela insere cada bundle
  ID num conjunto que começa com os instalados e só aceita os que entram como
  novos.
- **E7**: `fetchLeftovers` decompilada. Ela chama `isAppIgnoredWithBundleId:`
  da base e cria `CMApplicationInfo initWithBundleID:appName:` + `setPath:`.
  Símbolo `UninstallerKnowledgeBaseFactory.buildForLeftovers(isSystemApplicationsIgnored:)`
  em ApplicationsModuleDomain.
- **E8**: strings de ApplicationsModule/ApplicationsModuleDomain:
  `LeftoversResourcesLoadingModel`, `LeftoversScanResult`,
  `LeftoversSubcategoryScanResult` e os textos de busca em segundo plano (chaves
  `leftovers_bg_scan_*` e `tile_looking_for_leftovers_*`).
- **E9**: literais lidos do binário de UninstallerScanning: o vetor estático
  `["plist", "xml"]`; `.com.apple.containermanagerd.metadata.plist`;
  `application_bundle`; `MCMMetadataInfo`;
  `SandboxProfileDataValidationInfo`;
  `SandboxProfileDataValidationParametersKey`; `Container.plist`.
- **E10**: função decompilada que monta o candidato a partir de um arquivo:
  `isIgnoreOrSystemItemFileWithPath:`, `bundleIDsForFileURL:` e
  `applicationNameFor:` da base.
- **E11**: inicializadores dos modelos `sharedApplicationTemplate` (20
  caracteres, `/Applications/%@.app`) e `userApplicationTemplate` (21
  caracteres, `~/Applications/%@.app` com `~` expandido), além de uma função
  auxiliar com `fileExistsAtPath:` + `pathExtension`.
- **E12**: observação AX: `apps-Sobras-v-…526Z.txt` (grupo de sobras com
  49,2 KB) e `apps-results2-…449Z.txt` (cartão com revisar e remover).
- **E13**: literal `com.valvesoftware.steam` nas strings de ApplicationsModule,
  perto do removedor configurável.
- **E14**: ver E10–E12 de `removal.md` (removedor definitivo).

## A confirmar com a baseline
A baseline desta máquina mostra **49,2 KB** de sobras (observação AX, sem a
lista de arquivos). Falta conferir:

1. **Quais apps fantasmas e quais arquivos** compõem os 49,2 KB. A hipótese
   aritmética é 12 arquivos de 1 bloco (4096 B) cada. Abrir a lista dentro do
   grupo de sobras com o `dump-ax` (só leitura), quando a janela estiver
   livre.
2. **Candidatos da fonte 1 nesta máquina** (cálculo nosso, só leitura, em
   2026-10-21): plists de `~/Library/Preferences` que não são `com.apple.*` e
   cujo nome não bate com nenhum bundle ID indexado pelo Spotlight:
   `com.google.GeminiMacOS.shareddata`, `com.google.Keystone.Agent`,
   `com.logi.optionsplus.driverhost`, `com.macpaw.CleanMyMac-setapp.HealthMonitor`,
   `com.macpaw.CleanMyMac-setapp.Menu`, `com.openai.sky.CUAService` (802 KB,
   grande demais para caber no total, logo **não** é sobra para ele),
   `com.setapp.defaults` e nomes sem ponto (`ContextStoreAgent`,
   `MiniLauncher`, `MobileMeAccounts`, `TokenBucketRateLimiter`,
   `diagnostics_agent`, `familycircled`, `mbuseragent`, `pbs`,
   `sharedfilelistd` …). Conferir quais deles o CleanMyMac aceita. Isso
   revela a regra de `bundleIDsForFileURL:` (nome sem ponto? sufixo `.shareddata`?
   helpers dentro de bundles instalados?).
3. **Fonte 2**: rodar nossa leitura dos metadados dos contêineres com Acesso
   Total ao Disco e listar contêineres cujo `application_bundle` não existe.
   Ver se algum aparece na baseline.
4. Se os filhos vêm **marcados** e se o grupo mostra um nó por app ou os
   arquivos soltos.
5. Se `ByHost` entra na fonte 1.
6. Se a comparação de bundle ID diferencia maiúsculas de minúsculas (o
   conjunto do CleanMyMac é de strings Swift; parece diferenciar).
7. Se arquivos de um candidato em `/Library` (fora de `~`) entram e com que
   marcação.

## Divergências conhecidas
- **Base cifrada**: `bundleIDsForFileURL:`, `applicationNameFor:` e
  "ignorar ou de sistema" são regras da `info.cmmkb`. Nossa versão inicial:
  - bundle ID = nome do arquivo sem a extensão, só se tiver o formato de DNS
    reverso (pelo menos dois pontos, só `[A-Za-z0-9.-]`);
  - nunca `com.apple.*`, nem nomes sem ponto;
  - nunca prefixo de um bundle ID instalado seguido de ponto (ex.:
    `com.macpaw.CleanMyMac-setapp.Menu` pertence a `com.macpaw.CleanMyMac-setapp`
    quando este estiver instalado; helpers e extensões também contam como
    instalados);
  - nome exibido = último componente legível do bundle ID ou `CFBundleName`
    lido do contêiner, quando houver.
  A paridade final depende do item 2 da seção anterior.
- **Segurança acima da paridade** (design): na dúvida, o candidato não entra.
  Comparamos bundle IDs **sem** diferenciar maiúsculas, o que gera menos sobras
  (um app instalado como `com.Foo.Bar` protege `com.foo.bar.plist`).
- **Destino**: Lixo (nosso) × remoção definitiva (CleanMyMac).
- **Contêiner sem metadado legível**: no CleanMyMac, ele segue como candidato
  (só é descartado quando o caminho do app é lido **e** existe) [E5]. Nós
  exigimos a prova: sem `application_bundle` lido, o contêiner não entra. Sem
  Acesso Total ao Disco, a fonte 2 fica vazia nos dois apps, porque nenhum
  metadado é lido. Mesmo assim, conferir na baseline se o CleanMyMac lista
  contêineres "cegos".
- **Inventário de plug-ins/painéis/adições**: se o nosso inventário não listar
  algum desses tipos, o bundle ID dele precisa entrar no conjunto de instalados
  mesmo assim. Sem isso, os arquivos de um plug-in instalado virariam sobra.
  O teste 6 cobre esse caso.

## Checklist de testes
1. `~/Library/Preferences/com.example.gone.plist` sem app instalado → 1 app
   fantasma `com.example.gone` com esse arquivo.
2. Igual, com `com.example.gone.app` instalado em `/Applications` → nada.
3. `com.apple.foo.plist` → nada.
4. `com.example.gone.lockfile` → nada (extensão).
5. `com.example.gone.xml` → candidato.
6. Painel `~/Library/PreferencePanes/X.prefPane` com bundle ID
   `com.example.pane` → `com.example.pane.plist` não é sobra.
7. Contêiner `~/Library/Containers/com.example.sbx` cujo metadado aponta para
   `/Applications/Sbx.app` inexistente → candidato; com o app presente → nada.
8. Contêiner sem metadado legível → não é candidato. Regra nossa: sem prova
   de que o app sumiu, não entra.
9. Dois rastros do mesmo bundle ID (plist + contêiner) → um único app fantasma.
10. `com.example.Host.Helper.plist` com `com.example.Host` instalado → nada.
11. Remover → os arquivos vão para o Lixo; nada fora da lista selecionada é
    tocado.
