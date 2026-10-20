# Binários Universais (`universalBinaries`)

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (Apple Silicon, `arm64`), análise de
2026-10-20 (baseline `re-notes/ax/baseline-20261020-1457`).

## Resumo do comportamento
Para cada app "de usuário", o grupo procura executáveis Mach-O *fat* (universais)
dentro do bundle e calcula quanto espaço sairia se ficasse só a fatia da
arquitetura da máquina. O item é o **app**. O tamanho é a soma das fatias que
seriam removidas. A limpeza reescreve cada binário mantendo só a fatia
compatível. **Não reassina** nem mexe no `CodeResources`, e se apoia no fato de
que cada fatia tem a sua própria assinatura embutida (E10, E11, E14).

## Locais varridos
A lista de apps é a mesma "lista de apps do usuário" do CleanMyMac (E1, E2, E3):

1. **Fontes** (união, sem repetir caminho):
   - todos os apps registrados no LaunchServices;
   - consulta Spotlight por `kMDItemContentType == com.apple.application-bundle` nos escopos `~` (home) e `/Applications/`;
   - varredura recursiva de `/Applications` (usada também como plano B se o LaunchServices falhar).
2. **Filtro de caminho** (o app é descartado se o caminho casar com qualquer regra):
   - começa com `/net`, `/tmp`, `/var`, `/cores`, `/private`, `/dev`, `/sbin`, `/bin`, `/etc`, `/usr`, `/Library`, `/System`, `/Developer`, `/Applications/Developer Tools`, `/Volumes`;
   - começa com `/opt`, exceto `/opt/homebrew-cask/Caskroom`;
   - começa com `~/Library` (inferido: a regra tem um caminho variável, e os apps em `~/Library/Application Support/Setapp/LaunchAgents/` não aparecem; ver E3 e "Baseline");
   - está **dentro de outro `.app`** (o caminho tem `.app/` seguido de mais componentes);
   - contém `.pvm` ou `.vmwarevm` (máquinas virtuais);
   - está dentro de uma pasta cujo nome tem um ponto, exceto quando o trecho depois do ponto é `localized` ou começa com dígitos (ex.: `Chrome Apps.localized/` passa; `Foo.bundle/X.app` não passa).
   - Exceção: um caminho que termina em `/Library/Application Support/Setapp/LaunchAgents/Setapp.app` entra mesmo assim.
3. **Filtro de bundle id por prefixo** (E3): descartar bundle ids que começam com
   `com.parallels.winapp`, `com.parallels.ApplicationGroupBridge`,
   `com.vmware.proxyApp`, `com.codeweavers.CrossOverHelper`,
   `com.google.Chrome.app.` (atalhos de web app do Chrome) e `com.setapp.teaser`.

Para o CleanYourMac: `~/Applications`, `/Applications` (com subpastas, como
`/Applications/Setapp/`) e qualquer outro lugar da home, como `~/Downloads`,
estão dentro do escopo. Isso explica o `Hidden Bar.app` em `~/Downloads` (E15).

## Inclusão
### Critério por app (nesta ordem; qualquer "não" pula o app)
1. O app não é protegido pelo SIP: o caminho não está protegido pelo *rootless*, e o
   `Contents/Info.plist` não tem o flag `restricted` (`SF_RESTRICTED`, visível em
   `ls -lO`) (E4, E5). Ex.: `/Applications/Safari.app` sai por isso.
2. O app não está na lista de ignorados da base de regras nem na lista de
   ignorados do usuário (E6). Ver "Exclusão" para a regra equivalente que adotamos.
3. A pasta do bundle não tem o flag `uchg` (imutável) (E7).
4. Em Apple Silicon, o app não é o próprio CleanMyMac (comparação do bundle id sem
   diferenciar maiúsculas) (E7). No CleanYourMac: nunca processar o próprio bundle.
5. O app não está marcado para "Abrir com o Rosetta" (ou o inverso): o bundle id não
   aparece nas chaves `Architectures for arm64` / `Architectures for x86_64` de
   `~/Library/Preferences/com.apple.LaunchServices/com.apple.LaunchServices.plist` (E8).
