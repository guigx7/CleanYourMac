# Arquivos de Cache do Sistema (`systemCache`)

Regras transversais em `common.md`. O mecanismo de candidatos e de agrupamento
é o mesmo de `user-cache.md` (contexto agrupado por identificador); aqui fica só
o que muda.

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83), análise de 2026-10-20 14:57.

## Composição do grupo na UI
O grupo é a tarefa composta `SystemCachesCompound`, com **duas** subtarefas
simples e nenhuma personalizada ou agrupada: [E1, E2]

| Subtarefa | Raiz | Cai em `systemCache`? |
|---|---|---|
| `SystemCache` | `/Library/Caches` | sim |
| `CoreSymbolicationdCache` | `/System/Library/Caches/com.apple.coresymbolicationd` | sim |

`AppStoreDownloadsCache` **não** está aqui: ele fica em `userCache`.

## Locais varridos
1. `/Library/Caches`: cada filho direto é um candidato. [E3, E4]
2. `/System/Library/Caches/com.apple.coresymbolicationd`: a **própria pasta**
   é um candidato único (não se listam os filhos). [E3, E5]

## Inclusão
- Raiz 1: nível = cada filho direto. Raiz 2: nível = a raiz em si. [E4, E5]
- Um candidato com tamanho 0 só entra quando o helper privilegiado está
  autorizado; sem o helper, ele é descartado. [E6] Como quase tudo aqui é de
  root (`com.apple.iconservices.store` é de `_iconservices`, com modo
  `drwx--x--x`; `com.apple.coresymbolicationd` é de root, com `drwx------`), o
  tamanho só pode ser medido com privilégio. [E7]
- **Regra nossa:** medir com privilégio quando o usuário autorizar
  (`requiresAdminToScan = true`). Sem autorização, valem as mesmas regras do
  CleanMyMac sem helper: medir o que der para ler e descartar candidatos que
  resultem em 0.
- Sem idade mínima e sem tamanho mínimo.

## Exclusão
- `.DS_Store` e a KB, como em `common.md`. [E4]
- **Regra nossa equivalente à KB**, derivada da observação: das entradas de
  `/Library/Caches` nesta máquina (`ColorSync` com 8 KB, `Desktop Pictures`,
  `com.apple.amsengagementd.classicdatavault`, `com.apple.aned`,
  `com.apple.aneuserd` e `com.apple.iconservices.store`), **só**
  `com.apple.iconservices.store` apareceu. [E7, E8] Exclusões:
  - `ColorSync`, `Desktop Pictures`
  - `com.apple.amsengagementd.classicdatavault`, `com.apple.aned`,
    `com.apple.aneuserd` (não foi possível medi-las sem privilégio; ficam fora
    por paridade)
  - nada em `/System/Library/Caches` além de `com.apple.coresymbolicationd`
    (a raiz 2 é a única que toca `/System`)
- Itens protegidos pelo SIP: a `PathPolicy` recusa a remoção (`common.md` 3.3).
  `com.apple.coresymbolicationd` **não** é protegida pelo SIP (o CleanMyMac a
  mostra e remove).

## Recomendado
**Sim** para os dois tipos de candidato. As duas subtarefas herdam o padrão
"autoselected" dos caches. [E6] A baseline mostrou tudo desmarcado
(`common.md` §4).

## Agrupamento e nome exibido
- O identificador é o **último componente do candidato**:
  `com.apple.iconservices.store` e `com.apple.coresymbolicationd`. Não há
  container nesta raiz. [E9]
- Nome exibido: o identificador; se ele for o bundle id de um app instalado, o
  nome do arquivo do app (mesma regra de `user-cache.md`). Nos dois itens
  observados, não há app, e o nome fica cru. [E8]
- Ícone: pasta genérica.
- **Filhos:** a baseline não mostra o botão "mostrar itens incluídos" nem a
  dica inteligente nas células deste grupo. [E8] **Regra nossa:** o item é uma
  folha; ao expandir, não mostra conteúdo (o conteúdo é de root e não é
  listável sem privilégio).

## Cálculo de tamanho
Alocado (`common.md`). Para pastas ilegíveis, o tamanho vem do helper
privilegiado. **Regra nossa:** o lote privilegiado de análise roda `du -sk`
para cada candidato ilegível e converte para bytes (× 1024). Isso equivale ao
tamanho alocado.

