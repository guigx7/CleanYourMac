# Arquivos de Idioma (`languageFiles`)

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (Apple Silicon), análise de 2026-10-20
(baseline `re-notes/ax/baseline-20261020-1457`). Idiomas do usuário nesta máquina:
`AppleLanguages = ["pt-BR"]`, teclado "Brazilian - Pro".

## Resumo do comportamento
Para cada app "de usuário", o grupo procura pastas `<idioma>.lproj` dentro de
qualquer pasta `Resources` do bundle e propõe apagar as de idiomas que o usuário não
usa. Ficam de fora as que a assinatura de código sela como obrigatórias, as que
têm algo além de `.strings`/`.stringsdict` e as pastas `Resources` onde não sobraria
nenhum idioma mantido. Os itens são agrupados **por idioma**, e os apps aparecem
como filhos (E1, E5, E7, E10).

## Locais varridos
Os mesmos apps de usuário da spec `universal-binaries.md` (seção "Locais varridos":
LaunchServices + Spotlight na home e em `/Applications/` + varredura de
`/Applications`, com o mesmo filtro de caminho e o mesmo filtro de prefixos de
bundle id) (E1).

Dentro de cada app (E4):
- Se o bundle tem extensão `.wdgt`, a pasta do próprio bundle é tratada como uma
  pasta `Resources`.
- Senão, percorrer o bundle sem seguir links simbólicos e **sem descer em pastas
  `.lproj`**. Cada pasta (ou link) cujo nome, em minúsculas, é exatamente
  `resources` é examinada como "pasta Resources", e a varredura continua descendo
  nela (pega `Contents/Resources`, `Foo.framework/Versions/A/Resources`,
  `Helper.app/Contents/Resources`, `X.bundle/Contents/Resources`…). Um
  `Foo.framework/Resources` que é link simbólico não é aberto, então não há duplicatas.
- Numa pasta Resources, os candidatos são os **filhos diretos** que são pastas
  (não links) com extensão `.lproj` (comparação sem diferenciar maiúsculas).

## Inclusão
### Critério por app (E2)
Pular o app se:
1. o caminho é protegido pelo SIP (rootless) ou o `Contents/Info.plist` tem o flag
   `restricted`;
2. o bundle id está ignorado (base de regras ou lista do usuário);
3. o caminho está ignorado (base de regras ou lista do usuário).

### Código do idioma de uma `.lproj` (E5)
Tirar `.lproj` do nome e canonicalizar com
`CFLocaleCreateCanonicalLanguageIdentifierFromString` (no Swift:
`Locale.canonicalLanguageIdentifier(from:)`). Exemplos medidos: `zh_CN`→`zh-Hans`,
`zh_TW`→`zh-Hant`, `zh_HK`→`zh-HK`, `French`→`fr`, `English`→`en`,
`pt_PT`→`pt-PT`, `es_419`→`es-419`, `en_GB`→`en-GB`, `no`→`nb`, `Base`→`base`. Dois
apelidos antigos são corrigidos à mão: `ua`→`uk` e `jp`→`ja`. Se a canonicalização
falhar, usar o nome sem `.lproj`.

### Idiomas protegidos, nunca propostos (E6, E8, E9)
Um código está protegido quando, em minúsculas:
- é `en`, `english`, `base`, `default`, `empty` ou `.`, ou começa com `en-` (logo
  **todo inglês**, inclusive `en-GB` e `en-AU`, e o `Base.lproj` ficam sempre); **ou**
- o "idioma principal" (o trecho antes do primeiro `-`) é o idioma principal de algum
  idioma do usuário. A lista do usuário é a união de:
  - `AppleLanguages` das preferências globais do usuário (ex.: `pt-BR` → `pt`);
  - os idiomas das fontes de entrada de **teclado** habilitadas
    (`kTISPropertyInputSourceLanguages` das fontes da categoria
    `kTISCategoryKeyboardInputSource`).
  Assim, com `pt-BR` ficam `pt`, `pt-BR`, `pt-PT` e `pt_PT`. Com `zh-Hans`, ficam
  `zh-Hans`, `zh-Hant` e `zh-HK` (todos têm principal `zh`).
