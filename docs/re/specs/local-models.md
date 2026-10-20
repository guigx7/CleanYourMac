# Modelos locais (`localModels`)

Categoria **Acúmulos de IA**. O CleanMyMac chama o grupo internamente de
`aiLocalModels` (E1).

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26 (Darwin 25.6.0), análise de 20/10/2026.
Neste Mac o grupo veio **vazio (0 KB)**: não existem `~/.ollama` nem `~/.lmstudio`
(E13). Por isso, tudo aqui vem da análise estática do framework
`LocalModelScanning` e do formato público do Ollama e do LM Studio.

## Fonte das regras
As regras estão fixas no código do `LocalModelScanning`. A base cifrada não
entra (E2). Há duas "lojas" (`LocalModelStore`), nesta ordem: `ollama` e
`lmStudio`. Há dois formatos (`LocalModelFormat`): `gguf` e `mlx` (E3).

## Locais varridos
| Loja | Raiz | Observação |
|---|---|---|
| Ollama | `~/.ollama/models` (manifests em `models/manifests`, blobs em `models/blobs`) | não lê `OLLAMA_MODELS` (E4) |
| LM Studio | `~/.lmstudio/models` | não lê `~/.cache/lm-studio` nem a pasta configurada no app (E5) |

`~` é a home real do usuário. Uma loja que não existe é ignorada. Um erro
numa loja é reportado e não impede a outra (`onStoreError`) (E6).

## Inclusão

### Ollama (E4, E7, E8, E9)
1. Percorre `~/.ollama/models/manifests` recursivamente, **até 7 níveis**. Cada
   **arquivo** encontrado é um manifesto. Pela convenção do Ollama, o caminho
   relativo é `<registro>/<namespace>/<modelo>/<tag>` (ex.:
   `registry.ollama.ai/library/llama3.2/latest`).
2. Lê o manifesto (JSON, **no máximo 1 MiB**; maior que isso é pulado). Usa os
   campos `config.digest` e `layers[].digest` / `layers[].mediaType`.
   Um manifesto ilegível marca a loja com erro de manifesto indecodificável.
3. Digest `sha256:<hex>` → arquivo `~/.ollama/models/blobs/sha256-<hex>` (troca
   `:` por `-`).
4. **Contagem de referências.** Para **todos** os manifestos, soma-se quantas
   vezes cada blob é referenciado (config + layers): um mapa `blob → n` (E8).
5. Um manifesto vira um modelo se tiver uma camada cujo `mediaType` **termina em
   `.model`** (`application/vnd.ollama.image.model`), cujo blob existe. Esse é o
   arquivo de pesos (E9).
6. Campos do modelo:
   - `id` = `ollama:` + caminho do manifesto;
   - `format` = `gguf`;
   - `url` = blob de pesos;
   - `sizeBytes` = tamanho do blob de pesos;
   - `blobURLs` = todos os blobs do manifesto (config + layers);
   - `manifestURL` = arquivo do manifesto;
   - `companionBytes` = 0;
   - `downloadDate` = data do arquivo (lida dos atributos);
   - `displayName`: ver "Agrupamento e nome exibido".

### LM Studio (E5, E10, E11, E12)
1. Nível 1: filhos de `~/.lmstudio/models` que são pastas (o *publisher*),
   ignorando `.internal` e nomes ocultos. Nível 2: cada pasta dentro deles é uma
   **pasta de modelo** (ex.: `lmstudio-community/Qwen3-8B-GGUF`).
2. Na pasta de modelo, listam-se os arquivos com tamanho:
   - **GGUF**: arquivos `*.gguf`. Shards no padrão `<base>-<i>-of-<n>.gguf` (com
     `i` e `n` numéricos) são agrupados num **único** modelo pela chave `<base>`.
     Um arquivo sem esse padrão é um modelo sozinho. `shardURLs` = os arquivos do
     grupo. `sizeBytes` = soma deles. Se houver pelo menos um modelo GGUF, a
     pasta é tratada como GGUF.
   - **MLX** (só se não houver GGUF): exige `config.json` (até 1 MiB) com a chave
     `model_type`. O modelo = os arquivos `*.safetensors` da pasta (`sizeBytes` =
     soma deles). `format` = `mlx`.
   - Sem GGUF e sem MLX válido, a pasta não gera modelo.
3. `companionBytes` = os demais arquivos da pasta (JSON, tokenizer, README…),
   atribuídos ao modelo quando ele é o único da pasta.
4. `id` = `lmStudio:` + `<publisher>/<pasta>` (mais o nome do arquivo/grupo,
   no GGUF). `totalBytes` = `sizeBytes + companionBytes` (com saturação).

