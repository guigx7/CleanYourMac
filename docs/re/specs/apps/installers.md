# Instaladores não usados (`appInstallers`)

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83). Análise de 2026-10-21
(reconhecimento `re-notes/ax/apps-*` das 14:02–14:05 UTC). Grupo da seção
Sobras do Gerenciador de Aplicativos, também resumido num cartão da tela de
resultados (ver `results-screen.md`).

## Visão geral
É uma busca no **índice do Spotlight** por imagens de disco no formato UDIF
(`.dmg`) dentro da pasta do usuário e de `/Applications`. Cada arquivo
encontrado vira um item plano, **desmarcado**. Não existe regra de "não usado"
no código: o critério é apenas "é um DMG nessas raízes e não está numa pasta
ignorada" [E1][E2][E3]. Apesar do nome do grupo, `pkg`, `mpkg`, `zip` e
`.app` soltos **não** entram [E1].

## Locais varridos
- Escopos da consulta: `NSMetadataQueryUserHomeScope` (a pasta do usuário
  inteira, incluindo `~/Library`, `~/Downloads`, `~/Desktop` etc.) e
  `/Applications/` [E2].
- **Não** entram `/Library`, `/Users/Shared`, outros volumes nem a pasta de
  outros usuários. Os DMGs do sistema em `/Library/Developer/...` (imagens de
  dispositivo do Xcode) ficam de fora por isso [E2][E8].
- A busca não percorre o disco: depende do Spotlight. Pasta não indexada (ou
  volume com indexação desligada) não aparece [E2][E4].

## Inclusão
- Consulta: `kMDItemContentTypeTree == "com.apple.disk-image-udif"`. Os
  resultados são ordenados pelo Spotlight por `kMDItemFSSize` [E1][E4].
- Um item por arquivo, no nível do próprio arquivo (sem agrupamento por app)
  [E3].
- Como o critério é a **árvore de tipos**, um arquivo `.dmg` que o Spotlight
  classifique como UDIF entra, seja qual for o nome. Imagens `.sparseimage`,
  `.sparsebundle`, `.iso` e `.cdr` não têm `com.apple.disk-image-udif` na árvore e
  ficam fora [E1][E4].

## Exclusão
1. **Base de regras**: cada URL passa pelo filtro "ignorar URL" da base do
   grupo. A base está em `info.cmmkb` (cifrada) e não é conhecida [E3].
2. **Pastas do Dropbox**: qualquer caminho que comece com a pasta de uma conta
   do Dropbox configurada na máquina é descartado. As contas vêm do arquivo de
   configuração do próprio Dropbox [E3][E5].
3. Resultado sem caminho é descartado [E3].
4. **Não** há exclusão por: DMG montado, app correspondente já instalado,
   idade, data de último uso ou tamanho mínimo. O DMG do Warp desta máquina é
   listado mesmo com o Warp instalado e o arquivo dentro da pasta de
   atualização automática do próprio Warp [E3][E7][E8].

## Recomendado
- **Nada vem marcado.** Cada item nasce com `autoselected = false` [E3]. Na
  observação, o DMG do Warp aparece desmarcado e o menu de seleção do grupo
  começa em "nenhum" [E7].
- O cartão de resultados oferece só "Revisar" (sem ação direta de remover),
  coerente com nada estar marcado [E7].

## Agrupamento e nome exibido
- Grupo próprio na seção Sobras (ícone de DMG), irmão do grupo de sobras de
  apps [E7].
- Linha: checkbox, ícone de DMG, **nome do arquivo com extensão**
  (`v0.2026.10.14.08.27.stable_02.Warp.dmg`) e tamanho [E7].
- O modelo guarda só nome, URL e tamanho [E6].

## Cálculo de tamanho
- Primeiro `kMDItemPhysicalSize` do Spotlight (tamanho alocado). Sem resposta,
  o contador de bytes comum (blocos alocados, ver `common.md` §1) [E3].
- Conferência: o DMG do Warp tem `kMDItemPhysicalSize` = 187 150 336 bytes, que
  formata como 187 MB, igual à tela. O tamanho lógico (175 893 879) daria
  176 MB [E7][E8].

## Remoção
- CleanMyMac: classe de remoção própria do grupo (`UnusedDiskImagesRemoval`)
  [E9]. O módulo Aplicativos só importa o removedor que **apaga de vez**
  (`FileRemover`, que usa `removeFileAndHandleLockAtPath:error:`), e não o
  removedor que move para o Lixo [E10]. Por isso a remoção do CleanMyMac é,
  muito provavelmente, definitiva. Não foi possível ver a ligação direta entre
  `UnusedDiskImagesRemoval` e o removedor, porque o código Swift não tem símbolos.
- **Regra nossa (design):** instaladores são **apagados na hora** (sem Lixo),
  como na Limpeza. Antes de apagar, revalidamos que o caminho é um arquivo
  comum (não symlink, não pasta) dentro das raízes deste grupo e com extensão
  `dmg`.
- **Regra nossa, DMG montado:** se o arquivo estiver anexado (`hdiutil info
  -plist`, campo `image-path`), o item continua na lista, mas não pode ser
  marcado, com uma explicação. Não ejetamos nada sozinhos. O CleanMyMac não
  faz essa checagem [E3].
- Não precisa de admin: tudo fica na pasta do usuário ou em `/Applications`.
  Se faltar permissão de escrita em `/Applications`, o item falha com erro, sem
  helper.

