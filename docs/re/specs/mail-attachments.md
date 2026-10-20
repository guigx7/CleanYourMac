# Anexos do Mail (`mailAttachments`)

Categoria **Anexos do Mail**. Um único grupo, que reúne as cópias locais de
anexos guardadas pelo app Mail da Apple e os arquivos que o Mail baixou para a
pasta de downloads dele.

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2, análise de 2026-10-20.
Neste Mac a categoria veio vazia (ver "Baseline observada").

## Locais varridos

A análise tem duas fontes (E1):

**A. Anexos dentro das contas do Mail**

1. A versão da biblioteca do Mail vem de `~/Library/Mail/PersistenceInfo.plist`,
   chave `LastUsedVersionDirectoryName` (ex.: `V10`). Sem esse arquivo ou essa
   chave, não há contas e a fonte A fica vazia (E2).
2. As contas vêm do banco `~/Library/Accounts/Accounts4.sqlite` (somente
   leitura). Entram só as contas cujo tipo é `com.apple.account.IMAP` ou
   `com.apple.account.IMAPMail` (E3). Para cada uma:
   - pasta da conta: `~/Library/Mail/<Vn>/<identificador da conta>`;
   - nome exibido: a descrição da conta (coluna de descrição da conta ou, se
     houver, a da conta-mãe);
   - ativa: a conta precisa estar habilitada para a classe de dados
     `com.apple.Dataclass.Mail`. Se o banco não diz nada, conta como ativa (E3, E4).
3. Uma conta só é varrida se (E5):
   - for IMAP (tipos acima);
   - estiver ativa;
   - **não** estiver offline. "Offline" significa: o arquivo
     `<pasta da conta>/.mboxCache.plist` existe e tem a chave `takenOffline`
     com um valor que, sem diferenciar maiúsculas/minúsculas, indica "sim".
     Se o arquivo não existe, a conta é tratada como online.
4. Dentro da pasta da conta, a varredura desce recursivamente, ignorando itens
   ocultos. Toda pasta cujo nome, em minúsculas, é `attachments` é aberta (E6).
   Dentro dela, cada **arquivo comum** ou **pacote** (ex.: `.pages`, `.key`,
   `.app`) é um anexo encontrado, e o pacote não é aberto. Pastas comuns são
   atravessadas. Depois de tratar uma pasta `Attachments`, a varredura não desce
   mais nela pela busca externa.
   Na prática isso pega `…/<conta>/<caixa>.mbox/<UUID>/Data/…/Attachments/<id da mensagem>/<parte>/<arquivo>`.

**B. Downloads do Mail**

As duas pastas abaixo, **só os filhos diretos** (E7):
- `~/Library/Mail Downloads/`
- `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/`

Os itens ocultos entram, exceto `.DS_Store`, que é pulado pelo nome.

## Inclusão

**Fonte A (contas).** Cada arquivo/pacote encontrado é uma **cópia**. As cópias
são agrupadas por uma chave formada pelo **nome do arquivo** e pelo **tamanho em
bytes** (`<nome>-<tamanho>`). Todas as cópias com a mesma chave na mesma conta
viram **um único anexo** com N cópias (E8). Uma conta sem nenhum anexo some do
resultado (E9).

**Fonte B (downloads).** Cada filho direto das duas pastas é um item (E7):
- se for **pasta** cujo nome casa com o padrão de UUID
  `^\w{8}(-\w{4}){3}-\w{12}$` (o Mail cria uma pasta-UUID por download), o
  item é representado pelo **último arquivo** listado dentro dela (só nível 1). Se
  a pasta estiver vazia, o item é a própria pasta;
- qualquer outro arquivo ou pasta é o próprio item.
O que se remove é sempre o **filho direto** (a pasta-UUID inteira ou o arquivo
solto), e o tamanho é o desse filho direto.

As duas pastas de downloads formam juntas um único bloco, "Downloads do Mail".

## Exclusão

- Contas POP, Exchange e outros tipos que não sejam os dois IMAP acima (E3).
- Contas inativas ou offline (E5).
- `.DS_Store` na fonte B (E7).
- Lista de exclusões do usuário: o CleanMyMac consulta uma lista de itens ignorados
  por conta, por anexo (chave `<nome>-<tamanho>`) e por caminho (E10). A v1 não tem
  lista de exclusões (não-objetivo do design), então não há exclusão equivalente.