### Plano de remoção (uma linha por modelo) (E14, E15, E16)
O resultado da análise (`LocalModelInventory`) tem a lista de modelos e as
**linhas de remoção** (`LocalModelRemovalPlan`: modelo, URLs a apagar,
`exclusiveBytes`, `anchorURL`). **A UI mostra uma linha por plano.**
- **Ollama:**
  - `urls` = o manifesto + cada blob do modelo cuja contagem global de
    referências é **1** (só este manifesto o usa);
  - `exclusiveBytes` = soma desses blobs (mais o manifesto);
  - `anchorURL` = o manifesto.
  - Blobs compartilhados com outro modelo **não** entram.
  - **Trava de segurança:** se o mapa de referências não pôde ser montado (ex.:
    algum manifesto ilegível) e houver modelos, **não se gera nenhuma linha do
    Ollama**, porque não dá para saber o que é exclusivo.
- **LM Studio:**
  - se a pasta de modelo contém **só este** modelo e não é uma pasta protegida,
    `urls` = a **pasta de modelo inteira**, `anchorURL` = a pasta e
    `exclusiveBytes` = `totalBytes`;
  - se a pasta contém **vários** modelos (ex.: várias quantizações GGUF lado a
    lado), `urls` = só os arquivos do modelo (`shardURLs`) e `exclusiveBytes` =
    `sizeBytes`.
- As linhas são ordenadas pela ordenação padrão (tamanho decrescente).

## Exclusão
- Manifestos > 1 MiB, manifestos sem camada `.model`, blob de pesos inexistente.
- No LM Studio: `.internal`, ocultos, pastas sem GGUF/MLX válido, `config.json`
  sem `model_type`.
- **O que NUNCA é removido:** blobs referenciados por qualquer manifesto que
  continua no disco; a raiz `~/.ollama/models`, `models/blobs`,
  `models/manifests` e as pastas de registro/namespace; `~/.ollama/id_ed25519*`,
  `history`, `logs` e a configuração; `~/.lmstudio/models` e as pastas de
  *publisher*; qualquer coisa em `~/.lmstudio` fora de `models/` (configurações,
  conversas, `extensions`, `bin`). Uma pasta "protegida"
  (`isProtectedFolder` do serviço de arquivos) nunca é apagada inteira.

## Recomendado
**Nenhum.** Todos os modelos começam desmarcados. Há uma opção de seleção extra
deste grupo (`AIClutterOldestSelectionControlOption`, "os mais antigos") (E17).
A nossa regra equivalente: entre linhas com o mesmo modelo-base (mesmo nome
antes de `:` no Ollama, mesma pasta de modelo no LM Studio) e mais de uma
versão, marca todas, exceto a de `downloadDate` mais recente. Ela só é
aplicada quando o usuário escolhe essa opção.

## Agrupamento e nome exibido
- **Lista plana**: um nó folha por linha de remoção
  (`JunkCleanupItemNode<LocalModelRowModel, Node>`), sem nó pai por loja (E17).
- **Nome:**
  - Ollama: pela convenção do Ollama, `<modelo>:<tag>` quando o registro é
    `registry.ollama.ai` e o namespace é `library` (ex.: `llama3.2:latest`).
    Senão, `<namespace>/<modelo>:<tag>`, com o host incluído se não for o
    padrão (ex.: `hf.co/user/repo:Q4_K_M`);
  - LM Studio GGUF: nome do arquivo sem `.gguf` e sem o sufixo
    `-<i>-of-<n>`;
  - LM Studio MLX: nome da pasta do modelo.
- **Detalhe** (subtítulo): loja (Ollama / LM Studio), formato (GGUF / MLX) e
  data de download, com formatador de data próprio do grupo
  (`localModelDownloadDateFormatter`). Usar data no estilo médio, sem hora
  (E17).
- **Tamanho exibido** = `exclusiveBytes` (o que de fato será liberado).
- **Ícone:** ícone do app da loja se instalado (`com.electron.ollama` → Ollama.app,
  `ai.elementlabs.lmstudio` → LM Studio.app), senão o SF Symbol `cpu`. Regra
  nossa: o ícone exato não foi observado.

## Cálculo de tamanho
- Tamanho lógico de cada arquivo (atributo de tamanho do arquivo).
- **Sem contar duas vezes:** o total do grupo = soma de `exclusiveBytes` das
  linhas. Como um blob compartilhado nunca é exclusivo de ninguém, ele não entra
  em nenhuma linha nem no total. Os conjuntos exclusivos são disjuntos por
  construção.
- `sizeBytes`/`totalBytes` do modelo são informativos (podem incluir blobs
  compartilhados) e não somam no total.