## Alertas e selos
- Nenhum selo por item [E7].

## requiresAdmin
- Análise: não
- Limpeza: não

## Evidências
- **E1**: strings de `UnusedDiskImagesScanning`. Há uma única constante de tipo
  (`com.apple.disk-image-udif`), o caminho `/Applications/` e
  `kMDItemPhysicalSize`. Não há extensões nem outros UTIs.
- **E2**: função decompilada `CMUnusedDiskImagesScanTask initWithKnowledgeBase:`
  (UnusedDiskImagesScanning). Ela monta a fábrica de consultas com dois
  escopos: a pasta do usuário e `/Applications/`.
- **E3**: funções decompiladas `CMUnusedDiskImagesScanTask scan` e o bloco de
  mapeamento chamado por ela. Busca por tipos com o filtro do Dropbox; para
  cada resultado, consulta a base (ignorar URL) e o filtro do Dropbox, pega o
  tamanho físico do Spotlight com o contador como alternativa e cria a entidade
  com `autoselected` falso.
- **E4**: funções decompiladas `CMMetadataSearchQueryFactory
  createSearchQueryWithFileTypes:` / `factoryWithScopes:` e
  `CMMetadataSearchController searchFilesWithTypes:filter:` (SharedObjcUtils).
  A consulta é uma disjunção de `kMDItemContentTypeTree == <tipo>`, executada de
  forma síncrona (`MDQueryExecute`), com escopo fixo e ordenação por
  `kMDItemFSSize`.
- **E5**: função decompilada `CMDropboxFilter isItemFilteredAtPath:` /
  `filteredPaths` (SharedObjcUtils). Ela compara o prefixo do caminho com as
  pastas das contas do Dropbox.
- **E6**: símbolos de `UnusedDiskImagesModel(name:url:size:)`
  (UnusedDiskImagesScanning).
- **E7**: observação AX `apps-Sobras-v-2026-10-21T140526Z.txt` e
  `apps-results2-2026-10-21T140449Z.txt`: 1 item, nome do arquivo, 187 MB,
  checkbox desmarcado, seleção "nenhum"; o cartão só tem "Revisar".
- **E8**: leitura do disco em 2026-10-21. A mesma consulta com `mdfind
  -onlyin ~` devolve só
  `~/Library/Application Support/dev.warp.Warp-Stable/autoupdate/UbvhWmw/v0.2026.10.14.08.27.stable_02.Warp.dmg`,
  e com `-onlyin /Applications`, nada. `mdls`: `kMDItemPhysicalSize`
  187 150 336, `kMDItemFSSize` 175 893 879. `hdiutil info`: não montado. O
  Warp 0.2026.09.16 está instalado em `/Applications`.
- **E9**: nome de classe `UnusedDiskImagesRemoval` e do nó
  `RemovalModel<UnusedDiskImagesModel, …>` nas strings de ApplicationsModule.
- **E10**: símbolos importados por ApplicationsModule (`nm -u`): `FileRemover`
  e `PrivilegedFileRemover` de CleaningCore, sem `MoveToTrashFileRemover`.
  Na função decompilada `FileRemover.remove(at:)` (CleaningCore), a única
  ação é `removeFileAndHandleLockAtPath:error:`.

## Divergências conhecidas
- **Spotlight × varredura própria.** Para ter paridade, usamos a **mesma
  consulta** ao Spotlight (`MDQuery`/`NSMetadataQuery` com os dois escopos e o
  mesmo predicado). Sem índice (Spotlight desligado), o grupo fica vazio, como
  no CleanMyMac. Não fazemos varredura de disco própria nesta versão.
- **Base cifrada.** As regras de "ignorar URL" deste grupo não são conhecidas.
  Começamos com uma lista vazia e configurável.
- **Dropbox.** Para paridade, lemos as pastas das contas em
  `~/.dropbox/info.json` (chaves `personal.path` / `business.path`) e
  ignoramos DMGs abaixo delas. Sem esse arquivo, não há exclusão.
- **"Não usado"** é um nome de interface: nenhum dos dois apps tenta adivinhar
  se o DMG ainda serve. A falta de marcação por padrão compensa isso. Avaliar
  numa versão futura (fora da paridade) marcar DMGs cujo app já está instalado
  com a mesma versão ou mais nova.
- **DMG montado**: nós bloqueamos a marcação; o CleanMyMac não.
- **Destino**: nós e o CleanMyMac apagamos de vez (o dele é provável, E10).

## Checklist de testes
1. `~/Downloads/a.dmg` (UDIF real, criado com `hdiutil create`) → 1 item,
   desmarcado, nome `a.dmg`, tamanho alocado.
2. `~/Library/Application Support/X/b.dmg` → item (a `~/Library` está no escopo).
3. `/Applications/c.dmg` → item.
4. `/Users/Shared/d.dmg` e `/Library/e.dmg` → fora.
5. `~/Downloads/f.sparseimage`, `g.iso`, `h.pkg`, `i.zip` → fora.
6. DMG dentro da pasta do Dropbox lida de `info.json` → fora.
7. DMG montado → item visível, mas não pode ser marcado.
8. Remover → o arquivo some na hora (não vai para o Lixo); um symlink
   `j.dmg → /alvo` é recusado na revalidação.
9. Sem índice do Spotlight (escopo fictício nos testes) → grupo vazio, sem erro.
10. Paridade nesta máquina: exatamente 1 item, o DMG do Warp, com 187 MB.
