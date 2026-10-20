# Preferências Defeituosas (`brokenPreferences`)

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2. Análise de 2026-10-20 (baseline
`baseline-20261020-1457`).

## Locais varridos
- Uma única raiz: `~/Library/Preferences` (a pasta Preferences do usuário atual) [E1][E2].
- Se a raiz não existir, o resultado é vazio [E2].
- Listagem **não recursiva**: só os filhos diretos, **sem arquivos ocultos** [E3].
  Subpastas como `ByHost/` não são abertas. Elas próprias também não viram item,
  porque não passam no filtro de extensão.
- `/Library/Preferences`, `ByHost` e as preferências dentro de containers de sandbox
  **não** são varridos.

## Inclusão
Para cada filho direto, nesta ordem [E4][E5]:
1. Se a base de regras manda ignorar a URL → ignora.
2. O arquivo precisa **existir**.
3. O nome **não pode começar com `.`**.
4. A extensão, em minúsculas, precisa ser `plist`. `X.PLIST` também conta.
5. O caminho **não pode conter `.lockfile`**.
6. O tamanho em bytes (atributo `NSFileSize`) precisa ser **> 0**. Arquivo vazio
   **não** é considerado defeituoso.
7. O arquivo **não pode estar bloqueado** (`NSFileImmutable` = falso).
8. Abre um stream de leitura. **Se não conseguir abrir** (ex.: sem permissão / TCC),
   o arquivo é considerado **não defeituoso**.
9. Tenta interpretar como property list (qualquer formato, XML ou binário):
   - se a interpretação **falhar** → **defeituoso**;
   - se der certo, mas a lista não for válida para o formato detectado
     (`CFPropertyListIsValid` falso) → **defeituoso**;
   - senão → saudável.

Cada arquivo defeituoso vira **um item** (o próprio arquivo) [E5].

## Exclusão
- Ocultos (`.`), não-`plist`, `*.lockfile*`, vazios (0 bytes), bloqueados (imutáveis)
  e ilegíveis [E4].
- Itens marcados pela base de regras para este grupo (`BrokenPreferencesKnowledgeBase`
  → `shouldIgnoreURL` / `isIgnoreItem`) [E6]. A base é cifrada (ver Divergências).
- Não há exclusão de `com.apple.*` no código. Ela só existiria pela base.
- Não há verificação de "arquivo em uso".

## Recomendado
Todos os itens vêm **marcados** (`autoselected = true`) [E5].

## Agrupamento e nome exibido
- Lista plana, um item por arquivo, sem filhos.
- Nome exibido = nome do arquivo **sem a extensão final** (corta no último ponto,
  buscando de trás para frente). Ex.: `com.foo.app.plist` → `com.foo.app` [E5].
- Ícone: não vem do código de análise. Proposta: o ícone do app dono quando o
  domínio coincidir com o bundle id de um app instalado (via `NSWorkspace`
  `urlForApplication(withBundleIdentifier:)`); senão, o ícone de documento plist.
- Ícone do grupo: imagem própria (`system junk broken preferences` na árvore AX) [E7].

## Cálculo de tamanho
Tamanho do arquivo pelo serviço padrão de tamanho (alocado) [E5]. O total do grupo
é a soma.

## Remoção
Por item [E8]:
1. Se o caminho não existe mais → nada a fazer.
2. Se a extensão é `lockfile` → pula o passo 3.
3. Senão, roda `/usr/bin/defaults delete <domínio>`, onde o domínio é o caminho do
   arquivo sem `.plist`. Isso limpa o cache do `cfprefsd` para esse domínio. O
   resultado ("OK"/"Error") só vai para o log, e uma falha não interrompe.
4. Marca que o `cfprefsd` precisa ser **reiniciado** (`CMCFPrefsdManager
   setNeedsRelaunch`) ao fim da limpeza.
5. Apaga o arquivo com o removedor de arquivos padrão (definitivo).