6. Existe uma **arquitetura compatível** para o executável principal do app
   (`CFBundleExecutable` em `Contents/MacOS/`), conforme "Arquitetura mantida". Se não
   houver, o app é pulado.

### Arquivos considerados dentro do bundle (E7, E9)
Percorrer o bundle inteiro, entrando em pacotes (`.framework`, `.app` aninhados,
`.xpc`, `.appex`, `.bundle`, `.plugin`) e incluindo arquivos ocultos, **sem descer em
pastas `.lproj`**. Um arquivo é **candidato** quando:
- o nome **não tem extensão** (logo `.dylib`, `.so`, `.node`, `.bundle` não entram; o
  binário de um framework, como `Foo.framework/Versions/A/Foo`, entra);
- o nome não é `CodeResources`, `.DS_Store` nem `PkgInfo`;
- tem o bit de execução, **não** é link simbólico e **não** é pasta.

Os arquivos chamados `CodeResources` não são candidatos, mas são lidos: para cada
um, a base é a pasta dois níveis acima (ex.: `X.app/Contents/_CodeSignature/CodeResources`
→ `X.app/Contents`). Cada chave de `files` e `files2` cujo valor **não** tem
`optional = true` vira um caminho selado (`base/chave`). Um candidato cujo caminho
completo está entre os selados de algum `CodeResources` cuja base é prefixo do seu
caminho **sai** da lista (E9). Na prática, os executáveis principais de bundles (o
app, os frameworks, os helpers `.app`/`.xpc`) continuam, porque o selo os registra
pela pasta do bundle e não pelo arquivo, enquanto executáveis soltos, selados por
hash (ex.: uma ferramenta em `Contents/Resources/`), ficam de fora.

### Cálculo por candidato (E10, E11)
- Se o arquivo é fat (magia `0xcafebabe` ou `0xcafebabf`, em big-endian): ler a
  tabela de fatias, descartando as entradas inválidas (deslocamento + tamanho maior
  que o arquivo, ou alinhamento ≥ 2^16 ou não respeitado). Se **nenhuma** fatia for
  compatível com a arquitetura mantida, **o app inteiro é pulado**. Caso contrário, as
  fatias "desnecessárias" são **todas** as que não são compatíveis.
- Se o arquivo não é fat: ler o tipo/subtipo de CPU nos bytes 4–11 (sem conferir a
  magia). Se for a arquitetura mantida, não há o que remover (0 bytes). Se não for, ou
  se não for reconhecível (ex.: script de shell executável, binário só `x86_64` em
  Apple Silicon), **o app inteiro é pulado**.
- Com uma ou mais fatias desnecessárias, o candidato vira um filho do app.

O app só vira item se tiver pelo menos um filho.

### Arquitetura mantida (E10, E12)
- "Compatível" significa mesmo `cputype` e mesmo `cpusubtype` depois de mascarar os
  bits altos (`& 0x00FFFFFF`). Só dois pares são reconhecidos: `arm64` =
  (`0x0100000C`, subtipo 0, `ARM64_ALL`) e `x86_64` = (`0x01000007`, subtipo 3,
  `X86_64_ALL`). `arm64e` (subtipo 2), `x86_64h` (subtipo 8), `i386` e `ppc` não são
  reconhecidos.
- A arquitetura mantida é decidida pelo **executável principal**: em Apple Silicon
  (ou quando o processo roda sob o Rosetta, `sysctl.proc_translated = 1`), escolhe
  `arm64` se houver essa fatia, senão `x86_64`; em Intel, escolhe `x86_64`. Essa
  arquitetura vale para todos os candidatos do app.
- Consequências: numa fatia `arm64e` ao lado de `arm64`, a `arm64e` é removida. Um
  binário aninhado só com `arm64e` + `x86_64` não tem fatia compatível, e o app é
  pulado.

## Exclusão
- Apps protegidos pelo SIP, imutáveis, marcados para o Rosetta, o próprio app de
  limpeza, apps fora do escopo de caminho e com bundle id nos prefixos ignorados
  (ver acima).
