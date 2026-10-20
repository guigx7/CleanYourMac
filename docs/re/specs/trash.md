# Lixos (`trash`)

Categoria **Lixos**. Esta spec cobre o Lixo do usuário (inclusive os lixos do
iCloud Drive) e os lixos dos volumes montados. Os Lixos do Mail estão em
`mail-trash.md`.

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2, análise de 2026-10-20.
Neste Mac a categoria veio vazia (ver "Baseline observada").

## Locais varridos

Há duas tarefas de análise, e cada uma gera um bloco (E1).

**A. Lixo do sistema (volume de inicialização)**: as pastas abaixo, **só os
filhos diretos** (E2, E3):
1. `~/.Trash`
2. `~/Library/Mobile Documents/com~apple~CloudDocs/.Trash` (lixo do iCloud Drive)
3. `~/Library/CloudStorage/iCloud Drive/.Trash`
4. `~/Library/Mobile Documents/.Trash`
5. Para cada filho direto `X` de `~/Library/Mobile Documents/`, a pasta
   `X/Documents/.Trash` (lixo dos apps com contêiner no iCloud, ex.: Pages,
   Keynote), **se existir** (E4).

As pastas que não existem são ignoradas sem erro. Os itens ocultos **entram**:
a listagem não pula ocultos, então um `.DS_Store` dentro do Lixo vira item (E3).

**B. Lixos montados**: um bloco por volume que passa no filtro (E5):
- lista os volumes montados, pulando os ocultos;
- o caminho do volume precisa começar com `/Volumes/` (sem diferenciar
  maiúsculas/minúsculas). Assim, o volume de inicialização `/` fica de fora;
- `volumeIsBrowsable == true`, `volumeIsLocal == true` e
  `volumeIsReadOnly == false`. Isso exclui volumes de rede e volumes só de
  leitura. Discos externos USB/Thunderbolt e imagens de disco montadas para
  escrita entram.
- pasta varrida: `<volume>/.Trashes/<uid>`, em que `<uid>` é o id numérico do
  usuário atual (ex.: `501`). Só os filhos diretos (E6).

## Inclusão
Cada **filho direto** das pastas de lixo é um item (arquivo, pasta ou pacote).
Não há filtro de idade, tamanho ou extensão (E3, E6).

## Exclusão
- Pastas de lixo que não existem.
- Volumes de rede, só de leitura, não navegáveis, ocultos, ou fora de `/Volumes/` (E5).
- Lixos de outros usuários (`.Trashes/<outro uid>`) não são lidos.
- Não há lista de exclusões na v1.

## Recomendado
**Todos os itens vêm recomendados** (E3, E6). O critério é que o conteúdo do Lixo
já foi descartado pelo usuário.

## Agrupamento e nome exibido

```
Lixos (categoria)
├── Lixo do sistema (grupo `trash`, bloco A)      ícone: disco interno
│   └── <nome do item no Lixo>                     ícone: ícone do Finder do item
└── Lixos Montados (grupo `trash`, bloco B)       ícone: disco externo
    └── <nome do item no Lixo do volume>           ícone: ícone do Finder do item
```

- O CleanMyMac tem dois grupos de lixo de volume: o do volume de inicialização e o
  dos volumes montados. O grupo de volumes montados tem um título próprio, com o
  sentido de "lixos dos discos montados". O do volume de inicialização só tem
  descrição na localização, e o nome interno dele é "Root Volume Trash" (E7). O
  nosso título para ele é nosso, com o sentido de "Lixo" ou "Lixo do Mac".
- O nosso modelo tem um único `GroupID` `trash`. Para manter a separação visual sem
  criar outro `GroupID`, o grupo `trash` tem **dois itens-pai fixos**, "Lixo" e
  "Lixos Montados", e os itens do Lixo são filhos deles. Em "Lixos Montados", há
  um nível por volume, com o nome do volume (`volumeLocalizedName`) e os itens
  como filhos. Um pai sem filhos não aparece.
- O nome de cada item é o nome do arquivo no Lixo (`lastPathComponent`). O nome
  original antes de ir para o Lixo não é recuperado.
- Os itens que vêm dos lixos do iCloud (fontes A2 a A5) levam a marca
  `isCloudFile` (E8). A UI pode mostrar um selo pequeno de nuvem. A remoção é igual.
- Itens que são apps da App Store levam a marca `isApplicationFromAppStore` (E9).
  Ver "Remoção".

## Cálculo de tamanho
Tamanho alocado de cada filho direto, recursivo, como em `common.md` (E3).

## Remoção
- **Apagar definitivamente** cada item selecionado. A descrição do cartão de Lixos
  deixa claro que o conteúdo é apagado de vez (E10). O módulo não usa
  "mover para o Lixo" (E11).
- Arquivos travados (flag `uchg`) são destravados antes de apagar. O removedor do
  CleanMyMac tem uma rotina para "remover tratando o travamento" (E11).
- Se o usuário não tiver permissão (itens de root no Lixo, por exemplo), o item vai
  para a fila com privilégio, pela regra geral de `common.md`.
- Apps da App Store no Lixo: o CleanMyMac mostra, no registro, um erro próprio
  dizendo que esse tipo de app não pode ser removido por restrição da Apple, com um
  botão para mostrar o item no Finder (E9). Na v1, tentamos apagar normalmente. Se
  falhar, registramos o erro e oferecemos "Mostrar no Finder".
- Raízes permitidas: as pastas de lixo listadas em "Locais varridos". Só se apaga
  um **filho direto** delas, nunca a pasta de lixo em si.
- Não é preciso fechar nenhum app.

## Alertas e selos
- Nenhum alerta de confirmação próprio.
- O selo de nuvem nos itens `isCloudFile` é opcional.