- Também ficam os idiomas que a base de regras marca como ignorados, no geral ou
  para um app específico (pelo **nome** do app). É opaco, e a lista do usuário
  equivale a isso (ver "Exclusão").

### Regra da pasta Resources: nunca deixar o app sem idioma (E7)
Para cada pasta Resources: contar `N` = número de `.lproj` encontradas e `K` =
número de códigos **distintos não protegidos** entre elas. Se `N > 0` e `N == K`
(nenhuma `.lproj` da pasta é de idioma protegido, e não há duas pastas para o mesmo
código), **nada** dessa pasta é proposto. Caso contrário, as `.lproj` não
protegidas viram candidatas.

### Filtro por `.lproj` candidata (E10, E11)
Uma candidata só entra se:
1. **não** for selada como obrigatória pela assinatura: lendo **todos** os
   arquivos `_CodeSignature/CodeResources` do bundle (base = pasta dois níveis
   acima), cada chave de `files`/`files2` que contém `.lproj` e cujo valor **não** tem
   `optional = true` marca a pasta `base/<chave cortada até .lproj>` como selada. Se
   a entrada tem `symlink`, o alvo (relativo à pasta da entrada) também fica selado.
   Na prática, o `codesign` marca as `.lproj` como opcionais por padrão e o
   `Base.lproj` como obrigatório, então a maioria das pastas de idioma de apps
   assinados **pode** ser apagada sem invalidar o selo;
2. todo o conteúdo (recursivo, incluindo subpastas e arquivos ocultos) for arquivos
   terminados em `.strings` ou `.stringsdict`. Qualquer outro nome (`.nib`,
   `.storyboardc`, `.plist`, `.png`, uma subpasta, `.DS_Store`…) descarta a pasta;
3. pasta **vazia** entra (com 0 bytes). Isso explica as dezenas de idiomas com
   "0 KB" vindos das `.lproj` vazias que os apps Electron trazem.

## Exclusão
- Apps fora do escopo (ver `universal-binaries.md`), apps com SIP/`restricted`.
- **Base de regras (opaca)** (E2, E6): bundle id ignorado, caminho ignorado,
  idioma ignorado e idioma ignorado por app. **Regra equivalente do CleanYourMac**,
  derivada da baseline:
  - ignorar bundle ids que começam com `com.apple.`. O `/Applications/Xcode.app`
    (`com.apple.dt.Xcode`, fora do SIP) tem `nl.lproj` só com `.strings` e opcional
    no selo, mas o holandês aparece com 0 KB;
  - ignorar `com.google.Chrome` (e `.beta`, `.dev`, `.canary`). O Chrome tem 4 KB
    elegíveis em quase todos os idiomas, e a baseline não os conta (ver tabela). Ele
    também some de Binários Universais;
  - ignorar apps da Mac App Store (`Contents/_MASReceipt`): escolha de segurança nossa,
    sem observação contrária (o único app MAS de terceiros, o WhatsApp, não tem
    candidatas válidas);
  - lista do usuário de bundle ids, caminhos e idiomas a manter, vazia por padrão.
- Nenhuma checagem de app em execução (E3).

## Recomendado
**Não.** Os grupos de idioma chegam à UI **desmarcados** ("Selecionar: Nenhum",
`checked=0` em todos) (E12). Os modelos internos têm um campo `autoselected`, mas
a seleção inicial exibida é vazia, e é ela que seguimos.

## Agrupamento e nome exibido
- **Nível 1: idioma.** Um item por código de idioma, somando todos os apps. Nome
  = nome do idioma localizado no idioma da UI, como `Locale(identifier: <idioma da
  UI>).localizedString(forIdentifier: <código>)`, com a primeira letra minúscula
  como o macOS devolve em português (ex.: `fr` → "francês", `zh-Hans` → "chinês
  simplificado", `es-419` → "espanhol (América Latina)", `nb` → "bokmål
  norueguês"). Ícone: símbolo genérico de idioma (o CleanMyMac usa uma imagem
  própria, que não copiamos). Tem o botão de expandir (E12, E13).
- **Nível 2: apps.** Ao expandir, um filho por app que tem pastas daquele idioma.
  Nome = nome do app, ícone = ícone do app, tamanho = soma das pastas daquele
  idioma no app (E13).
