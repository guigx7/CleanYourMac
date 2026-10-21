# Remoção no módulo Aplicativos (Desinstalar, Redefinir, Sobras, Instaladores)

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83). **Só análise estática**:
nunca clicamos em Desinstalar, Remover, Redefinir nem Atualizar no CleanMyMac.

## Visão geral

### O que o CleanMyMac faz
- Uma tarefa de remoção (`ApplicationRemovalTaskFactory` → `RemovalTask`)
  recebe os recursos marcados e despacha cada um para um **removedor por
  tipo** [E1]:

  | Removedor | Usado para |
  |---|---|
  | `FileApplicationResourceRemover` | arquivos e pastas comuns (bundle, suporte, caches, contêiner…) |
  | `ApplicationPreferencesResourceRemover` | preferências (com `/usr/bin/defaults`, para o `cfprefsd` não regravar) [E2] |
  | `ApplicationLoginItemResourceRemover` | itens de início (descarrega o item) [E3] |
  | `ApplicationStartupItemResourceRemover` | agentes/daemons do launchd |
  | `ApplicationPackageReceiptResourceRemover` | recibos de pacote |
  | `ApplicationDockIconResourceRemover` | ícone no Dock (edita as preferências do Dock e reinicia o Dock) [E4] |
  | `ExcludedBundleRemover` | apps da App Store que a Apple não deixa remover (erro explicativo) [E5] |
  | `ApplicationBundleSelfRemover` | o próprio CleanMyMac (serviço à parte) [E6] |

- **Destino: apagar de vez.** O módulo usa `FileRemover`, que chama
  `removeFileAndHandleLockAtPath:error:` (destrava arquivos bloqueados antes).
  Ele não importa o `MoveToTrashFileRemover`, que existe em CleaningCore [E7].
- **Sem permissão:** `PrivilegedFileRemover` tenta pelo helper
  (`RemoveFileRequest`) e pede autorização se ele não estiver instalado [E7][E8].
- **launchd:** antes de remover o plist de um agente do usuário, ele roda
  `/usr/bin/env launchctl bootout gui/<uid>/<label>` (domínio da sessão, sem
  root). Para o que é do sistema, pede ao helper `RemoveLaunchAgentRequest(url)`,
  que faz `/bin/launchctl unload <plist>` como root e apaga. Uma falha de
  descarregamento vira uma "dependência" que impede a remoção do app e é
  mostrada ao usuário [E9][E10].
- **Recibos:** pede ao helper `RemovePackageReceiptRequest(packageID)`, que roda
  `/usr/sbin/pkgutil --forget <id>` [E10][E11].
- **Apps abertos:** antes de desinstalar ou atualizar, abre um diálogo com os
  apps em execução ligados aos bundle IDs da operação (`NSRunningApplication`),
  com ações para encerrar cada app, encerrar todos, forçar o encerramento e
  seguir sem encerrar. Apps que não podem ser encerrados aparecem num estado
  próprio [E12].
- **Simulação:** há removedores de depuração que só registram a remoção
  (`DebugApplicationResourceRemover`, `DebugFileRemover`), escolhidos por uma
  configuração [E13].
- **Apps de sistema protegidos:** o bundle não pode ser removido, só os
  arquivos (redefinir). Plug-ins em pasta protegida mandam o usuário ao Finder
  [E14].

## Remoção (regras nossas)

### Destino por operação (design)
| Operação | Destino |
|---|---|
| Desinstalar (bundle + arquivos marcados) | **Lixo** do volume do item |
| Redefinir (só arquivos, mantém o app) | **Lixo** |
| Sobras | **Lixo** |
| Instaladores (DMG) | **apagar na hora** (como na Limpeza) |
| Itens de sistema movidos pelo helper | **Lixo do usuário que pediu** (`/Users/<usuário>/.Trash`, ou `.Trashes/<uid>` no volume do item, se não for o de inicialização) |

- No app (sem root): `FileManager.trashItem(at:resultingItemURL:)`, que
  escolhe o Lixo certo do volume. Se falhar por permissão, o item vai para o
  helper (`trash`). Nunca caímos para "apagar de vez" sem avisar.
- Itens de iCloud/Arquivos sob demanda: `trashItem` também serve. Se o arquivo
  só existir na nuvem, ele vai para o Lixo do iCloud. O registro anota isso.
- **Divergência intencional**: o CleanMyMac apaga de vez [E7].