## Recomendado

Esta é a regra de "arquivos modificados pelo usuário são mantidos" (E7, E8):

- **Anexos das contas (fonte A): sempre recomendados.** Toda cópia vem
  recomendada. O Mail pode baixar de novo do servidor IMAP.
- **Downloads do Mail (fonte B): recomendado só se o arquivo não foi modificado
  depois de criado.** Para o arquivo que representa o item (o arquivo dentro da
  pasta-UUID ou o próprio filho), compare a data de criação
  (`creationDate`) com a data de modificação do conteúdo
  (`contentModificationDate`), as duas em segundos desde 1970, como `Double`:
  - **iguais** → recomendado (o usuário só abriu o arquivo, não o editou);
  - **diferentes** → **não** recomendado (o usuário editou e salvou; manter).
  - Se nenhuma das duas datas puder ser lida, as duas valem 0, então ficam iguais e
    o item vem recomendado. Se só uma puder ser lida, ficam diferentes e o item
    não vem recomendado.
  A comparação é exata (sem tolerância).

O estado de um nível de cima (anexo com várias cópias, conta, bloco de
downloads) é a soma dos filhos: marcado se todos os filhos estão marcados, misto
se só parte deles. Ver `results-screen.md` para quando a seleção recomendada é
aplicada.

## Agrupamento e nome exibido

```
Anexos do Mail (categoria)
└── Mail (grupo `mailAttachments`)           ícone: envelope
    ├── <descrição da conta IMAP>            ícone: conta de e-mail genérica
    │   └── <nome do anexo>                  ícone: ícone do arquivo (NSWorkspace)
    │       └── <cópia 1>, <cópia 2>…        (só quando há mais de uma cópia)
    └── Downloads do Mail                    ícone: conta de e-mail genérica
        └── <nome do arquivo baixado>        ícone: ícone do arquivo
```

- Cada **conta** é um item (E11). O nome é a descrição da conta. O bloco de
  downloads usa uma "conta desconhecida" sem nome. A UI mostra para ele um título
  nosso equivalente a "Downloads do Mail" (E12).
- O nome do **anexo** é o nome do arquivo (último componente do caminho) da
  primeira cópia encontrada. Na fonte B, é o nome do arquivo representante (o
  arquivo dentro da pasta-UUID). O ícone é o ícone do Finder para esse arquivo.
- O tamanho do anexo é a soma das cópias. O tamanho da conta é a soma dos anexos.
- No nosso modelo (`JunkItem`), a conta e o bloco de downloads têm `removal = nil`.
  Um anexo com uma só cópia tem `removal = .delete(cópia)`. Um anexo com várias
  cópias tem `removal = nil`, e cada cópia é um filho com `.delete(cópia)`. Um
  item de download tem `.delete(<filho direto de Mail Downloads>)`.
- O `id` estável é `mailAttachments:<id da conta>:<nome>-<tamanho>` para os anexos
  e `mailAttachments:downloads:<caminho do filho direto>` para os downloads.
- O CleanMyMac mostra no fim da coluna de grupos uma linha de propaganda do módulo
  dele de limpeza de e-mail (E13). Isso fica **fora da v1**.

## Cálculo de tamanho
Tamanho alocado, como definido em `common.md`. A fonte A mede cada arquivo/pacote.
A fonte B mede o filho direto inteiro (E7, E8).

## Remoção
- **Apagar definitivamente** (sem mover para o Lixo). O módulo de Limpeza do
  CleanMyMac não usa o removedor "mover para o Lixo" (E14).
- Fonte A: apagar **cada cópia** do anexo (os arquivos/pacotes dentro de
  `Attachments`). As pastas `Attachments/<id>/<parte>` que ficarem vazias não
  precisam ser apagadas.
- Fonte B: apagar o **filho direto** de `Mail Downloads` (a pasta-UUID inteira ou o
  arquivo).
- Raízes permitidas para o `PathPolicy`: `~/Library/Mail/<Vn>/` (só caminhos que
  tenham um componente `Attachments`, sem diferenciar maiúsculas/minúsculas),
  `~/Library/Mail Downloads/` e
  `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/`.
- App aberto: não achamos nada que encerre o Mail ou avise que ele está aberto antes
  da limpeza. Se a remoção falhar, a tela de falha sugere fechar os apps
  relacionados (ver `results-screen.md`).