- O idioma só aparece se algum app tiver pelo menos uma pasta para ele, mesmo
  vazia (E5).
- No modelo do CleanYourMac: `JunkItem` de idioma com `removal = nil`,
  `id = "languageFiles:<código>"`, `detail = <código>`. Filhos com
  `id = "languageFiles:<código>:<caminho do app>"`,
  `removal = .removeLocalizations(bundle:, lprojs: [URL])`.
- Ordem: tamanho decrescente. O desempate entre tamanhos iguais não é estável na
  baseline e não precisa ser reproduzido.

## Cálculo de tamanho
- Tamanho **alocado** (blocos em disco) dos arquivos dentro da `.lproj`, sem contar
  a própria pasta. Uma pasta vazia vale 0. Os valores da baseline são múltiplos de
  4.096 bytes (ex.: francês 32,8 KB = 8.192 + 24.576 B alocados, contra 28.272 B
  lógicos), e a UI usa unidades decimais (E12, E14).
- Links simbólicos não são seguidos.

## Remoção
- O CleanMyMac trata cada `.lproj` como um arquivo comum do grupo. Ele apaga a pasta
  com o removedor genérico de arquivos (remoção definitiva com tratamento de
  arquivo travado) e usa o removedor privilegiado como plano B (E15). Não foi achado
  uso do Lixo neste fluxo. Não reassina nem edita o `CodeResources`.
- **CleanYourMac:** `.removeLocalizations(bundle:lprojs:)` **apaga definitivamente**
  cada pasta `.lproj` listada, depois de validar que cada caminho está dentro de uma
  pasta `Resources` do bundle e termina em `.lproj`. Mover para o Lixo não faz
  sentido para pedaços de bundle.
- **Salvaguarda (divergência):** se `codesign --verify --deep --strict <app>`
  passava antes, rodar de novo depois. Se falhar, restaurar as pastas (guardadas
  numa cópia temporária antes de apagar) e marcar falha.
- **Gerenciamento de Apps:** apagar dentro do bundle de um app de outro desenvolvedor
  exige essa permissão no macOS 13 ou mais novo. O CleanMyMac não a pede (ver
  `universal-binaries.md`, E18), mas o CleanYourMac pede quando a seleção inclui
  este grupo.
- App aberto: sem checagem. Apagar recursos de um app em execução não o derruba, mas
  ele pode precisar ser reaberto para mudar de idioma.

## Alertas e selos
Nenhum.

## requiresAdmin
- Análise: **não**
- Limpeza: **não** por padrão. Se der `EACCES` (ex.: app de outro dono), o item vai
  para o lote privilegiado.

## Baseline observada
Grupo "Arquivos de Idioma": **213 KB** no total, "Selecionar: Nenhum", todos com
`checked=0`.

| Idioma (UI) | Tamanho | Composição no disco (alocado) |
|---|---|---|
| francês | 32,8 KB | Claude 8.192 + Hidden Bar 24.576 |
| japonês | 28,7 KB | Claude 4.096 + Hidden Bar 24.576 |
| chinês tradicional | 24,6 KB | Hidden Bar |
| chinês simplificado | 24,6 KB | Hidden Bar |
| alemão | 20,5 KB | Claude 8.192 + Hidden Bar 12.288 |
| árabe, vietnamita, croata | 12,3 KB cada | Hidden Bar 12.288 (Claude 0) |
| italiano, indonésio, hindi, espanhol (América Latina), espanhol | 8,2 KB cada | Claude 8.192 |
| coreano | 4,1 KB | Claude 4.096 |
| urdu, ucraniano, télugo, tâmil, turco, tcheco, tailandês, sérvio, sueco, suaíli, russo, romeno, polonês, persa, marati, malaio, malaiala, lituano, letão, húngaro, holandês, hebraico, guzerate, grego, finlandês, filipino, estoniano, esloveno, eslovaco, dinamarquês, catalão, canarim, búlgaro, bokmål norueguês, bengali, amárico, africâner | 0 KB cada | `.lproj` vazias de Claude e Visual Studio Code (Electron) |