### Ordem de uma desinstalação
1. **Apps abertos** (ver abaixo). Sem fechar tudo, nada é removido daquele app.
2. **launchd**: para cada plist marcado, descarregar e depois mandar o plist para o
   Lixo:
   - em `~/Library/LaunchAgents`: `launchctl bootout gui/<uid> <caminho-do-plist>`
     no app (sem root). Erro "não carregado" (`ESRCH`, código 3) conta como
     sucesso;
   - em `/Library/LaunchAgents`, `/Library/LaunchDaemons` e
     `/Library/PrivilegedHelperTools`: helper `launchdBootout`.
3. **Itens de início** (BTM/`SMAppService` e `LSSharedFileList`): só o que a
   spec `related-files.md` listar. Remover a entrada não apaga arquivos.
4. **Arquivos** marcados → Lixo (app ou helper `trash`).
5. **Recibos** marcados → helper `forgetPackage`.
6. **Bundle** do app → Lixo, por último. Se algo antes falhou, o bundle
   **fica**, para o usuário poder tentar de novo sem ficar com um app quebrado
   e meio removido.
7. Ícone no Dock: o macOS some com o ícone de um app que foi para o Lixo
   só quando o Dock recarrega. Na v0.2 **não** editamos as preferências do Dock
   nem reiniciamos o Dock (fica como divergência). Um app que já não existe
   aparece com um "?", e o usuário tira à mão.
8. Registro de cada passo em `~/Library/Logs/CleanYourMac/` (caminho de
   origem, destino no Lixo, operação, resultado).

### Redefinir
- Igual à desinstalação, sem os passos 2 (launchd) e 6 (bundle) para o
  **bundle** do app. Plists do launchd do app só entram se marcados, com o
  mesmo tratamento.
- Confirmação extra quando houver itens marcados de Dados do Usuário ou
  Contêiner (design; ver `UninstallerScanner.needsResetConfirmation`).

### Sobras
- Arquivos → Lixo; plists do launchd seguem o passo 2; recibos seguem o passo 5.
  Não há app aberto para fechar (o app não existe mais).

### Instaladores
- `unlink` na hora, só para arquivo comum `.dmg` dentro das raízes de
  `installers.md`. DMG montado não pode ser marcado.

### Apps abertos
- Antes de Desinstalar, Redefinir (e, na etapa 2, Atualizar): listar os
  `NSRunningApplication` cujo `bundleIdentifier` é o do app ou de um helper
  dele (bundles dentro de `Contents/` do app), mais os processos cujo
  executável está dentro do bundle.
- Diálogo nosso: encerrar (por app), encerrar todos e cancelar. **Forçar
  o encerramento** só aparece depois de uma tentativa normal sem resposta em
  10 s e pede confirmação. A opção de seguir sem encerrar **não existe** para
  desinstalar. Para Redefinir, existe, com um aviso de que o app pode regravar os
  arquivos.
- Encerrar = `terminate()`; forçar = `forceTerminate()`. Nunca `kill` como root.
- O próprio CleanYourMac não entra nessa lista (não pode ser desinstalado por
  ele mesmo na v0.2; redefinir a si mesmo fica bloqueado enquanto ele estiver
  aberto, ou seja, sempre).

## Helper: três operações novas (design)
O helper (`HelperExecutor`) ganha três casos em `PrivilegedCommand`. Todos
seguem as travas atuais (`validated`: caminho absoluto, sem `\n`, pai
resolvido, último componente **não** seguido, dentro de um prefixo permitido,
nunca vital) e mais as abaixo.

### `trash(URL, requester: uid_t)`
- Move para o Lixo do usuário que pediu: `/Users/<nome do uid>/.Trash` no volume
  de inicialização, ou `<volume>/.Trashes/<uid>` em outro volume (criado com
  dono `uid` e modo `0700` se faltar). Nome livre (`x`, `x 2`, …) para não
  sobrescrever.
- Feito com `rename(2)` no mesmo volume. Entre volumes, **recusa**: o helper
  não copia árvores.
- Depois de mover, `lchown -R` para `uid` (para o usuário poder esvaziar o
  Lixo). Symlinks nunca são seguidos.
- O `uid` vem da conexão XPC (`auditToken`), não da mensagem.
- Prefixos permitidos para esta operação: só os de "app e arquivos de app"
  (`/Applications`, `/Library/Application Support`, `/Library/Caches`,
  `/Library/Preferences`, `/Library/Logs`, `/Library/LaunchAgents`,
  `/Library/LaunchDaemons`, `/Library/PrivilegedHelperTools`,
  `/Library/Audio/Plug-Ins`, `/Library/Internet Plug-Ins`,
  `/Library/PreferencePanes`, `/Users/<uid>/…`). Nunca `/System`, `/usr`,
  `/bin`, `/sbin`, `/private/var/db` nem a pasta de outro usuário.

