# Lixos do Mail (`mailTrash`)

Categoria **Lixos**. São as cópias locais das mensagens que estão na caixa de
Lixo das contas IMAP do app Mail. As mensagens continuam no servidor e o Mail
as baixa de novo se precisar. As cópias locais ficam ocupando espaço no disco.

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2, análise de 2026-10-20.
Neste Mac a categoria Lixos veio vazia.

## Locais varridos
1. As contas vêm do mesmo leitor de contas de `mail-attachments.md`:
   `~/Library/Accounts/Accounts4.sqlite`, a versão de
   `~/Library/Mail/PersistenceInfo.plist` e a pasta da conta
   `~/Library/Mail/<Vn>/<identificador>` (E1).
2. Uma conta entra se (E2):
   - for IMAP (`com.apple.account.IMAP` ou `com.apple.account.IMAPMail`);
   - estiver ativa;
   - tiver uma caixa de Lixo definida.
   Ao contrário dos anexos, aqui **não** se verifica se a conta está offline.
3. **Caixa de Lixo.** As propriedades da classe de dados Mail da conta têm a chave
   `TrashMailboxName` (ex.: `Deleted Messages`, `Trash`, `[Gmail]/Lixeira`). O
   valor é quebrado em `/`, e cada parte vira `<parte>.mbox`. O caminho é
   `<pasta da conta>/<parte1>.mbox/<parte2>.mbox/` (E3). Exemplo: `[Gmail]/Lixeira`
   vira `<conta>/[Gmail].mbox/Lixeira.mbox/`. Sem essa chave (ou com ela vazia), a
   conta não tem Lixo e fica de fora.
4. **Mensagens.** Dentro da caixa de Lixo, a busca é recursiva e ignora ocultos.
   Em toda pasta cujo nome, em minúsculas, é `data`, a busca desce de novo
   (recursiva, sem ocultos) e coleta cada **arquivo comum** e cada **pacote** (sem
   abrir o pacote). As pastas comuns não são coletadas (E4). Dessa coleta ficam só
   os arquivos com extensão `emlx` ou `emlxpart` (E5).
   Na prática: `…/Lixeira.mbox/<UUID>/Data/<d>/<d>/Messages/<n>.emlx` e
   `…/Messages/<n>.<parte>.emlxpart`.

## Inclusão
Cada arquivo `.emlx` ou `.emlxpart` é um item, isto é, uma mensagem (E5, E6).
**Filhos do item:** os anexos da mensagem. O CleanMyMac os acha assim (E6):
- toma o nome do arquivo sem a extensão (`123.emlx` → `123`;
  `123.2.emlxpart` → `123.2`);
- sobe dois níveis a partir do arquivo (de `…/<d>/Messages/123.emlx` para `…/<d>/`)
  e monta `…/<d>/Attachments/123`;
- se essa pasta existir, entram como filhos as entradas de **nível 2** dentro dela
  (`Attachments/123/<parte>/<arquivo>`), cada uma com o próprio tamanho.

## Exclusão
- Contas que não sejam IMAP, contas inativas e contas sem caixa de Lixo (E2, E3).
- Arquivos que não sejam `.emlx` nem `.emlxpart` (por exemplo, os `.plist` de
  caixa) (E5).
- Não há lista de exclusões na v1.

## Recomendado
**Todas as mensagens e todos os anexos vêm recomendados** (E6).

## Agrupamento e nome exibido

```
Lixos (categoria)
└── Lixos do Mail (grupo `mailTrash`)            ícone: lixo do Mail
    └── <descrição da conta>                      ícone: conta de e-mail genérica
        └── <remetente>: <assunto>                ícone: mensagem (envelope)
            └── <arquivo anexo>                   ícone: ícone do Finder do arquivo
```

- O CleanMyMac monta **um bloco por conta**. O nó de grupo é parametrizado pela
  conta e tem o nome da conta (E7). O nosso modelo tem um só `GroupID` `mailTrash`,
  então cada conta vira um **item-pai** com `removal = nil`, e as mensagens são
  filhos dele.
- **Nome da mensagem** (E8): o nome do arquivo sem a extensão é lido como número
  inteiro decimal, que é o id da mensagem no `Envelope Index` do Mail
  (`~/Library/Mail/<Vn>/MailData/Envelope Index`, SQLite, somente leitura). Se o
  número for válido e o banco tiver o **assunto** e o **remetente** dessa
  mensagem, os dois não vazios, o nome é `<remetente>: <assunto>`. Nos outros
  casos (id inválido, sem banco, assunto ou remetente vazio), o nome é o nome do
  arquivo.
  - O assunto vem da tabela de assuntos, ligada à mensagem pelo `rowid`. O CleanMyMac
    faz uma junção entre as tabelas de mensagens e de assuntos (E8).
- O tamanho da mensagem é o tamanho do `.emlx` mais o dos anexos (filhos).

## Cálculo de tamanho
Tamanho alocado (`common.md`) de cada `.emlx` e de cada entrada de anexo (E6).

## Remoção
- **Apagar definitivamente** o arquivo da mensagem **e** os anexos dela (os filhos
  de nível 2). O CleanMyMac marca o modelo da mensagem para remover a si mesmo,
  além dos filhos (E6).