Ausências conferidas no disco: português (protegido por `pt-BR`), inglês e Base
(sempre protegidos). As `.lproj` da `Electron Framework.framework` (contêm `.pak`)
não entram. Os apps do Setapp em `~/Library/Application Support/Setapp/LaunchAgents/`
(têm `fr`, `de`, `es`… só com `.strings`) não entram, porque estão fora do escopo
`~/Library`. Google Chrome e Xcode também não entram (regra de bundle id).
Recalcular com as regras acima, excluindo Chrome e Xcode, reproduz todos os valores
da tabela.

## Evidências
- **E1** — pseudocódigo de `CMApplicationLanguagesScanTask::scan` e dos blocos que ele
  usa: os apps vêm de `applicationsService.userApplications`, e os itens passam por
  `_groupedLanguageItemsFromApplicationItems:`.
- **E2** — pseudocódigo de `CMApplicationLanguagesScanTask::_shouldScanApplication:`
  (rootless, `isRestricted`, `isBundleIdIgnored:`, `isPathIgnored:`).
- **E3** — pseudocódigo de `CMApplicationLanguagesScanTask::_applicationLanguagesForApplication:`:
  ordem dos filtros, `isLanguageIgnored:forApplication:` com o nome do app,
  `isCodesignedLprojFileWithPath:`, `hasNonStringsFilesAt:`, tamanho por pasta,
  idioma só com arquivos.
- **E4** — pseudocódigo de `CMLanguagesUtilities::languagesForApplicationAtPath:progress:`
  (caso `.wdgt`, `fts` físico, pular `.lproj`, examinar pastas `resources`).
- **E5** — pseudocódigo de `CMLanguagesUtilities::shortLanguageNameFromDirectoryTwoLetters:`
  (canonicalização, `ua`/`jp`). Execução local de
  `CFLocaleCreateCanonicalLanguageIdentifierFromString` e
  `Locale.localizedString(forIdentifier:)` para conferir os exemplos e os nomes em pt-BR.
- **E6** — pseudocódigo de `ApplicationLanguagesKnowledgeBaseWrapper::isLanguageIgnored:`
  e da função auxiliar dos códigos sempre mantidos (`en`, `en-*`, `english`, `base`,
  `default`, `empty`, `.`) e da busca do idioma principal (trecho antes de `-`) na
  lista do usuário. Depois disso vem a regra da base.
- **E7** — pseudocódigo de `CMLanguagesUtilities::scanResourcesForLanguages:addResultsToDictionary:progress:`
  e do bloco por filho (conta as `.lproj`, compara com o número de idiomas não
  ignorados, só adiciona se forem diferentes).
- **E8** — pseudocódigo de `LanguagePreferences.languagesToKeep` e do construtor da
  lista lazy (`AppleLanguages` das `UserDefaults`, registros com `isoCode`,
  `mainLanguage`, `shouldBeKept`, `isProtected`).
- **E9** — pseudocódigo da função do `LanguagePreferences` que chama
  `TISCreateInputSourceList` e lê `kTISPropertyInputSourceLanguages` das fontes
  `kTISCategoryKeyboardInputSource`.
- **E10** — pseudocódigo de `CMApplicationInfo::_loadCodeResourcesIfNeeded`,
  `_allCodeResourcesFiles`, `_nonOptionalSignedLprojsFromCodeResources:basePath:` e
  do bloco que corta a chave em `.lproj`, pula `optional` e adiciona o alvo de
  `symlink` (ApplicationsService).
- **E11** — pseudocódigo de `CMApplicationLanguagesScanTask::hasNonStringsFilesAt:`.
- **E12** — observação da baseline (`Detritos do Sistema/Arquivos de Idioma.txt`).
- **E13** — strings do JunkCleanupModule com os tipos de nó
  `JunkCleanupItemNode<ApplicationLanguageGroupModel, JunkCleanupItemNode<ApplicationLanguageModel, Node>>`
  (idioma → app). Símbolos `ApplicationLanguageGroupModel.isoCode/applications` e
  `ApplicationLanguageModel.appUrl/files/size`.
