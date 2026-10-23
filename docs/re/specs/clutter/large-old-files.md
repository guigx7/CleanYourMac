# Acúmulos: Fundo do Baú (arquivos grandes e antigos, `laof`)

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83), Apple Silicon (arm64), 2026-10-23.
Só análise estática (`OrganizeModule`, com o código embutido de `LAOFScanning`;
`OrganizeScanning`), dump AX do Gerenciador (`re-notes/ax/clutter-20261023/manager.txt`) e
leitura do disco (`stat`, `mdls`). Nada foi clicado no CleanMyMac. Método de leitura do código:
disassembly anotado em `re-notes/disasm/` (ver `duplicates.md`).

"LAOF" = *Large And Old Files*, nome interno. Na interface: **Fundo do Baú** (categoria do
Gerenciador e cartão) e **Arquivos grandes** (Smart Care e Intro).

Legenda: **[E*n*]** = evidência (lista no fim). **(inferência)** = conclusão nossa.

## 1. Locais varridos

### O que o CleanMyMac faz
- **Raiz: a pasta pessoal** (mesma montagem das tarefas de Duplicatas e Similares; a fábrica
  `LAOFScanTaskFactory.createLAOFScanTask(directory:rules:logName:)` recebe a pasta) [E1].
  Observado: os itens listados estão em `~/Downloads` [E2].
- **Regras** = regras comuns (`duplicates.md` §1: 13 padrões de nome, 79 extensões de
  código/build, prefixos `/System/`, `/Library/`, `~/Library/`, `~/Music/Music/`,
  `~/Music/iTunes/`, ocultos fora, pacotes `photoslibrary`/`musicLibrary` fora) **mais uma
  regra própria** (`laofSpecificRules`) [E3]:
  - **tamanho mínimo de 52.428.800 bytes (50 MiB)** (`MinimumFileSizeIgnoreRule`).
- A fototeca **não** entra no Fundo do Baú (só Duplicatas e Similares leem
  `DirectoryURLProvider.photoLibrary`) [E1].
- **Pacotes** (`.app` etc.): não há regra de pacote própria do LAOF (inferência: um pacote é
  pasta para a enumeração, então só arquivos soltos ≥ 50 MiB dentro dele apareceriam; `.app` em
  `~/Applications` é raro).
- **iCloud:** `isUbiquitousItem` é lido na montagem do resultado (`LAOFScanProduct`) junto com
  `isHidden`, `fileSize` e a data de acesso; o tratamento exato não foi lido (inferência: item
  só na nuvem sai, porque não ocupa espaço local) [E4].

### Para o CleanYourMac (forma proposta)
- Raiz `~`; mesmas exclusões; tamanho mínimo 50 MiB; itens não baixados do iCloud fora.

## 2. Critério de "antigo"

### O que o CleanMyMac faz
- A data usada é a **data de último acesso do sistema de arquivos**: `NSURLContentAccessDateKey`
  (o `atime` do POSIX) → `LAOFFileModel.accessDate`, mostrada como "A última vez que você abriu
  o arquivo" [E4][E5]. **Não** usa `kMDItemLastUsedDate` (nenhum dos binários importa chaves do
  Spotlight para isso).
- **Prova nesta máquina** [E2][E6]: `Cyberduck-9.5.2.45323.zip` e `HG Vídeo Final -.MOV`
  aparecem com "6 de ago. de 2026"; o `stat` dá `atime` = 6 ago 2026 22:15 para os dois, e o
  `kMDItemLastUsedDate` deles é nulo. `Godot_v4.7.2…zip` aparece com 6 out 2026 = seu `atime`.
  - Consequência: qualquer leitura do arquivo (backup, indexação, antivírus, `cat`) "rejuvenesce"
    o item. Os dois arquivos acima têm o mesmo `atime` com 1 s de diferença, sinal de leitura em
    lote, não de uso pelo usuário (inferência).
- **A análise não filtra por idade:** o Gerenciador mostra arquivos acessados na última semana
  (filtro "Semana Passada" com 60,8 MB) [E2]. "Antigo" só aparece nos filtros de data e no cartão
  (ver §4 e §5).