## requiresAdmin
- Análise: **não**. Precisa de Acesso Total ao Disco para ler `~/.Trash` (E12).
- Limpeza: **não** em geral. Usa privilégio só para os itens que falharem por
  permissão (fallback de `common.md`).

## Evidências
- **E1**: pseudocódigo de `TrashScanTasksFactory.makeSystemTrashScanTask` e
  `makeMountedVolumesTrashScanTasks` (TrashJunkScanning): uma tarefa para o lixo do
  sistema e uma por volume montado.
- **E2**: pseudocódigo de `CMPaths::systemTrash` e `CMPaths::iCloudTrashes`
  (SharedObjcUtils): `~/.Trash` e os três lixos do iCloud.
- **E3**: pseudocódigo de `CMTrashesScanTask::scan` e `CMTrashesScanTask::_trashURLs`:
  só os filhos diretos (a listagem não pula ocultos), um modelo de arquivo por
  filho com tamanho e marcado como recomendado, e a raiz do bloco é `/`.
- **E4**: pseudocódigo de `CMTrashesScanTask::_mobileDocumentsTrashes` e
  `CMTrashesScanTask::init` (que liga a inclusão dos lixos do iCloud), mais a string
  `Documents/.Trash/`.
- **E5**: pseudocódigo de `CMMountedTrashesScanTasksFactory::tasks` e
  `isVolumeAtMountURLCleanable:`, mais a string `/Volumes/`.
- **E6**: pseudocódigo de `CMMountedTrashesScanTask::scan`: o caminho
  `.Trashes/<uid>`, os filhos diretos, e cada item marcado.
- **E7**: strings `Root Volume Trash`, `Mounted Trash Bins` e as chaves
  `trash_bins_root_volume_trash_group_description`, `trash_bins_mounted_trash_group_title`
  e os nomes de ícone `trash-bins_macintosh-hd` e `trash-bins_external-drive-trash`
  (JunkCleanupModule).
- **E8**: pseudocódigo do tratador de `CMTrashesScanTask::scan`: um item é de nuvem
  quando o URL dele começa com o URL de um dos lixos do iCloud.
- **E9**: símbolo `TrashFileModel.isApplicationFromAppStore` (TrashJunkScanning) e
  as chaves `cleanup_items_popover_unable_to_remove_app_store_application_*` (ModuleCore).
- **E10**: chave `tiles_trash_bins_normal_description` (JunkCleanupModule): o
  sentido é apagar de vez o conteúdo dos Lixos.
- **E11**: strings do CleaningCore: `FileRemover`, `PrivilegedFileRemover`,
  `removeFileAndHandleLockAtPath:error:`, `tryToUnlockFileIfNeededAtPath:recursively:`.
  Não há `MoveToTrashFileRemover` no JunkCleanupModule.
- **E12**: leitura do disco: sem Acesso Total ao Disco, `ls ~/.Trash` dá
  "Operation not permitted".

## Divergências conhecidas
- Dois itens-pai fixos ("Lixo" e "Lixos Montados") dentro do grupo `trash`, em vez
  de dois grupos separados, para caber no `GroupID` único.
- Não houve observação real. A paridade vem de fixtures e, se for seguro, de uma
  imagem de disco montada para escrita com um `.Trashes/<uid>`.
- O lixo do app Fotos ("Apagados Recentemente") **não** é varrido: ele fica dentro da
  biblioteca de fotos, e o CleanMyMac não procura lá.

## Baseline observada
Categoria vazia. O Gerenciador mostrou o estado "nada aqui" e nenhum grupo.
Leitura do disco (somente leitura):
- `~/.Trash` existe. O tamanho do diretório é 64 bytes no APFS, o que indica que ele
  está vazio. O conteúdo não pôde ser listado sem Acesso Total ao Disco;
- `~/Library/Mobile Documents/com~apple~CloudDocs/.Trash`,
  `~/Library/Mobile Documents/.Trash` e `~/Library/CloudStorage/iCloud Drive/.Trash`
  não existem. Nenhum `~/Library/Mobile Documents/*/Documents/.Trash` existe;
- `/Volumes` tem só `Macintosh HD` (o link para `/`), então não há volume montado.
O resultado vazio é coerente com a regra.

## Checklist de testes
1. `~/.Trash/a.txt` (10 bytes) e `~/.Trash/pasta/b.bin`: dois itens, `a.txt` e
   `pasta`, os dois recomendados. O tamanho de `pasta` inclui `b.bin`.
2. `~/.Trash/.DS_Store`: vira item.
3. `~/.Trash` inexistente: sem erro, bloco vazio.
4. `~/Library/Mobile Documents/com~apple~CloudDocs/.Trash/x.pages`: item com
   `isCloudFile = true`.
5. `~/Library/Mobile Documents/com~apple~Keynote/Documents/.Trash/k.key`: item de
   nuvem.
6. `~/Library/Mobile Documents/com~apple~Keynote/Documents/` sem `.Trash`: nada.
7. Volume falso em `/Volumes/USB` (local, navegável, gravável) com `.Trashes/501/f.mov`
   e uid 501: item `f.mov` sob "Lixos Montados › USB".
8. O mesmo volume com `.Trashes/502/g.mov`: `g.mov` não aparece.
9. Volume de rede ou só de leitura: ignorado (testar o filtro com valores de
   recurso injetados).
10. Volume `/` (inicialização): não entra em "Lixos Montados".
11. Remoção de `~/.Trash/pasta`: a pasta e o conteúdo somem, e `~/.Trash` continua
    existindo.
12. Remoção de um arquivo com `chflags uchg`: é destravado e apagado.
13. O `PathPolicy` recusa apagar `~/.Trash` em si e recusa `~/Documents/x`.