- **Base de regras (opaca, `info.cmmkb`)** (E6): a consulta faz três perguntas,
  todas sobre o "grupo" universal binaries: (a) o caminho do app está na lista de
  ignorados do usuário; (b) o caminho casa com uma regra de caminho da base; (c) o
  bundle id está ignorado (na base ou numa lista embutida no `JunkCleanupModule`).
  Não lemos a base. **Regra equivalente do CleanYourMac** (derivada da baseline):
  - ignorar bundle ids que começam com `com.apple.` (apps da Apple fora do SIP, como
    o Xcode e o GarageBand). A evidência vem da baseline de Arquivos de Idioma: o
    Xcode tem uma `.lproj` elegível que não é contada (ver `language-files.md`);
  - ignorar `com.google.Chrome`, `com.google.Chrome.beta`, `com.google.Chrome.dev` e
    `com.google.Chrome.canary` (o Chrome é universal, todas as fatias são
    compatíveis e nada no disco explica a ausência dele; ele também some de
    Arquivos de Idioma, o que aponta para uma regra por bundle id) (E15);
  - ignorar apps com `Contents/_MASReceipt` (Mac App Store): pertencem ao `root`, e
    a App Store substitui o bundle inteiro nas atualizações. É uma escolha de
    segurança nossa, sem observação contrária (não havia app MAS universal de
    terceiros nesta máquina).
  - Suportar uma lista de ignorados do usuário (bundle id ou caminho), vazia por padrão.
- Não há checagem de app em execução nem de assinatura/notarização na análise (E7).
  Apps assinados e notarizados por terceiros entram normalmente (Spotifast e Hidden
  Bar são assinados com Hardened Runtime) (E15).

## Recomendado
**Não.** O app e os filhos chegam à UI **desmarcados** (E7: o app nasce com
`autoSelected` da tarefa, que é `false`; baseline: os dois itens com
`checked=0` e "Selecionar: Nenhum") (E13). O CleanYourMac também não recomenda:
mexer em binários é a operação mais arriscada da Limpeza.

## Agrupamento e nome exibido
- **Item = app.** Nome exibido = nome da pasta do bundle **com** a extensão
  (`Spotifast.app`, `Hidden Bar.app`) (E13). Ícone = ícone do app (`.app(URL)`).
- A UI do CleanMyMac **não** mostra botão de expandir nesse grupo, só o tamanho (E13).
  Internamente, cada binário afinado é um filho com o caminho, o tamanho economizado
  e a arquitetura mantida (E7, E16).
- No modelo do CleanYourMac: `JunkItem` do app com `removal = nil`,
  `id = "universalBinaries:<caminho do app>"`, e um filho por binário com
  `removal = .thinBinary(executable:, keepArch:, bundle:)`,
  `id = "universalBinaries:<caminho do binário>"`, nome = caminho relativo ao
  bundle. A UI pode esconder os filhos, como o CleanMyMac faz.
- Ordem: por tamanho decrescente (padrão da tela).

## Cálculo de tamanho
- Filho = **soma dos campos `size` das fatias desnecessárias** na tabela fat, em
  bytes **lógicos** (não alocados). App = soma dos filhos (E7, E15).
- Conferência: o `x86_64` do `Spotifast` tem 31.731.888 bytes, e a UI mostra
  "31,7 MB". O `x86_64` do `Hidden Bar` tem 245.600 bytes, e a UI mostra "246 KB".
  A UI usa unidades decimais.
- Links simbólicos não são seguidos (candidatos não podem ser symlink).

## Remoção
Para cada filho selecionado (E14, E16, E17):
1. Reler o arquivo e montar um novo fat que contém **só** a fatia cujo nome de
   arquitetura é o mantido. O CleanMyMac mantém o cabeçalho fat (com 1 fatia, a mesma
   magia 32/64 bits do original, deslocamento recalculado pelo alinhamento da fatia)
   e grava em `<arquivo>.lipo` com o mesmo `mode` do original. Depois apaga o original
   e move o `.lipo` para o lugar.
2. Se a gravação como usuário falhar, tenta de novo pelo helper privilegiado
   (operação de "binary thinning" do serviço privilegiado).
