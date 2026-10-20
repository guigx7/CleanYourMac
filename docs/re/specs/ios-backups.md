# Backups de Dispositivos iOS (`iosBackups`)

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26 (Darwin 25.6.0), análise de 20/10/2026.
Neste Mac o grupo apareceu com **0 KB**, e a pasta de backups nem existe (ver
"Divergências conhecidas").

## Locais varridos
- Raiz única: `~/Library/Application Support/MobileSync/Backup/` (E1).
- Enumeração **rasa** dos filhos diretos da raiz, sem descer em subpastas e sem
  incluir itens ocultos (opções "pular descendentes", "pular conteúdo de pacotes"
  e "pular ocultos") (E2). Cada filho é candidato a backup. O nome do filho é,
  em geral, o UDID do aparelho.
- A raiz ausente gera um resultado vazio, sem erro.

## Inclusão
Para cada filho da raiz que não for ignorado pela base (consulta pelo nome do
filho) (E3):
1. Lê-se `<backup>/Info.plist` como dicionário e pegam-se as chaves
   `Device Name` e `Product Type` (strings) (E4).
2. **Com `Device Name`** → backup válido de um aparelho. O aparelho é
   identificado por `"<Device Name>, <Product Type>"`, ou só por `<Device Name>`
   quando o `Product Type` estiver vazio. Esse identificador é a chave de
   agrupamento e de igualdade entre aparelhos (E5).
3. **Sem `Device Name`**, ou com o `Info.plist` ausente ou ilegível → **backup
   quebrado** (E4).
4. Data de cada backup válido: `Date` (NSDate) de `<backup>/Status.plist`. Se
   ela faltar, usa-se `Last Backup Date` (NSDate) do `Info.plist`. Se as duas
   faltarem, a data fica nula (E6).

Cada backup é um item-folha cujo alvo é a pasta inteira do backup.

## Exclusão
- Filhos cujo nome a base cifrada manda ignorar (E3).
- Aparelhos cujo identificador a base ignora, por duas consultas: "ignorar
  item" e "ignorar device id" (E4, E7).
- Backups quebrados quando a base ignora o item `Broken Backups` ou quando a
  regra "ignorar backups quebrados" (categoria `Broken Backups`) estiver ativa
  (E4, E7).
- Nossa regra equivalente: as listas de ignorados começam vazias, e
  `ignorarBackupsQuebrados = false` (os quebrados aparecem).

## Recomendado
- Por aparelho, os backups são ordenados por data **decrescente**. O primeiro
  (o mais recente) recebe o selo `latest` e **não** é recomendado. Todos os
  outros do mesmo aparelho são recomendados (E8).