### `launchdBootout(plist: URL)`
- Só plists diretos de `/Library/LaunchAgents`, `/Library/LaunchDaemons` ou
  `/Library/PrivilegedHelperTools`, sem symlink, com extensão `plist`.
- O helper **relê** o plist e pega `Label`. Recusa se o `Label` estiver vazio,
  começar com `com.apple.` ou se o nome do arquivo começar com `com.apple.`.
- Daemon (`/Library/LaunchDaemons`): `launchctl bootout system/<Label>`.
  Agente (`/Library/LaunchAgents`): `launchctl bootout gui/<uid>/<Label>`, com
  o `uid` da conexão. "Não carregado" conta como sucesso.
- Só descarrega; o plist vai para o Lixo depois, num `trash` separado.

### `forgetPackage(id: String)`
- `id` só com `[A-Za-z0-9._-]`, sem `..`, e **nunca** `com.apple.*`.
- O helper confere que o recibo existe (`pkgutil --pkg-info <id>` com código 0)
  e roda `/usr/sbin/pkgutil --forget <id>`. Não apaga os arquivos do pacote,
  só o registro.
- Recusa se o volume do recibo não for `/`.

### Travas comuns
- Só itens do **app selecionado**: o app manda, junto com cada comando, o
  bundle ID do app. O helper revalida o vínculo pelo que consegue ver como
  root: o nome do plist ou o `Label` começa com o bundle ID, ou o
  `Program`/`ProgramArguments[0]` aponta para dentro do bundle do app; recibo
  cujo `id` começa com o prefixo do bundle ID ou do Team ID do app. Sem
  vínculo, recusa. A regra de vínculo de cada tipo está em `related-files.md`.
- Nunca através de links: `lstat` em cada componente revalidado e
  `O_NOFOLLOW` onde houver abertura de arquivo.
- Uma operação por item, resultado por item (`ok` / `refused` / `failed`).
  Recusado ≠ falhou: a UI diz "não permitido".
- Tudo vai para o registro do helper e para o registro da operação.

