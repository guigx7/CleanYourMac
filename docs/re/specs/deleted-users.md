# Usuários Apagados (`deletedUsers`)

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2. Análise de 2026-10-20 (baseline
`baseline-20261020-1457`).

## Locais varridos
- Uma única raiz, absoluta: **`/Users/Deleted Users`** [E1][E2].
  É a pasta onde o macOS guarda a imagem de disco da pasta pessoal quando uma conta
  é apagada com a opção "salvar a pasta pessoal numa imagem de disco".
- Se a raiz não existir, o resultado é vazio [E2].
- Listagem **não recursiva**, sem arquivos ocultos [E2].

## Inclusão
- Cada **filho direto** cuja extensão é **`dmg`** (comparação exata, minúscula)
  vira **um item** (o próprio arquivo) [E2].
- O tamanho é medido no item. Não há idade mínima.

## Exclusão
- Tudo o que não é `*.dmg`: pastas, outros arquivos e ocultos [E2].
- Itens marcados pela base de regras deste grupo (`DeletedUsersKnowledgeBase`
  → `shouldIgnoreURL` / `isIgnoreItem`) [E3]. A base é cifrada (ver Divergências).
- **O app não compara com as contas existentes.** Ele não procura pastas em
  `/Users` sem conta correspondente e não consulta o Directory Services. O único
  critério é estar em `/Users/Deleted Users` e ter a extensão `.dmg` [E2].

## Recomendado
**Não.** Todos os itens vêm **desmarcados** (`autoselected = false`) [E2]. A
descrição do grupo na UI alerta que o conteúdo pode ter valor e deve ser revisado
(paráfrase) [E4].

## Agrupamento e nome exibido
- Lista plana, um item por `.dmg`, sem filhos ao expandir (o `.dmg` é tratado como
  arquivo, não é montado nem aberto).
- Nome exibido: o nome do arquivo (modelo genérico de arquivo). Proposta: mostrar o
  nome sem a extensão `.dmg` (ex.: `maria`), porque o macOS nomeia a imagem com o
  nome curto da conta apagada. Ver Divergências.
- Ícone: o ícone do arquivo dado pelo sistema (imagem de disco).
- Ícone do grupo: imagem própria (`system junk deleted users` na árvore AX) [E5].
- Na tela de Resultados existe um **cartão próprio** para este grupo, que aparece
  quando há algo encontrado (`Deleted Users Tile`; os textos são de
  "contas de usuário apagadas encontradas/removidas") [E4][E6]. A regra dos cartões
  é definida em `results-screen.md`.

## Cálculo de tamanho
Tamanho do arquivo `.dmg` pelo serviço padrão de tamanho (alocado) [E2]. Imagens
esparsas (`.sparseimage`/`.sparsebundle`) não entram, porque a extensão é diferente.

## Remoção
- O grupo não tem removedor especial. Usa a remoção genérica de arquivos do módulo:
  apaga **definitivamente** (não vai para o Lixo) e, quando falta permissão, passa
  para o removedor **privilegiado** (admin) [E7].
- A pasta `/Users/Deleted Users` e as imagens costumam ser do `root`. Por isso, na
  prática, a limpeza pede admin.
- A pasta `/Users/Deleted Users` em si não é apagada, mesmo que fique vazia.

## Alertas e selos
Nenhum alerta específico na remoção. O grupo só alerta pela descrição e por vir
desmarcado.

## requiresAdmin
- Análise: não. A pasta é legível por todos quando existe; se não for, o resultado
  fica vazio.
- Limpeza: **sim** (arquivos do root).

## Regras prontas (modelo CleanYourMac)
| Regra | Valor |
|---|---|
| Raiz | `/Users/Deleted Users` |
| Nível | filhos diretos, sem ocultos, sem recursão |
| Inclusão | glob `*.dmg` (extensão exata) |
| Idade mínima | nenhuma |
| Recomendado | não |
| Remoção | apagar definitivamente, com admin |
| Admin | análise não; limpeza sim |

## Baseline observada
- Grupo "Usuários Apagados": **0 KB**, nenhum item [E5].
- Leitura do disco: `/Users` só tem `Shared` e `guigx`, e `/Users/Deleted Users`
  **não existe** neste Mac [E8]. Isso é consistente com o 0 KB.

## Evidências
- **E1**: pseudocódigo de `CMPaths deletedUsersURL` (SharedObjcUtils). URL fixa `/Users/Deleted Users`; string correspondente em SharedObjcUtils.
- **E2**: pseudocódigo de `CMDeletedUsersScanTask _scan` / `scan` / `initWithKnowledgeBase:`. Existência da raiz, listagem com "pular descendentes + ocultos", filtro de extensão `dmg`, ignorar pela base, tamanho, `CMFileModel` com autoselected = falso.
- **E3**: pseudocódigo de `DeletedUsersKnowledgeBase shouldIgnoreURL:` / `isIgnoreItem:` (JunkCleanupModule). Delegação para a base de regras.
- **E4**: chaves de texto `system_junk_deleted_users_group_*` e `tiles_deleted_users_*` em `localizable-pt-BR.json` (só o sentido).
- **E5**: observação da baseline, `Detritos do Sistema/Usuários Apagados.txt`.
- **E6**: strings de JunkCleanupModule `Deleted Users Tile` e `CMSystemJunkScanIdentifierDeletedUsers`.
- **E7**: símbolos/strings de CleaningCore (`FileRemover`, `PrivilegedFileRemover`, `ConfigDependentFileRemover`, `MoveToTrashFileRemover`). Não há removedor dedicado a usuários apagados em JunkCleanupModule (a lista de `*RemovalTask` não inclui esse grupo).
- **E8**: leitura do disco (`ls /Users`, `ls "/Users/Deleted Users"`, só leitura).

## Divergências conhecidas
- **Não houve observação real.** A pasta não existe neste Mac. Nome, ícone e
  formato do item na UI não foram conferidos.
- **Nome exibido**: o modelo genérico expõe o arquivo. Se o CleanMyMac mostra
  `maria.dmg` ou `maria`, não foi observado. Adotamos o nome sem `.dmg` e marcamos
  esse ponto para conferência.
- **Remoção definitiva vs. Lixo**: a escolha do removedor genérico (definitivo com
  fallback privilegiado) foi inferida dos símbolos. O caminho exato no JunkCleanupModule
  não foi lido no pseudocódigo. Adotamos apagar definitivamente, porque mover uma
  imagem do root para o Lixo do usuário não faz sentido.
- **Base de regras cifrada**: o que é ignorado não é conhecido. A lista começa vazia.
- Não detectamos pastas pessoais órfãs em `/Users` (o CleanMyMac também não faz isso).

## Checklist de testes
1. Raiz ausente → vazio, sem erro.
2. `/Users/Deleted Users/maria.dmg` (fixture: raiz configurável no teste) → 1 item, desmarcado, tamanho = tamanho do arquivo, nome `maria`.
3. `joao.sparseimage` → nenhum item.
4. Pasta `pedro/` dentro da raiz → nenhum item.
5. `.oculto.dmg` → nenhum item.
6. `X.DMG` → nenhum item (extensão exata `dmg`).
7. `sub/ana.dmg` → nenhum item (sem recursão).
8. Dois `.dmg` → 2 itens; total do grupo = soma.
9. Limpeza de um item do root sem admin → pede admin; se for negado, erro reportado e o arquivo continua lá.
10. Limpeza com admin → arquivo apagado (não aparece no Lixo); a raiz continua lá.