### Para o CleanYourMac (forma proposta)
- Data de "última abertura" = a **mais recente** entre `kMDItemLastUsedDate` (Spotlight,
  atualizado quando o usuário abre o arquivo por LaunchServices) e `contentAccessDate`. Se o
  Spotlight não tiver valor, cair para `contentAccessDate` (igual ao CleanMyMac). Documentar
  na UI que a data é aproximada.
- Divergência consciente: o `atime` sozinho sofre com leituras de backup.

## 3. Tipos (filtro "Por Tipo")

### O que o CleanMyMac faz
- `LAOFKind`, 5 valores, classificados por conformidade de UTI [E7]:

  | Filtro (texto curto) | Tooltip (sentido) | Tipo testado |
  |---|---|---|
  | Arq. Comp. | arquivos comprimidos de vários formatos | `UTType.archive` |
  | Documentos | documentos de vários formatos | `UTType.text` |
  | Imagens | imagens de vários formatos | `UTType.image` |
  | Vídeos | vídeos de vários formatos | `UTType.movie` |
  | Outro | arquivos de diversos formatos | o resto |

- Filtros sem itens não aparecem. Observado: "Arq. Comp. 350 MB", "Vídeos 1,3 GB", "Outro
  60,8 MB" (sem Documentos nem Imagens) [E2].

## 4. Filtros de tamanho e de data (limites exatos)

### Tamanho ("Por Tamanho"), em bytes, unidades decimais [E8]
| Filtro | Regra |
|---|---|
| Pequeno | 50.000.000 ≤ tamanho < 500.000.000 |
| Médio | 500.000.000 ≤ tamanho < 1.000.000.000 |
| Imenso | tamanho ≥ 1.000.000.000 (código: `> 999.999.999`) |

Como o mínimo da análise é 50 MiB (52,4 MB), "Pequeno" começa na prática em 52,4 MB.
Observado: "Imenso 1 GB" (um `.mov` de 1 GB) e "Pequeno 678 MB" [E2].

