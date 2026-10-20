# Versões de Documentos (`documentVersions`)

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26 (Darwin 25.6.0), análise de 20/10/2026.
Neste Mac o grupo apareceu com **0 KB**, então quase tudo aqui vem da análise
estática (ver "Divergências conhecidas").

## Locais varridos
Nenhuma pasta é percorrida diretamente. O grupo trabalha em duas etapas:

1. **Busca no Spotlight** (consulta de metadados) por documentos de tipos
   específicos, usando o predicado `kMDItemContentTypeTree == <UTI>` para cada
   UTI da tabela abaixo (E1, E2). O escopo é o computador local: neste Mac, a
   mesma consulta encontra arquivos `.key` em `/System/Library/Tcl/...`, o que
   mostra que a busca não se limita a `~` (E9).
2. Para cada documento encontrado, a lista de **versões antigas** vem da API do
   sistema de versões (`NSFileVersion.otherVersionsOfItem(at:)`), que lê o
   repositório de revisões do volume (`/.DocumentRevisions-V100`, que pertence a
   root e é ilegível para o usuário). O app **não** lê esse repositório nem o
   banco `db-V1/db.sqlite` diretamente. FMDB/FMResultsMapper existem no
   framework, mas servem a outra tarefa (contas do Dropbox), não a este grupo (E3, E4).

Tabela de aplicativos e tipos. É fixa no código e não vem da base cifrada (E1):

| App (nome exibido) | Bundle id do app | UTIs buscadas |
|---|---|---|
| Sketch | `com.bohemiancoding.sketch3` | `com.bohemiancoding.sketch.drawing.single`, `com.bohemiancoding.sketch.drawing` |
| Pages | `com.apple.iwork.pages` | `com.apple.iwork.pages.sffpages`, `com.apple.iwork.pages.pages`, `com.apple.iwork.pages.pages-tef` |
| Keynote | `com.apple.iwork.keynote` | `com.apple.iwork.keynote.sffkey`, `com.apple.iwork.keynote.key`, `com.apple.iwork.keynote.key-tef` |
| Numbers | `com.apple.iwork.numbers` | `com.apple.iwork.numbers.numbers`, `com.apple.iwork.numbers.sffnumbers`, `com.apple.iwork.numbers.numbers-tef` |

## Inclusão
- Os resultados do Spotlight são agrupados por UTI. Cada UTI é mapeada para o
  bundle id do app pela tabela acima, e os arquivos de todas as UTIs de um mesmo
  app vão para o mesmo grupo (E2).
- Cada caminho encontrado vira um **documento** (nível 2), salvo se a base o
  ignorar (E5).
- Para cada documento, as versões vêm de `otherVersionsOfItem` (a versão atual
  nunca entra), filtradas para manter só as que têm `modificationDate`. Elas
  são ordenadas por data de modificação, **da mais nova para a mais antiga** (E3, E6).
- Cada versão com tamanho > 0 vira um item-folha (nível 3). Uma versão de
  tamanho 0 é descartada (E3).
- O documento só entra se a soma das versões for > 0, e o app só entra se tiver
  pelo menos um documento com tamanho > 0 (E3).

## Exclusão
- Documentos que estão dentro de pastas do Dropbox são filtrados já na busca:
  um filtro descobre as pastas das contas Dropbox por `~/.dropbox/info.json`
  (E7). A nossa regra é ignorar os caminhos sob as pastas de conta listadas
  nesse `info.json`, quando o arquivo existir.
- A base de conhecimento (cifrada) pode ignorar um **app inteiro** (consultada
  pelo bundle id) ou um **documento** (consultada pelo caminho) (E5, E8). A
  nossa regra equivalente: a lista de ignorados começa vazia e é configurável,
  com chave por bundle id e por prefixo de caminho.
- Versões sem data de modificação (E6).

## Recomendado
App e documento nunca vêm marcados por conta própria: eles ficam marcados
quando os filhos estão. A marcação é **por versão** e segue a regra de
"rarefazer" versões próximas no tempo (E10). Com a lista ordenada da mais nova
(índice 0) para a mais antiga (índice n-1):

- o índice 0 (a versão antiga mais recente) **nunca** é recomendado;
- o índice n-1 (a versão mais antiga) **nunca** é recomendado;
- cada índice intermediário `i` é recomendado se
  `|data(i) − data(i−1)| < 14400 s` (4 horas), comparando sempre com a vizinha
  imediatamente mais nova, esteja ela marcada ou não.