## Remoção
- **Alerta antes de remover** (E18): quando o usuário clica em Limpar e há pelo
  menos um modelo local marcado, aparece **uma** confirmação antes de começar a
  limpeza (de toda a seleção). O título avisa que remover modelos locais pode
  afetar os projetos do usuário. A mensagem diz que os projetos ainda podem usar
  esses modelos e que vão dar erro até serem baixados de novo. Botões: Cancelar
  (aborta tudo, nada é apagado) e Continuar. Escreva os textos com as nossas
  palavras.
- **Como apaga:** apagar definitivamente as `urls` do plano (manifesto + blobs
  exclusivos, no Ollama; pasta inteira ou arquivos do modelo, no LM Studio).
- **Nossa regra no momento da limpeza (Ollama):** recalcule as referências com
  os manifestos **atuais** do disco. Depois de tirar os manifestos selecionados,
  apague todo blob deles que não for mais referenciado por nenhum manifesto que
  fica. Isso inclui os blobs compartilhados **só** entre modelos selecionados e
  exclui qualquer blob que ganhou uma referência nova desde a análise. Se algum
  manifesto restante estiver ilegível, apague só os manifestos selecionados e
  nenhum blob.
- Pastas vazias que sobram em `manifests/` podem ficar.
- Não fecha o Ollama nem o LM Studio.
- Admin: não.

## Alertas e selos
- Alerta de confirmação acima (o único da categoria).
- Sem selos.

## requiresAdmin
- Análise: não.
- Limpeza: não.

## Evidências
- **E1** — strings do LocalModelScanning: `aiLocalModels` (rawValue de
  `LocalModelScanIdentifier`).
- **E2** — símbolos do LocalModelScanning: só `FileManagerService` como
  dependência (`LocalModelScanTasksFactory.init(fileManager:)`), sem base de
  conhecimento.
- **E3** — pseudocódigo de `LocalModelStore.rawValue`/`allCases` (`ollama`,
  `lmStudio`) e de `LocalModelFormat.rawValue` (`gguf`, `mlx`).
- **E4** — pseudocódigo da varredura do Ollama: raiz `.ollama` + `models/manifests`,
  enumeração com profundidade 7, `models/blobs`. As strings não contêm
  `OLLAMA_MODELS`.
- **E5** — pseudocódigo da varredura do LM Studio: raiz `.lmstudio` + `models`,
  dois níveis de pastas. Só aparece a string `.lmstudio` (nenhuma `lm-studio`).
- **E6** — símbolo `makeLocalModelsScanTask(onStoreError:)`.
- **E7** — pseudocódigo da leitura de manifesto (limite de leitura 0x100000) e
  dos decodificadores com as chaves `config`, `layers`, `digest`, `mediaType`.
  String `undecodableManifest`.
- **E8** — pseudocódigo da conversão de digest (`sha256:` → `sha256-`) e
  símbolo `LocalModelStoreScanResult.blobReferences : [URL : Int]`.
- **E9** — pseudocódigo da criação do modelo Ollama: sufixo `.model` no
  `mediaType`, id com prefixo `ollama:`, `OllamaDetails(manifestURL:blobURLs:)`.
  Símbolo de `LocalModelStore.modelID(forPath:)` (prefixo `ollama:`/`lmStudio:` + `:`).
- **E10** — pseudocódigo do filtro de pastas do LM Studio (compara o nome com
  `.internal`, mantém só as pastas).
- **E11** — pseudocódigo da classificação da pasta de modelo: extensão `gguf`
  primeiro; senão `config.json` + `model_type` + extensão `safetensors`. Strings
  `ShardFileName`, `ShardGroupKey`, `shardURLs`, `companionBytes`.
- **E12** — pseudocódigo do analisador de nome de shard: divide por `-`, exige
  ≥ 4 partes, penúltima `of`, última e antepenúltima numéricas, e chave = o
  resto.
- **E13** — leitura do disco: `~/.ollama`, `~/.lmstudio` e `~/.cache/lm-studio`
  não existem neste Mac.
- **E14** — símbolos `LocalModelRemoval.rows(from:allManifestBlobReferences:isProtectedFolder:)`
  e `LocalModelRemovalPlan(model:urls:exclusiveBytes:anchorURL:)`.
- **E15** — pseudocódigo de `rows`: separa por loja. O ramo do Ollama só roda
  com o mapa de referências presente (e não vazio quando há modelos). O ramo do
  LM Studio agrupa por pasta, e uma pasta com 1 modelo, não protegida, vira a
  âncora/URL.
- **E16** — pseudocódigo do plano do Ollama: contagem local versus contagem
  global de cada blob.