## Alertas e selos
- Confirmação antes de qualquer remoção, com o total e o destino ("vai para o
  Lixo" / "será apagado").
- Confirmação extra no Redefinir com Dados do Usuário/Contêiner.
- App da App Store que o sistema não deixa mover para o Lixo: o item falha com
  uma explicação nossa (mesmo caso do `ExcludedBundleRemover` do CleanMyMac),
  e os arquivos dele seguem a regra normal.
- App da Apple protegido: sem opção de desinstalar, só redefinir.
- Plug-in em pasta protegida pelo SIP: botão "Mostrar no Finder", sem remoção.

## requiresAdmin
- Análise: não
- Remoção: só para itens fora da pasta do usuário e de `/Applications` com
  dono diferente. Sem helper aprovado, esses itens ficam desmarcados e com aviso.

## Evidências
- **E1**: nomes de classe em ApplicationsModule (`_OBJC_CLASS_$_…`):
  `ApplicationRemovalTaskFactory`, `FileApplicationResourceRemover`,
  `ApplicationPreferencesResourceRemover`, `ApplicationLoginItemResourceRemover`,
  `ApplicationStartupItemResourceRemover`, `ApplicationPackageReceiptResourceRemover`,
  `ApplicationDockIconResourceRemover`, `ExcludedBundleRemover`,
  `ApplicationBundleSelfRemover`, `LaunchAgentRemovalDependency`,
  `UnusedDiskImagesRemoval`, `RemovalProgressProxy`; strings `RemovalTask`,
  `ConfigDependentApplicationResourceRemover`.
- **E2**: string `/usr/bin/defaults` em ApplicationsModule e UninstallerScanning.
- **E3**: string de erro de descarregamento de item de início em ApplicationsModule.
- **E4**: strings `com.apple.dock.tmp.`, `/usr/bin/defaults`, `/usr/bin/killall`
  e um erro de remoção do ícone do Dock, em sequência, em ApplicationsModule.
- **E5**: chave `error_description_bundle_exclusion_app_cannot_be_removed_format`
  e classe `ExcludedBundleRemover`.
- **E6**: framework `ApplicationSelfRemoverService` e as chaves
  `uninstalling_cmm_*`.
- **E7**: `nm -u` de ApplicationsModule: importa `FileRemover`,
  `PrivilegedFileRemover` e `ConfigDependentRemover` de CleaningCore, sem
  `MoveToTrashFileRemover`. Funções decompiladas `FileRemover.remove(at:)` →
  `removeFileAndHandleLockAtPath:error:` e `MoveToTrashFileRemover.remove` →
  `trashItemAtURL:resultingItemURL:error:` (CleaningCore).
- **E8**: requisições `RemoveFileRequest`, `FileMoveRequest(source:destination:)`
  e `PrivilegedAccessTaskRequest` em PrivilegedOperationsPerformerService; o
  erro de agente não autorizado em `PrivilegedFileRemover`.
- **E9**: strings em sequência em ApplicationsModule: `/usr/bin/env`,
  `launchctl`, `bootout`, `gui/`, além de `id`/`-u`; e
  `/Library/PrivilegedHelperTools/`.
- **E10**: símbolos `PrivilegedOperationsClient.removeLaunchAgent(at:)` e
  `removePackageReceipt(with:)`, além de `RemoveLaunchAgentRequest(url:)` e
  `RemovePackageReceiptRequest(packageID:)` (PrivilegedOperationsPerformerService).
  Strings do helper `com.macpaw.CleanMyMac-setapp.Agent`: `/bin/launchctl`,
  `unload`, `unloadLaunchAgentWithConfigPath:error:`,
  `_unloadAgentAtPath:shouldDisable:`.
- **E11**: strings do helper: `/usr/sbin/pkgutil`, `--forget`, `PANPKGUtility`,
  `PackageReceiptPrivilegedOperations`; em UninstallerScanning, `CMReceiptFetcher`.
- **E12**: ApplicationsTerminator: `TerminatorViewModel(bundleIDs:terminator:subtitle:tracker:)`,
  `terminateAll()`, `ignore()`, `NSRunningApplication`; TerminatorUI: quatro botões (encerrar um, encerrar todos,
  forçar, ignorar) e um estado de app que não pode ser encerrado (chaves `ButtonTitle_*` e `AppTerminator_*`); chave
  `updater_terminator_subtitle`.
- **E13**: strings `DebugApplicationResourceRemover`, `DebugFileRemover` e um
  prefixo de log de simulação; `ConfigDependentRemover(throwIfFailCleanEnabled:debugRemover:realRemover:removeAction:)`.
- **E14**: chaves `protected_system_application_info` e `protected_plugin_info`.

## Divergências conhecidas
- **Lixo × apagar de vez** (Desinstalar, Redefinir, Sobras): intencional
  (design). Instaladores: os dois apagam de vez.
- **Dock**: o CleanMyMac edita `com.apple.dock` e reinicia o Dock; nós não,
  na v0.2.
- **launchd do usuário**: o CleanMyMac descarrega pelo `Label` (`gui/<uid>/<label>`);
  nós descarregamos pelo caminho do plist (`bootout gui/<uid> <plist>`), que não
  exige confiar no `Label` lido. Para o sistema, o CleanMyMac usa `unload`
  (obsoleto); nós usamos `bootout system/<Label>` com o `Label` relido pelo
  helper.
- **Ignorar apps abertos**: o CleanMyMac deixa continuar; nós não deixamos na
  desinstalação.
- **Preferências**: o CleanMyMac usa `defaults` para o `cfprefsd` não
  regravar. Nós mandamos o plist para o Lixo **depois** de fechar o app; se o
  app estiver fechado, o `cfprefsd` não regrava. Avaliar `defaults delete
  <domínio>` antes de mover, caso a paridade mostre o plist voltando.
- Nunca removemos o próprio CleanYourMac (o CleanMyMac tem um fluxo de
  autodesinstalação).

## Checklist de testes
1. Desinstalar o app de teste `Foo.app` (pasta temporária) com 3 arquivos
   relacionados → os 4 vão para o Lixo falso dos testes; nada apagado de vez.
2. Falha ao mover um relacionado → o bundle **não** é movido; o registro tem a
   falha.
3. Redefinir → o bundle fica; os relacionados vão para o Lixo.
4. Instalador → `unlink`; não aparece no Lixo.
5. Helper `trash` com symlink no último componente → `refused`.
6. Helper `trash` para `/System/Library/x` ou `/Users/outro/x` → `refused`.
7. Helper `trash` entre volumes → `refused`.
8. Helper `launchdBootout` com `Label = com.apple.foo` → `refused`; com o
   arquivo em `/Library/LaunchAgents/sub/x.plist` → `refused` (não é filho
   direto).
9. Helper `forgetPackage("com.apple.pkg.X")` → `refused`; `"a;rm -rf /"` →
   `refused`.
10. Comando para um item sem vínculo com o bundle ID informado → `refused`.
11. App aberto (processo de teste) → o diálogo aparece; Cancelar → nada removido.
12. `uid` da mensagem diferente do da conexão → vale o da conexão.
13. Modo simulação (Debug) → nenhum arquivo é tocado; o registro diz "simulado".