3. **Não** reassina, **não** roda `codesign`, **não** edita `CodeResources` nem
   `_CodeSignature` (nenhuma referência a `codesign`/assinatura no `CleaningCore`,
   `PrivilegedRoutines` ou `JunkCleanupModule`) (E17).
4. Nenhuma checagem de app aberto foi encontrada (E7, E16). A troca por
   apagar + mover não afeta processos em execução, que mantêm o inode antigo.

**CleanYourMac:**
- Implementar com `lipo <bin> -thin <arch> -output <tmp>` (ou `-extract <arch>`, que
  mantém o cabeçalho fat como o CleanMyMac). Preservar `mode`, dono e grupo,
  substituir com `rename(2)` no mesmo diretório. Sem reassinar.
- **Salvaguarda extra (divergência):** antes de afinar um app, rodar
  `codesign --verify --deep --strict <app>`. Se passava antes e falhar depois,
  restaurar os originais (guardados numa cópia temporária) e marcar o item como falha.
  Apps que já falhavam antes não são verificados de novo.
- Mover para o Lixo não se aplica (é uma reescrita no lugar).
- **Gerenciamento de Apps (TCC):** no macOS 13 ou mais novo, alterar o bundle de um
  app assinado por outro desenvolvedor exige a permissão "Gerenciamento de Apps"
  (`kTCCServiceSystemPolicyAppBundles`). O CleanMyMac não tem nenhuma referência a
  essa permissão nos frameworks analisados (E18). Ele depende do helper root. O
  CleanYourMac deve pedir essa permissão quando a seleção incluir este grupo, e
  tratar `EPERM` como "falta Gerenciamento de Apps" (não como "precisa de root").

## Alertas e selos
Nenhum selo. Existe um "smart tip" por item (ícone de informação na baseline), sem
efeito na seleção (E13). Mensagem de erro genérica por app quando a remoção falha
(sentido: "não foi possível remover os binários extras de <app>") (E16).

## requiresAdmin
- Análise: **não**
- Limpeza: **não** por padrão. O motor tenta como usuário, e os itens que falharem com
  `EACCES` vão para o lote privilegiado (como no CleanMyMac, que usa o helper como
  plano B) (E14).

## Baseline observada
Grupo "Binários Universais": **32 MB** no total, "Selecionar: Nenhum".

| Item | Tamanho | checked | Observação no disco |
|---|---|---|---|
| `Spotifast.app` | 31,7 MB | 0 | `/Applications/Spotifast.app`; principal `x86_64 arm64`; `x86_64` = 31.731.888 B |
| `Hidden Bar.app` | 246 KB | 0 | `~/Downloads/Hidden Bar.app`; principal `x86_64 arm64`; `x86_64` = 245.600 B |

Apps universais **ausentes**, e o motivo:
- `/Applications/Safari.app` (`x86_64 arm64e`): SIP (`restricted`).
- `/Applications/Setapp/CleanMyMac.app`: é o próprio app.
- `~/Applications/Chrome Apps.localized/{GlobalWorks,Vercel,GitHub,Supabase Studio}.app`: bundle id `com.google.Chrome.app.*` (prefixo ignorado).
- `/Applications/Google Chrome.app`: nenhuma causa no disco (todos os executáveis são `x86_64 arm64`, sem script, sem `uchg`, sem marca do Rosetta). Atribuído à base de regras (bundle id).

## Evidências
- **E1** — pseudocódigo de `CMUniversalBinariesScanTask::scan` e do bloco que ele
  usa: a lista de apps vem de `CMSystemInfo.userApplications`, e cada app passa por
  `_shouldScanApplication:` e `_universalBinariesForApplication:`.
- **E2** — pseudocódigo de `CMSystemApplicationsProvider::_findAllApplications_NonSandboxed`
  e `_spotlightAppsURLs` (ApplicationsService): junta o LaunchServices, o Spotlight
  (escopos home e `/Applications/`, tipo `com.apple.application-bundle`) e uma varredura
  profunda.