## Alertas e selos
Nenhum alerta específico deste grupo.

## requiresAdmin
- Análise: **não**. Precisa de Acesso Total ao Disco, porque `~/Library/Mail`, o
  container do Mail e `Accounts4.sqlite` são protegidos pelo TCC (E15).
- Limpeza: **não**. Os arquivos são do usuário. Se algum der erro de permissão,
  vale a regra geral de `common.md` (fila com privilégio).

## Evidências
- **E1**: pseudocódigo de `CMMailTask::scan` (MailJunkScanning): o resultado
  junta os blocos das contas e o bloco de downloads, e no fim descarta os blocos
  vazios.
- **E2**: pseudocódigo de `CMMailAccountsInfoProvider::lastUsedVersionDirectoryName`
  e `CMMailInfo::mailLibraryURL` (MailboxService): a versão vem de
  `PersistenceInfo.plist`; sem ela, o caminho da biblioteca não se forma.
- **E3**: pseudocódigo de `CMMailAccountsInfoProvider::fetchAccountsWithError:`
  e `CMMailInfo::_importMailboxesFromArray:` (MailboxService), e as strings
  `Library/Accounts/Accounts4.sqlite`, `com.apple.account.IMAP` e
  `com.apple.account.IMAPMail`: só contas IMAP entram. A pasta da conta é a versão
  mais o identificador.
- **E4**: pseudocódigo de `CMMailBox::initWithInfoDictionary:`: `IsActive`
  ausente vale "ativa", e o nome vem de `AccountName`.
- **E5**: pseudocódigo de `CMMailBox::availableForClean`, `CMMailBox::isOffline`
  e `_takenOfflineWithDictionary:`, mais as strings `.mboxCache.plist` e
  `takenOffline`.
- **E6**: pseudocódigo de `CMMailBox::enumerateAttachmentsWithHandler:canContinueHandler:`:
  a busca recursiva sem ocultos, a pasta `attachments` (sem diferenciar
  maiúsculas/minúsculas), arquivos e pacotes reportados, pacotes não abertos.
- **E7**: pseudocódigo de `CMMailTask::downloads`, `CMMailTask::contentsOfDirectory:progress:`
  e `CMMailTask::downloadsMailboxModel`, mais as strings dos dois caminhos
  `Mail Downloads`, `.DS_Store` e a expressão de UUID: só os filhos diretos, a
  pasta-UUID representada pelo último arquivo dela, e o recomendado igual a
  "criação igual a modificação".
- **E8**: pseudocódigo do tratador de anexos de `CMMailTask` (o bloco chamado por
  anexo) e a string de formato `%@-%lli`: as cópias são agrupadas por nome e
  tamanho, e cada cópia vem marcada.
- **E9**: pseudocódigo do filtro de `CMMailTask::scan`: só ficam os blocos com
  tamanho maior que zero.
- **E10**: pseudocódigo de `MailJunkKnowledgeBase::isMailboxIgnored:`,
  `isAttachmentIgnored:` e `isPathIgnored:` (JunkCleanupModule): é uma consulta à
  lista de ignorados.
- **E11**: pseudocódigo do mapeador `MailAppJunkModelMapper` (MailJunkScanning) e
  o tipo de nó `JunkCleanupItemNode<MailAppJunkModel, JunkCleanupItemNode<AttachmentModel, Node>>`
  (strings do JunkCleanupModule): conta → anexos. O nome da conta é nulo para a
  conta desconhecida.
- **E12**: chaves de localização `mail_attachments_mail_group_title` e
  `mail_attachments_mail_downloads_title` (JunkCleanupModule).
- **E13**: as strings `EmailCleanupPromoRow…` e "docked into the Mail Attachments
  groups column" (JunkCleanupModule).
- **E14**: as strings do JunkCleanupModule não mencionam `MoveToTrashFileRemover`.
  O CleaningCore tem `FileRemover` e `PrivilegedFileRemover`.
- **E15**: leitura do disco: neste shell, sem Acesso Total ao Disco, `ls` em
  `~/Library/Mail` e no container do Mail dá "Operation not permitted".