Com isso, ficam desmarcadas a primeira e a última versões e as que estão
separadas da vizinha mais nova por 4 h ou mais. As demais vêm marcadas.

Os índices contam as versões já ordenadas e filtradas por data, **antes** de
descartar as de tamanho 0. Na prática as de tamanho 0 são raras, mas, para ter
paridade, aplique a regra sobre a lista completa e depois remova as de tamanho 0.

## Agrupamento e nome exibido
Três níveis (E3, E11):
1. **App**: nome da tabela (Sketch, Pages, Keynote, Numbers) e ícone do app
   pelo bundle id (via Launch Services; se o app não estiver instalado, usar o
   ícone genérico de aplicativo).
2. **Documento**: nome do arquivo (o último componente, com extensão) e ícone
   do arquivo (`NSWorkspace.icon(forFile:)`).
3. **Versão**: o nome é a data de modificação da versão, formatada com estilo
   de data **médio** e estilo de hora **médio**, sem formatação relativa
   ("hoje", "ontem"), na localidade do usuário (E12). O ícone é o do documento.

Tamanho do app = soma dos documentos. Tamanho do documento = soma das versões.

## Cálculo de tamanho
Para cada versão: se o objeto da versão expõe um tamanho próprio, usa-se esse
valor. Senão, mede-se o tamanho em disco do conteúdo da versão (a URL da versão,
dentro do repositório de revisões), com o mesmo medidor dos outros grupos (E13).
Na nossa implementação, use o tamanho alocado da URL da versão
(`NSFileVersion.url`). Se ela for ilegível, use 0, e nesse caso a versão é
descartada.

## Remoção
Cada versão marcada é removida com `NSFileVersion.remove()` (o
`removeAndReturnError:` da API), uma por vez. Não se apaga arquivo nenhum
diretamente, e o documento atual não é tocado (E14). Isso não passa pelo Lixo e
é definitivo. Se a remoção falhar, o erro aparece por versão com uma mensagem
genérica do tipo "não foi possível remover a versão X" (E15). O app dono não
precisa estar fechado: o código não verifica isso.

## Alertas e selos
Nenhum alerta nem selo neste grupo (não há confirmação de seleção registrada
para estes modelos).

## requiresAdmin
- Análise: não (Spotlight + API de versões no contexto do usuário).
- Limpeza: não (a API de versões cuida do repositório protegido).

## Evidências
- **E1** — pseudocódigo de `CMDocumentVersionsScanTask initWithKnowledgeBase:` e
  strings do SystemJunkScanning: o construtor monta a especificação com 4 apps
  (nome, bundle id e conjunto de UTIs) e usa um controlador de busca de metadados.
- **E2** — pseudocódigo de `_groupItemsFromMetadataSearchResult:specification:` e
  do bloco de busca: busca por tipos, resultados agrupados por tipo e remapeados
  para o bundle id do app. Strings do SharedObjcUtils: `kMDItemContentTypeTree == %@`,
  `searchFilesWithTypes:filter:`.
- **E3** — pseudocódigo de `CMDocumentVersionsScanTask scan`: laço app →
  documento → versão, ordenação por `modificationDate` decrescente, tamanho
  por versão, descarte de tamanho 0, filhos adicionados só com tamanho > 0.
- **E4** — strings do SystemJunkScanning: `FMResultsMapper` aparece junto da
  `CMDropboxCacheScanTask`. Não há string `DocumentRevisions` nem `db.sqlite`
  neste framework.
- **E5** — pseudocódigo de `_createDocumentVersionFilesWithMetadataItemPath:`:
  consulta da base pelo caminho. Documento criado com autoselected = não.
- **E6** — pseudocódigo de `_findVersionsForFileAtURL:` e do bloco de filtro:
  `otherVersionsOfItemAtURL:`, mantendo só as versões com data.
- **E7** — pseudocódigo de `scan` (instancia `CMDropboxFilter` e o passa à busca)
  e strings do SharedObjcUtils (`CMDropboxFilter`, `.dropbox/info.json`).
- **E8** — pseudocódigo de `DocumentVersionsKnowledge isIgnoreItem:`/`shouldIgnoreURL:`
  (JunkCleanupModule): delega à base cifrada por categoria.
- **E9** — leitura do disco: `mdfind` com `kMDItemContentTypeTree == 'com.apple.iwork.keynote.sffkey'`
  retorna 2 arquivos em `/System/Library/Tcl/...`, e os demais tipos retornam 0.