### Data de acesso ("Por Data de Acesso") [E9]
O código calcula, a partir de hoje e do calendário atual: **−1 ano**, **−6 meses**, **−1 mês**,
**−1 semana** (componente `weekOfYear`) e **−7 dias**, e compara `accessDate` com `<=` / `>`.
As faixas são **exclusivas** (observado: 1,5 GB + 171 MB + 60,8 MB = 1,7 GB = "Todos os
Arquivos") [E2]:

| Filtro | Faixa de `accessDate` |
|---|---|
| Semana Passada | nos últimos 7 dias ("abertos há menos de uma semana") |
| Há Uma Semana | entre 1 mês e 1 semana atrás |
| Há Um Mês | entre 6 meses e 1 mês atrás |
| Há Seis Meses | entre 1 ano e 6 meses atrás |
| Há Um Ano | há mais de 1 ano |

(As fronteiras exatas, `<` × `<=`, ficam como inferência; a ordem das cinco datas e o caráter
exclusivo estão confirmados.)

### Outros filtros
- **Todos os Arquivos** ("Não há nenhum filtro em uso") e **Selecionados** ("Os itens
  selecionados aparecerão aqui") [E10].

## 5. Cartões e Smart Care

### O que o CleanMyMac faz
- **Cartão "Fundo do Baú"** nos Resultados (`LAOFRule` + `LAOFTileNodeRepresentation`): conta os
  arquivos com **agora − `accessDate` > 31.536.000 s (365 dias)** [E11]. Título "%@ de Arquivos
  Grandes e Antigos Encontrados"; texto "Considere remover arquivos grandes e desnecessários que
  você pode ter esquecido"; no Gerenciador, "… arquivos grandes que você não abre há mais de um
  ano". Depois da remoção: "%@ de Arquivos Grandes Removidos".
  - Observado: com 1,7 GB no Fundo do Baú mas nada acessado há mais de 1 ano, **não houve cartão**
    do Fundo do Baú (os três cartões eram de Similares, Duplicatas e Downloads) [E2].
- **Smart Care:** configuração `OrganizeModuleConfig.smartCareLAOF`, categoria "Arquivos grandes"
  ("Esta categoria inclui arquivos grandes que talvez você não precise mais"), com textos de
  análise "Procurando arquivos grandes que desperdiçam espaço" [E10] (inferência: usa o mesmo
  critério de 1 ano do cartão).

### Para o CleanYourMac (forma proposta)
- Cartão: arquivos com última abertura > 365 dias (com a data "mais recente" do §2).
- Nada vem marcado sozinho: arquivo grande antigo não tem "cópia de sobra" (decisão alinhada
  com o observado: seleção inicial vazia).

## 6. Linha da lista
Ícone, nome, caminho resumido (`guigx › Downloads`), **data do último acesso** e tamanho [E2].
O tamanho exibido é o **lógico** em unidades decimais (`Godot…zip`: 170.622.178 bytes → "171 MB")
[E6].

## 7. Remoção
Ver `results-and-manager.md` §6. **Nosso app:** Lixo, com `PathPolicy`; arquivos abertos por
algum app: erro amigável e o item continua na lista.

## requiresAdmin
- Análise: não. Limpeza: não.

## Evidências
- **E1** — disasm `re-notes/disasm/OrganizeModule.d.s` @0x58ab8 (monta as fábricas de Downloads,
  Duplicatas, LAOF e Similares) e @0x11c40 (`FileManagerProvider.realHomeDirectory`);
  `DirectoryURLProvider.photoLibrary` só em funções de Duplicatas/Similares.
- **E2** — `re-notes/ax/clutter-20261023/manager.txt` e `results.txt`.
- **E3** — disasm `re-notes/disasm/OrganizeScanning.d.s` @0x18b64 (`laofSpecificRules`): array
  de 1 regra, `MinimumFileSizeIgnoreRule` com a constante `(52428800, 7)` em `__TEXT,__const`
  @0x2e650.
- **E4** — disasm `OrganizeModule.d.s` @0x91ff0: `NSURLContentAccessDateKey`,
  `NSURLIsUbiquitousItemKey`, `NSURLIsHiddenKey`, `NSURLFileSizeKey`; símbolo
  `LAOFFileModel.accessDate`.
- **E5** — `localizable-pt-BR.json`: `laof_formatted_last_access_date_tooltip`.
- **E6** — `stat -f` e `mdls` (só leitura) nos três arquivos citados em `~/Downloads`.
- **E7** — disasm `OrganizeModule.d.s` @0x8fe24: `UTType.archive`, `.text`, `.image`, `.movie`;
  `localizable-pt-BR.json`: `laof_filter_by_kind_*`.
- **E8** — disasm `OrganizeModule.d.s` @0x48ffc (`size > 0x3B9AC9FF`), @0x49040
  (`size − 500.000.000 < 500.000.000`, sem sinal) e @0x49090 (`size − 50.000.000 <
  450.000.000`); textos `laof_filter_by_size_*` ("centenas de megabytes a um gigabyte",
  "gigabytes").
- **E9** — disasm `OrganizeModule.d.s` @0x48ad4: cinco `Calendar.date(byAdding:value:to:)` com
  (`.year`, −1), (`.month`, −6), (`.month`, −1), (`.weekOfYear`, −1), (`.day`, −7); funções
  seguintes comparam com `Comparable.<=` e `Date.>`; textos `laof_filter_by_access_date_*`.
- **E10** — `localizable-pt-BR.json`: `laof_filter_all_files*`, `laof_filter_selected*`,
  `smart_care_laof_*`, `smartCare_laof_scan_*`, `tile_laof_*`; símbolo
  `OrganizeModuleConfig.smartCareLAOF(scanConfig:watcherConfiguration:)`.
- **E11** — disasm `OrganizeModule.d.s` @0x42738: `Date.timeIntervalSince(_:)` comparado com
  3,1536e7; tipos `LAOFRule`, `OrganizeModule.LAOFTileNodeRepresentation`.

## Divergências conhecidas
- Data de "última abertura": nós usamos o máximo entre `kMDItemLastUsedDate` e `atime`; o
  CleanMyMac usa só o `atime`.

## Dúvidas em aberto
- Fronteiras `<`/`<=` de cada faixa de data.
- Tratamento de itens do iCloud.
- Se o Smart Care usa exatamente a regra de 1 ano.