## Divergências conhecidas
- Não há lista de exclusões na v1.
- Não há a linha de propaganda da limpeza de e-mail.
- O CleanMyMac lê `Accounts4.sqlite` procurando as colunas pelo sufixo do nome
  (o esquema Core Data muda entre versões do macOS). O nosso app deve fazer o
  mesmo: achar as tabelas e colunas por sufixo (`ACCOUNTTYPE`, `IDENTIFIER`,
  `ACCOUNTDESCRIPTION`, `PARENTACCOUNT`, `DATACLASSPROPERTIES`, `ENABLEDDATACLASSES`)
  e não fixar `Z…` literais. Se o banco não puder ser aberto, a fonte A fica vazia
  e a fonte B continua.
- Os anexos da caixa de Lixo de uma conta IMAP aparecem aqui e também em "Lixos do
  Mail" (`mail-trash.md`), que tem caminhos sobrepostos. O CleanMyMac não remove essa
  duplicação, e nós também não. O motor de limpeza deve ignorar sem erro um
  caminho que já tenha sido apagado na mesma limpeza.
- Não houve observação real: os dados de paridade vêm de fixtures.

## Baseline observada
Categoria vazia. O Gerenciador mostrou o estado "nada aqui" e nenhum grupo.
Leitura do disco (somente leitura) para explicar o resultado:
- `~/Library/Mail` existe, mas tem só 2 entradas, pelo tamanho do diretório
  (128 bytes no APFS);
- `~/Library/Mail Downloads` não existe;
- o domínio de preferências do Mail no container
  (`~/Library/Containers/com.apple.mail/Data/Library/Preferences/com.apple.mail`)
  não existe, o que indica que o Mail nunca foi configurado.
Sem conta IMAP e sem downloads, o resultado é vazio. Isso é coerente com a regra.

## Checklist de testes
Fixtures com `home` falso. O `Accounts4.sqlite` falso tem o esquema mínimo, com
colunas que terminam nos sufixos citados acima.

1. Sem `~/Library/Mail/PersistenceInfo.plist`: a fonte A fica vazia. Com
   `Mail Downloads/a.pdf`, o resultado é só "Downloads do Mail" com `a.pdf`.
2. Conta IMAP ativa em `V10/<ID>` com `INBOX.mbox/<UUID>/Data/1/Attachments/123/2/foto.jpg`
   de 1000 bytes: um anexo "foto.jpg", recomendado, 1 cópia.
3. Dois arquivos `foto.jpg` de 1000 bytes em mensagens diferentes da mesma conta:
   um anexo com 2 cópias, e o tamanho é a soma das duas.
4. `foto.jpg` de 1000 bytes e `foto.jpg` de 2000 bytes: dois anexos separados.
5. Pasta `ATTACHMENTS` em maiúsculas: entra.
6. Pacote `doc.pages/` dentro de `Attachments/…`: entra como uma cópia e não é
   aberto (os arquivos de dentro não viram cópias).
7. Arquivo oculto `.x` dentro de `Attachments`: não entra (a busca pula ocultos).
8. Conta do tipo POP: ignorada.
9. Conta IMAP com `IsActive` falso: ignorada.
10. Conta IMAP com `.mboxCache.plist` e `takenOffline` igual a `YES`: ignorada.
11. Conta sem nenhum anexo: não aparece.
12. `Mail Downloads/<UUID>/relatorio.pdf` com criação igual a modificação: um item
    "relatorio.pdf", recomendado, que remove a pasta `<UUID>`.
13. O mesmo caso com modificação 1 s depois da criação: item **não** recomendado.
14. `Mail Downloads/<UUID>/` vazia: o item é a pasta, com o nome da pasta-UUID.
15. `Mail Downloads/solto.zip` (sem pasta-UUID): o item é o próprio arquivo.
16. `Mail Downloads/.DS_Store`: ignorado. `Mail Downloads/.oculto`: entra.
17. `Mail Downloads/sub/neto.txt`: só `sub` vira item, não `neto.txt`.
18. Arquivos nas duas pastas `Mail Downloads` (a normal e a do container): todos no
    mesmo bloco "Downloads do Mail".
19. Remoção de um anexo com 2 cópias: os 2 arquivos são apagados, e
    `Attachments/123/2/` pode ficar.
20. O `PathPolicy` recusa apagar `~/Library/Mail/V10/<ID>/INBOX.mbox/…/Messages/1.emlx`
    neste grupo (não está sob `Attachments`).