- **E14** — leitura do disco (somente leitura): script em Python sobre os apps do
  Spotlight, com o filtro de caminho, `ls -lO`, `plutil -p` dos `CodeResources`,
  `defaults read -g AppleLanguages` e `com.apple.HIToolbox AppleEnabledInputSources`.
- **E15** — símbolos do CleaningCore: `FileRemover.remove(at:)`, que chama
  `removeFileAndHandleLockAtPath:error:` (remoção definitiva), e
  `PrivilegedFileRemover`. Ausência de `MoveToTrashFileRemover` no JunkCleanupModule.
  Os filhos de idioma são `CMFileModel` comuns (E3). É uma inferência: o removedor
  concreto é injetado pelo app.

## Divergências conhecidas
- **Base de regras** substituída por: `com.apple.*`, Chrome, MAS e a lista do usuário.
  Ela reproduz a baseline desta máquina.
- **Fontes de apps:** as mesmas limitações de `universal-binaries.md` (sem
  `_LSCopyAllApplicationURLs`).
- **Verificação de assinatura** antes e depois, com restauração: é nossa, o
  CleanMyMac não faz.
- **Remoção definitiva:** é a forma mais provável no CleanMyMac (E15), mas não foi
  observada em execução.
- **Ícone do grupo de idioma:** símbolo nosso.

## Checklist de testes
Fixtures em pasta temporária. `ScanContext.preferredLanguages` é injetado, e as
fontes de teclado também (vazias, salvo quando o caso diz outra coisa).
1. `keepsPreferredLanguages`: idiomas `["pt-BR","en"]`, app com `Contents/Resources/{pt-BR,pt,pt_PT,en,en_GB,Base,fr,de}.lproj/Localizable.strings` → itens só `fr` e `de`; `pt*`, `en*` e `Base` nunca aparecem.
2. `English.lproj` e `French.lproj` → `English` protegido; `French` aparece como `fr` ("francês").
3. `zh_CN.lproj` + `zh-Hant.lproj` → itens `zh-Hans` e `zh-Hant`. Com o usuário em `["zh-Hans"]` → nenhum dos dois aparece.
4. `ua.lproj` → item `uk`; `jp.lproj` → item `ja`.
5. Pasta Resources só com `fr.lproj` e `de.lproj` (sem inglês/Base/idioma do usuário) → **nada** proposto (regra de não deixar o app sem idioma).
6. Resources com `en.lproj` + `fr.lproj` → `fr` proposto.
7. `fr.lproj` com `MainMenu.nib` (ou subpasta, ou `.DS_Store`, ou `.plist`) → descartado.
8. `fr.lproj` com `A.strings` + `B.stringsdict` → proposto; tamanho = soma alocada dos dois.
9. `fr.lproj` vazio → proposto com 0 bytes, e o idioma aparece.
10. `CodeResources` com `files2["Resources/fr.lproj/Localizable.strings"]` **sem** `optional` → `fr` descartado; com `optional = true` → proposto.
11. `.lproj` dentro de `Contents/Frameworks/F.framework/Versions/A/Resources/` → considerado; `F.framework/Resources` sendo symlink → não é contado duas vezes.
12. `.lproj` fora de qualquer pasta `Resources` (ex.: `Contents/fr.lproj`) → ignorado.
13. `.lproj` dentro de outra `.lproj` → ignorado.
14. Bundle `X.wdgt` com `fr.lproj` na raiz e `en.lproj` → `fr` proposto.
15. App com bundle id `com.apple.dt.Xcode`, `com.google.Chrome` ou com `_MASReceipt` → pulado.
16. App com `Info.plist` com o flag `restricted` (simulado no teste com um provedor de flags falso) → pulado.
17. Fonte de teclado com idioma `ru` habilitada → `ru.lproj` protegido.
18. Dois apps com `fr.lproj` → um item "francês" com 2 filhos (um por app); tamanho = soma.
19. Remoção em cópia (`ditto` de app real assinado): depois de apagar as `.lproj` propostas, `codesign --verify --deep --strict` passa e o app abre (`open -W -a`).
20. Remoção recusa caminho que não termina em `.lproj` ou fora de `Resources` do bundle (validação da `PathPolicy`).
21. Simulação (dry-run) → nada apagado.