- **E3** — pseudocódigo de `CMSystemInfo::_findAllApplications`, de
  `CMApplicationInfo::isUserAppAtPath:` e do filtro que aceita o `Setapp.app` por
  sufixo. A expressão regular de caminhos de "não usuário" está nas strings do
  ApplicationsService. Os prefixos de bundle id ignorados estão em strings próximas
  e no array de `applicationBundleIdentifierPrefixesToIgnore`.
- **E4** — pseudocódigo de `CMUniversalBinariesScanTask::_shouldScanApplication:`
  (rootless, `isRestricted`, base de regras).
- **E5** — pseudocódigo de `CMApplicationInfo::isRestricted` (consulta "restricted"
  do `Info.plist`). Leitura do disco: `ls -lO /Applications/Safari.app` mostra
  `restricted`.
- **E6** — pseudocódigo de `UniversalBinariesKnowledgeBase::shouldIgnoreApplication:`
  (JunkCleanupModule): ignorado do usuário por caminho, regra de caminho e bundle id.
- **E7** — pseudocódigo de `CMUniversalBinariesScanTask::_universalBinariesForApplication:`:
  flag imutável, próprio bundle em Apple Silicon, Rosetta, arquitetura do
  executável principal, enumeração do bundle, candidatos, soma `@sum.size`, filho
  com `autoselected`, app só com filhos. Strings `.DS_Store`, `PkgInfo` e
  `CodeResources` (lista de "não executáveis conhecidos").
- **E8** — pseudocódigo de `CMApplicationLaunchServices::architectureWasChangedForBundleIdentifier:`.
  Strings `Architectures for arm64`, `Architectures for x86_64` e o caminho do plist
  do LaunchServices.
- **E9** — pseudocódigo de `CMCodeResourcesInfo::initWithURL:` (base = dois níveis
  acima) e `isCodeSignedFileWithPath:` (chaves de `files`/`files2` não opcionais).
- **E10** — pseudocódigo de `CMLipo::compatibleArchitectureForBinaryAtPath:error:`,
  `_compatibleArchitectureForFatBinaryAtPath:error:`,
  `getUnnecessaryThinFilesForBinaryAtPath:compatibleArchitectures:error:` e
  `_compatibleArchitectureWithThinFile:compatibleArchitectures:`.
- **E11** — pseudocódigo de `CMBinaryReader::getFatBinaryFileAtPath:error:`,
  `getNonFatBinaryFileAtPath:error:`, `_isValidFatArch:size:`.
- **E12** — pseudocódigo de `CMArchitecture::getArchitectureByCpuType:cpuSubType:`,
  `_arm64`, `_x86_64`, `cpuSubtypeWithMask:`, `CMLipo::runByRosetta`
  (`sysctl.proc_translated`) e `CMLipo::targetCpuArm64`.
- **E13** — observação da baseline (`Detritos do Sistema/Binários Universais.txt`).
- **E14** — pseudocódigo de `UniversalBinaryThinner.thinBinary` (SystemJunkScanning):
  tenta o `CMLipo` local e, se falhar, o cliente privilegiado. Strings "Couldn't
  remove thin by app" / "by helper tool". Símbolos `LipoPrivilegedOperationsClientType`
  e `BinaryThinningRequest` (PrivilegedOperationsPerformerService).
- **E15** — leitura do disco (somente leitura): `lipo -archs`/`-detailed_info`,
  `codesign -dv`, `ls -lO`, `mdfind` para os apps citados na baseline.
- **E16** — strings do JunkCleanupModule: `UniversalBinaryRemovalTask`,
  `ConfigDependentUniversalBinaryThinner` (modo simulação e log de sucesso/falha).
  Textos localizados do erro genérico por app.
- **E17** — pseudocódigo de `CMLipo::removeUnnecessaryThinFilesFromBinaryAtPath:compatibleArchitecture:error:`,
  `CMBinaryWriter::rewriteFatBinaryFile:error:` e
  `_replaceItemAtSourcePath:destinationPath:error:`. Busca de strings sem nenhum
  `codesign` nos frameworks de limpeza.
- **E18** — busca de `SystemPolicyAppBundles`/`Privacy_AppBundles` no executável e
  nos frameworks do CleanMyMac: nenhuma ocorrência.