- Backups com data nula ficam no fim da ordenação (eles nunca são o "mais
  recente" se houver outro com data). Se o aparelho só tiver backups sem data,
  o primeiro da lista fica como o mais recente.
- Backups quebrados: todos recomendados e nenhum com selo (E9).

## Agrupamento e nome exibido
Dois níveis (E10):
1. **Grupo por aparelho**: um nó por identificador de aparelho. O título é o
   `Device Name`. O modelo legível vem do `Product Type` por uma tabela de nomes
   comerciais (ex.: `iPhone14,2` → "iPhone 13 Pro") (E11). Ícone: um aparelho
   genérico (iPhone/iPad conforme o prefixo do `Product Type`).
2. **Backups quebrados**: um único grupo **sem aparelho**, com os quebrados,
   adicionado depois dos grupos de aparelhos (E9). Na nossa UI o título será
   "Backups danificados" (texto próprio).
3. **Itens (backups)**: o nome é a data do backup formatada (data em estilo médio
   + hora curta, na localidade do usuário; ver Divergências), e o selo "Mais recente" fica no primeiro (E12). Sem
   data, mostramos o nome da pasta (UDID). O ícone é o da pasta/aparelho.

A ordem dos grupos de aparelhos não é garantida no CleanMyMac (vem de um
dicionário). Nós ordenamos por tamanho, como no resto da UI.

## Cálculo de tamanho
Tamanho recursivo da pasta do backup, com o mesmo medidor dos outros grupos
(alocado, sem seguir symlinks) (E13). O tamanho do grupo é a soma dos backups.

## Remoção
- A pasta inteira do backup é apagada **definitivamente**, pelo removedor de
  arquivos comum do módulo. O JunkCleanupModule não usa o removedor que manda
  para o Lixo (E14).
- Não há verificação do Finder/Music aberto. Não é preciso fechar nada.
- A pasta `MobileSync/Backup` é protegida por TCC: tanto a leitura quanto a
  remoção exigem Acesso Total ao Disco, mas não admin.

## Alertas e selos
- Selo **"Mais recente"** no backup mais recente de cada aparelho (E12).
- **Confirmação de seleção**: ao marcar (ou deixar marcado para limpar) um
  backup com `latest = true`, ou um grupo que contenha um, aparece um alerta com
  título, mensagem e dois botões: cancelar ou "remover mesmo assim". O sentido é
  que a seleção inclui o backup mais recente de um ou mais aparelhos, e que sem
  ele não dá para restaurar o aparelho ao estado atual (E15). O texto da nossa
  UI é próprio. Nenhuma outra confirmação.
- Cartão de destaque na tela de Resultados quando o grupo tiver tamanho > 0
  (chaves de cartão de backups do iOS) (E16). A ordem e as regras ficam em
  `results-screen.md`.

## requiresAdmin
- Análise: não (precisa de Acesso Total ao Disco).
- Limpeza: não (idem).

## Evidências
- **E1** — pseudocódigo de `CMMobileBackupsTask initWithKnowledgeBase:` (raiz =
  `mobileBackupsURL` de `CMPaths`) e strings do SharedObjcUtils
  (`~/Library/Application Support/MobileSync/Backup/`).
- **E2** — pseudocódigo de `CMMobileBackupsTask backupURLs`: listagem rasa com
  as opções 7 (pular subdiretórios, pacotes e ocultos).
- **E3** — pseudocódigo do bloco de filtro em `scan`: a base é consultada pelo
  último componente da URL.
- **E4** — pseudocódigo de `CMMobileBackupsTask scan`: leitura de `Info.plist`,
  chaves `DeviceName`/`ProductType` (strings `Device Name`, `Product Type`);
  ramo sem nome com as consultas `Broken Backups` e `shouldIgnoreBrokenBackups`.
- **E5** — pseudocódigo de `CMMobileBackupDevice uniqueID` / `deviceFullName` /
  `isEqual:` e a string de formato `%@, %@`.
- **E6** — pseudocódigo do bloco que cria `CMMobileBackupWithDate`: `Status.plist`
  → `Date`, com recurso a `Last Backup Date` do `Info.plist`.
- **E7** — pseudocódigo de `MobileBackupsKnowledgeBase shouldIgnoreBrokenBackups`
  / `shouldIgnoreDeviceID:` / `isIgnoreItem:` (JunkCleanupModule): consultas
  por categoria à base cifrada, uma delas literalmente `Broken Backups`.
- **E8** — pseudocódigo do bloco por aparelho em `scan`: ordenação por `date`
  decrescente; o índice 0 recebe latest = sim e autoselected = não, e os demais
  latest = não e autoselected = sim.
- **E9** — pseudocódigo do bloco de quebrados em `scan`: `CMMobileBackup` com
  autoselected = sim e latest = não, num `CMMobileBackupGroup` sem aparelho.
- **E10** — símbolos `MobileBackupsGroupModel` (device, backups) /
  `MobileBackupsModel` (url, size, isAutoselected, latest, date) /
  `MobileDeviceModel` (productType), e strings
  `JunkCleanupItemNode<MobileBackupsGroupModel, JunkCleanupItemNode<MobileBackupsModel, Node>>`.
- **E11** — símbolo `CMMobileDeviceInfo humanReadableDeviceNameWithProductType:`
  usado pelo JunkCleanupModule (a tabela fica em outro framework e não foi lida).
- **E12** — chave `system_junk_ios_backup_latest_badge_label` e string
  `latest-ios-backup`. Símbolo `mobileBackupDateFormatter` (formatador de data
  dos itens).
- **E13** — pseudocódigo dos blocos de `scan`: `byteSizeAtURL` sobre a pasta do backup.
- **E14** — símbolos: `MoveToTrashFileRemover` existe só no CleaningCore e não
  aparece no JunkCleanupModule, que usa `FileRemover`/`PrivilegedFileRemover`.
- **E15** — pseudocódigo de `MobileBackupsModel.selectionConfirmation` (só
  quando `latest`) e de `MobileBackupsGroupModel.selectionConfirmation`. Chaves
  `system_junk_ios_backup_latest_alert_{title,message,confirm_button,cancel_button}`.
- **E16** — chaves `tiles_iOS_backups_normal_title`/`_description`/`completed_*`.
- **E17** — baseline `Detritos do Sistema/Backups de Dispositivos iOS.txt`: 0 KB,
  estado vazio. Leitura do disco: `~/Library/Application Support/MobileSync/`
  não existe neste Mac.

## Baseline observada
- Grupo "Backups de Dispositivos iOS": **0 KB**, sem itens. A pasta MobileSync
  não existe nesta máquina.

## Divergências conhecidas
- **Sem observação real.** O nome dos grupos, o formato da data, a posição do
  grupo de quebrados e o ícone saíram do código e de símbolos, sem UI para
  comparar. Para conferir a paridade, crie um backup falso em uma pasta de
  teste, ou faça um backup real de um iPhone pelo Finder, e compare.
- **Nome legível do modelo:** a tabela `Product Type` → nome comercial do
  CleanMyMac fica em outro framework e não foi lida. Usaremos uma tabela pública
  própria. Para um tipo desconhecido, mostramos o `Product Type` cru.
- **Formato da data do item:** o estilo exato (só data ou data e hora) não foi
  confirmado. Adotamos data média + hora curta, o que ajuda a distinguir dois
  backups do mesmo dia.
- **Base cifrada:** as regras de ignorar (por UDID, por aparelho e por
  quebrados) não são conhecidas. Começamos sem nenhuma.
- **Filho que não é pasta:** o CleanMyMac não verifica se o filho é diretório,
  então um arquivo solto na raiz viraria um "backup quebrado". Nós seguimos o
  mesmo comportamento, mas ignoramos `.DS_Store` (que de todo modo é oculto e já
  fica de fora).
- **Ordem dos grupos:** no CleanMyMac ela não é determinística. A nossa é por
  tamanho decrescente.

## Checklist de testes
1. Raiz inexistente → grupo vazio (0 KB) e sem erro.
2. `Backup/UDID1/` com `Info.plist` {Device Name: "iPhone do Gui", Product Type:
   "iPhone14,2"} e `Status.plist` {Date: 2026‑10‑01} → grupo "iPhone do Gui" com 1
   item marcado como "Mais recente" e **não** recomendado.
3. Dois backups do mesmo aparelho (mesmo nome e tipo), datas 2026‑10‑01 e
   2026‑09‑01 → o de 10/01 é o mais recente e fica desmarcado. O de 09/01 fica
   recomendado.
4. Mesmo `Device Name` com `Product Type` diferente → dois grupos distintos.
5. `Status.plist` sem `Date`, com `Info.plist` contendo `Last Backup Date` → usa
   a data do `Info.plist`.
6. Backup sem nenhuma data junto de outro com data → o que tem data é o mais recente.
7. Pasta sem `Info.plist` → grupo de quebrados, recomendado e sem selo.
8. `Info.plist` sem `Device Name` → quebrado.
9. `ignorarBackupsQuebrados = true` → os quebrados não aparecem.
10. Pasta oculta `.foo` na raiz → ignorada. Subpastas internas de um backup
    não viram itens.
11. Marcar o backup "Mais recente" → aparece o alerta de confirmação. Cancelar
    reverte a marcação, e confirmar mantém.
12. Limpar → a pasta do backup é apagada definitivamente (não vai para o Lixo).
13. Tamanho do item = tamanho alocado recursivo da pasta. Tamanho do grupo =
    soma dos itens.