- Não precisa de admin (a pasta é do usuário).
- Erro por item: mensagem genérica com o nome (parafrasear: "não foi possível
  remover as preferências de X").

## Alertas e selos
Nenhum.

## requiresAdmin
- Análise: não.
- Limpeza: não.

## Regras prontas (modelo CleanYourMac)
| Regra | Valor |
|---|---|
| Raiz | `~/Library/Preferences` |
| Nível | filhos diretos, sem ocultos, sem recursão |
| Inclusão | `*.plist` (extensão sem diferenciar maiúsculas), tamanho > 0, não imutável, legível, e falha ao interpretar como plist |
| Exclusão | começa com `.`, contém `.lockfile`, ilegível, vazio, bloqueado |
| Idade mínima | nenhuma |
| Recomendado | sim |
| Remoção | `defaults delete <caminho sem .plist>` (sem falhar), apagar definitivo, reiniciar o `cfprefsd` do usuário no fim |
| Admin | não |

## Baseline observada
- Grupo "Preferências Defeituosas": **0 KB**, nenhum item [E7].
- Leitura do disco, só leitura, com `plutil -lint`, em 2026-10-20: 377 `.plist` em
  `~/Library/Preferences`. Oito deram erro, **todos por falta de permissão** (TCC:
  `com.apple.AddressBook`, `com.apple.MobileSMS*`, `com.apple.homed*`,
  `com.apple.madrid`, `com.apple.mail-shared`, `com.apple.messages.pinning`). Pela
  regra 8, ilegível = saudável, o que é consistente com o 0 KB. Nenhum plist legível
  estava corrompido [E9].

## Evidências
- **E1**: pseudocódigo de `CMBrokenPreferencesScanTask initWithKnowledgeBase:` e `CMPaths userPreferences` (SharedObjcUtils). A raiz é `~/Library/Preferences`.
- **E2**: pseudocódigo de `CMBrokenPreferencesScanTask scan`. Checa a existência da raiz e mapeia os filhos.
- **E3**: pseudocódigo de `CMBrokenPreferencesScanTask scanningPathsWithURL:`. `contentsOfDirectory` com opções "pular descendentes + pular ocultos".
- **E4**: pseudocódigo de `CMBrokenPreferencesScanTask _isPreferenceFileBrokenWithPlistPath:`. Ordem das checagens, `NSFileSize`, `NSFileImmutable`, `CFReadStreamOpen`, `CFPropertyListCreateWithStream`, `CFPropertyListIsValid`. Strings `plist`, `.lockfile`.
- **E5**: pseudocódigo de `CMBrokenPreferencesScanTask junkModelWithURL:cancellationFlag:` e do bloco de mapeamento (FUN_000044d0). Ignorar pela base, nome sem extensão, tamanho, `CMBrokenPreferencesModel` autoselecionado.
- **E6**: pseudocódigo de `BrokenPreferencesKnowledgeBase shouldIgnoreURL:` / `isIgnoreItem:` (JunkCleanupModule). Delegação para a base de regras.
- **E7**: observação da baseline, `Detritos do Sistema/Preferências Defeituosas.txt`.
- **E8**: pseudocódigo de `BrokenPreferencesRemover.removePreferences(_:)` e símbolo `BrokenPreferencesRemover.init(fileManager:prefsdManager:fileRemover:)`. String `/usr/bin/defaults`, argumento `delete`, comparação com `lockfile`, `setNeedsRelaunch:`.
- **E9**: leitura do disco (`plutil -lint`, `ls -lO`, só leitura) em `~/Library/Preferences`.

## Divergências conhecidas
- **Não houve observação real** de um plist defeituoso (o grupo estava em 0 KB).
- **Base de regras cifrada**: o que a base manda ignorar neste grupo não é conhecido.
  Proposta: lista de ignorar configurável, que começa vazia. Não adicionamos
  `com.apple.*`, para manter a paridade.
- **Argumento exato do `defaults delete`**: o pseudocódigo sugere um caminho derivado
  do arquivo, mas a transformação exata (sem extensão vs. outra) não ficou
  inequívoca. Usamos o caminho absoluto sem `.plist`, que o `defaults` aceita como
  domínio. Como o arquivo é apagado logo depois, o efeito final é o mesmo.
- **Reinício do `cfprefsd`**: o CleanMyMac adia o reinício para o fim. Fazemos
  `killall -u <usuário> cfprefsd` uma vez, ao fim da limpeza, só se pelo menos um
  item foi removido.
- Rodamos sem Acesso Total ao Disco, então os plists protegidos por TCC ficam
  ilegíveis e são tratados como saudáveis (mesma regra).

## Checklist de testes
1. `~/Library/Preferences/a.plist` com texto lixo (`"xx<<"`) → 1 item `a`, marcado, tamanho = tamanho do arquivo.
2. `b.plist` XML válido → nenhum item.
3. `c.plist` binário válido (`plutil -convert binary1`) → nenhum item.
4. `d.plist` com 0 bytes → nenhum item.
5. `.e.plist` corrompido (oculto) → nenhum item.
6. `f.plist.lockfile` / `g.lockfile.plist` corrompido → nenhum item.
7. `H.PLIST` corrompido → 1 item `H`.
8. `i.txt` corrompido → nenhum item.
9. `ByHost/j.plist` corrompido → nenhum item (sem recursão).
10. `k.plist` corrompido com `chflags uchg` → nenhum item.
11. `l.plist` corrompido com `chmod 000` → nenhum item.
12. Raiz ausente → resultado vazio, sem erro.
13. Remoção de `a.plist` → `defaults delete <…/a>` chamado, arquivo apagado, reinício do `cfprefsd` agendado.
14. Remoção de um arquivo de extensão `lockfile` → `defaults` não chamado, arquivo apagado.