## Remoção
- Apagar definitivamente o candidato: a pasta de `/Library/Caches/<x>` inteira,
  e `com.apple.coresymbolicationd` inteira. [common.md E13/E16]
- Precisa de **admin**: todos os itens vão para o lote privilegiado único
  (Task 12). Não há aviso sobre processos em execução. O `coresymbolicationd` e
  o `iconservicesd` recriam os caches. Regra nossa: igual.

## Alertas e selos
Nenhum.

## requiresAdmin
- Análise: **sim**, para medir. Sem admin, o grupo mostra só o que for legível
  e com tamanho > 0.
- Limpeza: **sim**.

## Evidências
- **E1** — pseudocódigo de `CMSystemCachesCompoundTask initWithKnowledgeBase:privilegedOperationsPerformer:`:
  lista de tarefas = `CMSystemCachesScanTask` + `CMCoreSymbolicationdCacheScanTask`,
  identificador `CMSystemJunkScanIdentifierSystemCachesCompound`.
- **E2** — strings do JunkCleanupModule: `systemJunkSystemCacheGroupTitle` e
  `SystemJunkScanIdentifierSystemCachesCompound`.
- **E3** — pseudocódigo de `CMPaths allUsersCaches` (domínio local de
  `NSCachesDirectory` → `/Library/Caches`) e de
  `CMPaths coresymbolicationdCaches` (SharedObjcUtils).
- **E4** — pseudocódigo de `CMCacheScanTask scan` / `contentOfCachesDirectoryURL`
  (filhos diretos, `.DS_Store` e KB).
- **E5** — pseudocódigo de `CMCoreSymbolicationdCacheScanTask contentOfCachesDirectoryURL`:
  devolve só a própria raiz.
- **E6** — pseudocódigo do bloco de `CMCacheScanTask scan` (entra com 0 só se o
  helper estiver autorizado; usa `isResultAutoselectable`) e de
  `CMCacheScanTask isResultAutoselectable` (= sim).
- **E7** — leitura do disco: `ls -la /Library/Caches` (dono e modo; três
  entradas sem permissão) e `ls -ld /System/Library/Caches/com.apple.coresymbolicationd`.
- **E8** — observação da baseline (`Arquivos de Cache do Sistema.txt`): 2 itens,
  sem botão de expandir e sem dica inteligente.
- **E9** — pseudocódigo de `CMCachesContext _groupIdentifierFromURL:`.

## Divergências conhecidas
- O tamanho de itens de root vem de `du -sk` em lote privilegiado, e não de um
  helper residente.
- A lista de exclusões em `/Library/Caches` foi derivada de uma única máquina.
- Item sem filhos visíveis (o CleanMyMac também não os mostra nesta captura).

## Checklist de testes
- `systemCache_childrenOfLibraryCaches`: `$ROOT/Library/Caches/{com.foo.store}`
  (1 MB) → 1 item `com.foo.store`, recomendado, `requiresAdmin`.
- `systemCache_coresymbolicationdIsSingleItem`:
  `$ROOT/System/Library/Caches/com.apple.coresymbolicationd/{a,b}` → **1** item
  `com.apple.coresymbolicationd` com tamanho a + b, sem filhos.
- `systemCache_otherSystemCachesIgnored`: `$ROOT/System/Library/Caches/com.apple.kext.caches`
  → nenhum item.
- `systemCache_excludesColorSync`: `$ROOT/Library/Caches/ColorSync/x` → nenhum
  item.
- `systemCache_unreadableZeroDroppedWithoutAdmin`: um filho com `chmod 000` e
  sem runner privilegiado → nenhum item; com o runner falso devolvendo 4096 →
  1 item de 4096 bytes.
- `systemCache_dsStoreSkipped`: `$ROOT/Library/Caches/.DS_Store` → nenhum item.
- `systemCache_cleanBatchedOnce`: 2 itens selecionados → 1 chamada ao runner
  privilegiado com 2 comandos `remove`.

## Baseline observada
Total: **765 MB**. Itens: `com.apple.coresymbolicationd` 733 MB e
`com.apple.iconservices.store` 32,4 MB, ambos desmarcados.