- **E10** — pseudocódigo de `CMDocumentVersionsSelectionRule selectionIndexesForObjects:`
  e do seu bloco, mais a constante double `14400.0` lida em `__TEXT,__const`
  (`otool`).
- **E11** — pseudocódigo de `scan`: `CMDocumentApplication` criado com
  autoselected = não, e o nome vem de `applicationNameForBundleIdentifier:`.
  Símbolos `DocumentVersionsApplicationModel` / `DocumentVersionFileModel` /
  `FileVersionModel`.
- **E12** — pseudocódigo de uma função do JunkCleanupModule que formata a
  `modificationDate` de uma versão com um formatador de data média, hora média e
  sem formatação relativa.
- **E13** — pseudocódigo do auxiliar de `revisionSizeWithFileSizer:cancellationFlag:`:
  usa o `size` da versão se existir e, senão, o medidor sobre a URL da versão.
- **E14** — pseudocódigo do JunkCleanupModule (`FUN_00019d94`, chamado pelo
  removedor de versões): chama `removeAndReturnError:` no `NSFileVersion`.
  Strings `FileVersionRemover` e `ConfigDependentFileVersionRemover`.
- **E15** — chave de localização `error_description_document_version_generic`
  (sentido: falha genérica ao remover a versão de um documento).
- **E16** — baseline `Detritos do Sistema/Versões de Documentos.txt`: grupo com
  0 KB e a tela "nada para limpar".

## Baseline observada
- Grupo "Versões de Documentos": **0 KB**, sem itens (estado vazio). Neste Mac,
  o Spotlight só encontra 2 `.key` do sistema (no `/System/Library/Tcl`), que
  não têm versões antigas.

## Divergências conhecidas
- **Sem observação real de itens.** A estrutura de 3 níveis, a formatação da
  data e a regra das 4 horas vêm só do código. Para conferir a paridade, crie um
  documento Pages/Keynote/Numbers, salve várias vezes (com intervalos menores e
  maiores que 4 h, ou use a navegação de versões), rode a análise do CleanMyMac
  e compare.
- **Base cifrada:** a lista de apps/documentos ignorados vem do `info.cmmkb`,
  que não lemos. Começamos com a lista vazia.
- **Escopo do Spotlight:** inferido do comportamento (computador local). O
  escopo exato configurado no CleanMyMac não foi confirmado. Volumes não
  indexados ficam de fora nos dois apps.
- **Filtro do Dropbox:** reimplementado só a partir do `info.json`. Pode
  divergir se o Dropbox estiver em File Provider (`~/Library/CloudStorage`).
- **Tamanho de versão:** o CleanMyMac usa um tamanho interno da versão quando
  ele existe, um valor privado que não usamos. Medimos a URL da versão, e os
  valores podem diferir um pouco.

## Checklist de testes
1. Documento Pages com 0 versões antigas → nenhum item. O app não aparece e o grupo fica com 0 KB.
2. Versões (mais nova → mais antiga) com datas T, T−1h, T−2h, T−10h, T−11h →
   marcadas: índices 1 (1 h da vizinha) e 2 (1 h da vizinha). Desmarcadas: 0 (a
   primeira), 3 (8 h da vizinha) e 4 (a última).
3. Exatamente 2 versões → nenhuma recomendada.
4. 3 versões com diferenças de 4 h exatas (14400 s) → a do meio **não** é
   recomendada (a comparação é estrita `<`).
5. 3 versões T, T−3h59m, T−8h → a do meio é recomendada.
6. Versão sem `modificationDate` → descartada, e os índices são recalculados sem ela.
7. Versão com tamanho 0 → não aparece como item, mas conta na posição usada
   pela regra de seleção.
8. Documento cujo caminho está sob uma pasta de conta Dropbox do `info.json` → ignorado.
9. Arquivos `.numbers` e `.sffnumbers` → caem no mesmo grupo "Numbers".
10. Arquivo `.sketch` → grupo "Sketch", com o ícone do app `com.bohemiancoding.sketch3`.
11. Nome da versão → data de modificação no estilo médio de data e hora (ex.: em
    pt-BR, "20 de out. de 2026 14:57:03"), nunca "Hoje".
12. Limpeza de uma versão → `NSFileVersion.remove()` é chamado nela. O
    documento atual e as versões não marcadas continuam.
13. Falha ao remover → erro por versão, e as demais seguem.