- **E17** — strings do JunkCleanupModule: `JunkCleanupItemNode<LocalModelRowModel, Node>`,
  `localModelDownloadDateFormatter`, `AIClutterOldestSelectionControlOption`,
  `AIClutterOldestSelectionControlNodeType`.
- **E18** — localização `ai_clutter_local_model_alert_title/_message/_cancel_button/_confirm_button`.
- **E19** — baseline `Acúmulos de IA/Modelos locais.txt`: grupo com 0 KB e a
  tela "nada para limpar".

## Baseline observada
- "Modelos locais": **0 KB**, estado vazio (sem Ollama nem LM Studio neste Mac).

## Divergências conhecidas
- **Sem observação real.** O nome exibido, a data e o ícone vêm de inferência
  (convenção pública do Ollama/LM Studio). Para conferir: instalar o Ollama, rodar
  `ollama pull` em dois modelos que compartilham camadas (ex.: duas tags do
  mesmo modelo), analisar no CleanMyMac e comparar nomes e tamanhos.
- **Limpeza do Ollama:** o CleanMyMac apaga, por linha, só o que era exclusivo
  na análise. Nós recalculamos na hora e também apagamos blobs que ficaram
  órfãos entre modelos selecionados juntos. Isso libera mais espaço e nunca
  apaga um blob ainda referenciado.
- **Opção "mais antigos":** o critério exato de "versões similares" não foi
  confirmado. A regra acima é nossa.
- **Raízes:** não suportamos `OLLAMA_MODELS` nem a pasta de modelos
  personalizada do LM Studio, assim como o CleanMyMac.
- **Data de download:** usamos a data de criação do arquivo de pesos (Ollama:
  blob `.model`; LM Studio: primeiro shard ou maior `.safetensors`).

## Checklist de testes
Fixtures com `FixtureTree` (home falsa).
1. Sem `~/.ollama` e sem `~/.lmstudio` → grupo vazio, 0 KB.
2. Ollama com um manifesto `registry.ollama.ai/library/m/latest` (config `sha256:c1`,
   layers `model sha256:w1` e `params sha256:p1`), blobs existentes → 1 linha
   "m:latest", `exclusiveBytes` = c1+w1+p1 (+manifesto), desmarcada.
3. Dois manifestos `m:latest` e `m:q4` que compartilham `w1`, com configs
   próprias → cada linha mostra só a própria config (w1 fica de fora). O total do
   grupo não conta w1.
4. Remover só `m:q4` (cenário 3) → apaga o manifesto q4 e a config dele. `w1`
   continua (ainda é referenciado por latest).
5. Remover `m:latest` e `m:q4` juntos → apaga os dois manifestos, as duas
   configs **e** `w1` (órfão).
6. Manifesto sem camada `.model` → não vira modelo, mas os blobs dele contam
   nas referências (um blob compartilhado com ele não é exclusivo).
7. Um manifesto com JSON inválido + outro válido → nenhuma linha do Ollama (trava
   de segurança). A loja reporta erro.
8. Manifesto > 1 MiB → pulado.
9. Blob de pesos ausente → modelo não criado.
10. LM Studio `pub/Model-GGUF/model-Q4.gguf` (1 GB) + `README.md` (1 KB), sozinho
    na pasta → 1 linha "model-Q4", formato GGUF, `exclusiveBytes` ≈ 1 GB + 1 KB.
    A remoção apaga a pasta `pub/Model-GGUF`.
11. Mesma pasta com `model-Q4.gguf` e `model-Q8.gguf` → 2 linhas. Remover Q4 apaga
    só `model-Q4.gguf`. A pasta, o Q8 e o README ficam.
12. `x-00001-of-00002.gguf` + `x-00002-of-00002.gguf` → 1 modelo "x", com
    `shardURLs` = 2 arquivos e tamanho = soma.
13. `x-1-of-two.gguf` → não é shard (último não numérico), vira modelo próprio.
14. Pasta MLX com `config.json` contendo `model_type` + 2 `.safetensors` → 1
    modelo MLX, tamanho = soma dos safetensors. Sem `model_type` → nada.
15. Pasta com GGUF e safetensors → tratada como GGUF (os safetensors viram
    companion).
16. `~/.lmstudio/models/.internal/...` → ignorado.
17. Clicar em Limpar com 1 modelo marcado → alerta aparece. Cancelar → nada
    apagado (nem os itens de outros grupos). Continuar → limpeza segue.
18. Clicar em Limpar sem modelo local marcado → sem alerta.
19. A opção "mais antigos" com `m:latest` (jan) e `m:q4` (mar) → marca só
    `m:latest`.