- As pastas `Attachments/<n>` e `Attachments/<n>/<parte>` que ficarem vazias podem
  continuar. O CleanMyMac não as apaga.
- O `Envelope Index` **não** é alterado. Não se roda nenhum `VACUUM` nem
  `UPDATE`: as rotinas de banco do Mail que existem no CleanMyMac pertencem ao
  módulo Desempenho, não à Limpeza (E9).
- Raízes permitidas: a caixa de Lixo de cada conta
  (`~/Library/Mail/<Vn>/<conta>/<…>.mbox/`). Só se apaga `.emlx` ou `.emlxpart` e
  entradas de `Attachments/<n>/…` dentro dela.
- App aberto: não há regra específica. Se uma remoção falhar, vale o texto geral
  de falha (fechar os apps relacionados).

## Alertas e selos
Nenhum.

## requiresAdmin
- Análise: **não** (precisa de Acesso Total ao Disco).
- Limpeza: **não**.

## Evidências
- **E1**: pseudocódigo de `CMMailTrashScanTasksFactory::init` e `::tasks`
  (TrashJunkScanning): usa o `CMMailInfo` compartilhado (MailboxService), o mesmo dos
  anexos.
- **E2**: pseudocódigo do filtro de `CMMailTrashScanTasksFactory::tasks` e de
  `CMMailTrashScanTask::scan`: o tipo IMAP, a caixa de Lixo definida e a conta ativa.
- **E3**: pseudocódigo de `CMMailBox::initWithInfoDictionary:` e as strings
  `TrashMailboxName` e `%@.mbox/` (MailboxService).
- **E4**: pseudocódigo de `CMMailBox::trashes` (MailboxService): as pastas `data`,
  os arquivos e pacotes, e nada de ocultos.
- **E5**: pseudocódigo do filtro usado em `CMMailTrashScanTask::scan` e as strings
  `emlx` e `emlxpart` (TrashJunkScanning).
- **E6**: pseudocódigo de `CMMailTrashScanTask::_entityForURL:size:`: o caminho
  `Attachments/<nome>`, os filhos de nível 2, tudo marcado e "remover a si mesmo".
- **E7**: o tipo de nó `JunkCleanupGroupNode<MailTrashModel, JunkCleanupItemNode<MailTrashAttachmentModel, Node>>`
  e os símbolos `MailTrashModel.name` e `.attachments` (strings e símbolos do
  JunkCleanupModule e do TrashJunkScanning).
- **E8**: pseudocódigo do formatador de nome do JunkCleanupModule que chama
  `mailSubjectWithID:` e `mailFromWithID:` e junta os dois com `": "`, mais as
  strings `Envelope Index` e a consulta de assunto por `rowid` (MailboxService).
- **E9**: as strings `VACUUM;`, `vacuum` e `vacuumWithError:` aparecem só no
  MailboxService e no PerformanceService, não no JunkCleanupModule.

## Divergências conhecidas
- Cada conta vira um item-pai dentro de um único grupo `mailTrash`, e não um grupo
  próprio.
- As mensagens do Lixo também têm anexos que podem aparecer em "Anexos do Mail"
  (`mail-attachments.md`), com caminhos sobrepostos. O motor de limpeza deve
  ignorar sem erro um caminho que já tenha sido apagado na mesma limpeza.
- O banco de contas é lido pelas colunas encontradas por sufixo (ver
  `mail-attachments.md`).
- Não houve observação real.

## Baseline observada
Categoria Lixos vazia. O Mail não está configurado neste Mac (ver a baseline de
`mail-attachments.md`), então não há contas IMAP e o grupo fica vazio.

## Checklist de testes
Fixture: `Accounts4.sqlite` falso com uma conta IMAP ativa, de identificador `ACC1`,
descrição "Trabalho" e `TrashMailboxName = "Deleted Messages"`;
`~/Library/Mail/PersistenceInfo.plist` com `LastUsedVersionDirectoryName = V10`.

1. `V10/ACC1/Deleted Messages.mbox/U1/Data/1/2/Messages/55.emlx` (2000 bytes):
   um item sob "Trabalho", recomendado.
2. O mesmo caso, com `…/Data/1/2/Attachments/55/2/foto.jpg`: o item tem o filho
   `foto.jpg`, e o tamanho total é a soma.
3. `…/Messages/55.2.emlxpart`: entra e procura anexos em `Attachments/55.2`.
4. `…/Messages/x.plist`: não entra.
5. `TrashMailboxName = "[Gmail]/Lixeira"`: a caixa varrida é
   `ACC1/[Gmail].mbox/Lixeira.mbox/`.
6. Conta sem `TrashMailboxName`: não há item.
7. Conta POP: ignorada.
8. Conta IMAP inativa: ignorada.
9. Conta IMAP com `takenOffline` igual a `YES`: **entra** (esta regra não olha
   offline).
10. `Envelope Index` falso, com a mensagem 55 de remetente "Ana" e assunto "Oi":
    o nome é "Ana: Oi". Sem o banco: o nome é "55.emlx".
11. Arquivo `abc.emlx` (nome não numérico): o nome é o nome do arquivo.
12. A remoção apaga `55.emlx` e `Attachments/55/2/foto.jpg`, e não mexe em
    `Envelope Index`.
13. Pasta `data` em minúsculas e `Data` com inicial maiúscula: as duas são varridas.