## Divergências conhecidas
- **Lista de ignorados da base de regras:** substituída pela nossa (`com.apple.*`,
  Chrome, MAS, lista do usuário). O resultado nesta máquina deve bater com a baseline.
- **Arquitetura:** o CleanMyMac decide pelo slice com que ele mesmo foi executado
  (constante de compilação) mais o Rosetta. Nós usamos a arquitetura do hardware
  (`sysctl hw.optional.arm64`). Em Apple Silicon o resultado é igual.
- **Segurança extra:** se o executável principal de um app em Apple Silicon não tiver
  `arm64` (por exemplo, `arm64e` + `x86_64`), o CleanMyMac cairia para `x86_64` e
  removeria o `arm64e`. **Nós pulamos o app.** Também verificamos a assinatura
  antes e depois e desfazemos se ela quebrar (ver "Remoção").
- **Fontes de apps:** sem acesso à API privada `_LSCopyAllApplicationURLs`, usamos o
  Spotlight (home e `/Applications`) mais a varredura recursiva de `/Applications` e
  `~/Applications`. Um app registrado no LaunchServices, fora desses lugares e não
  indexado pode faltar.
- **Gerenciamento de Apps:** o CleanMyMac não pede; nós pedimos (decisão do design).

## Checklist de testes
Fixtures em pasta temporária. Binários fat feitos com `clang -arch arm64 -arch x86_64`
(ou `lipo -create`), e `root` do `ScanContext` apontando para a fixture.
1. `App.app/Contents/MacOS/App` fat `arm64+x86_64` → 1 item `App.app` com 1 filho; tamanho = `size` da fatia `x86_64`; `keepArch = arm64`; `isRecommended = false`.
2. Mesmo app com `Contents/Frameworks/F.framework/Versions/A/F` fat → 2 filhos; tamanho do app = soma.
3. `Contents/Frameworks/libx.dylib` fat → **ignorado** (tem extensão).
4. Executável fat sem bit `+x` → ignorado.
5. Symlink executável apontando para um fat → ignorado.
6. `Contents/Resources/tool` fat, listado em `Contents/_CodeSignature/CodeResources` (`files2`) sem `optional` → ignorado; com `optional = true` → vira filho.
7. Executável principal thin `arm64` → nenhum item.
8. Executável principal fat, mais um script de shell executável sem extensão em `Contents/MacOS/` → **app pulado**.
9. Helper thin só `x86_64` dentro de app cujo principal é fat → **app pulado**.
10. Binário aninhado fat `arm64e+x86_64` (sem `arm64`) → **app pulado**.
11. Binário fat `arm64+arm64e+x86_64` → filho com tamanho `arm64e + x86_64`; a remoção mantém só `arm64`.
12. Principal `arm64e+x86_64` em Apple Silicon → app pulado (nossa divergência).
13. Pasta `.lproj` com um executável fat dentro → ignorado (não desce em `.lproj`).
14. Bundle com `chflags uchg` → pulado.
15. Bundle id `com.apple.foo`, `com.google.Chrome`, `com.google.Chrome.app.abc`, `com.setapp.teaser` → pulados.
16. App com `Contents/_MASReceipt/receipt` → pulado.
17. App em `$ROOT/Library/Foo.app`, `~/Library/Foo.app`, `/Applications/Bar.app/Contents/Helpers/Foo.app`, `/Applications/X.bundle/Foo.app` → fora do escopo. App em `~/Downloads/Foo.app` e `/Applications/Setapp/Foo.app` → dentro do escopo.
18. App com o bundle id em `Architectures for x86_64` no plist do LaunchServices da fixture → pulado.
19. Remoção em cópia: depois de afinar, `lipo -archs` do binário = `arm64`; `mode` igual ao original; `codesign --verify --deep --strict` continua passando numa cópia (`ditto`) de app real assinado; o `open -W -a` da cópia não dá erro de lançamento.
20. Remoção com o arquivo sem permissão de escrita → resultado "precisa de privilégio" (vai para o lote admin), sem deixar `<arquivo>.lipo`/temporário para trás.
21. Simulação (dry-run) → nenhum byte alterado e o log marcado.
