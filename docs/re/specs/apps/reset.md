# Redefinir um app (`appUninstall`, modo redefinir)

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83), 2026-10-21. **Só análise
estática e observação**: nunca selecionamos nem removemos nada no CleanMyMac. O
`dump-ax` recusa esses cliques, e o checkbox das linhas não tem título, então nem
a seleção pôde ser feita.

## Visão geral

### No CleanMyMac
- **Não há uma ação "Redefinir" separada.** Nenhum texto do módulo Aplicativos (nem
  de outro framework) tem a ideia de redefinir como botão ou menu [E1]. O único
  texto sobre isso é a ajuda do app de sistema protegido: o bundle não pode ser
  removido, mas os arquivos relacionados podem, e isso redefine o app [E2].
- Na prática, redefinir no CleanMyMac = **abrir os itens incluídos do app,
  deixar o item "Binários" desmarcado e remover o resto**. O bundle é só mais um
  recurso da lista (tipo "bundle do app"), com um checkbox próprio [E3].
- Para apps **protegidos** (bundle com `Info.plist` restrito pelo SIP, ou bundle
  ID protegido pela base cifrada), o recurso "Binários" é criado como **não
  removível**. Ao marcar o app, só os arquivos podem ser removidos, então a
  única coisa possível é redefinir [E3][E4].
- Apps da App Store que a Apple não deixa apagar falham no passo do bundle com
  um erro próprio, e os arquivos seguem a regra normal (ver `removal.md`) [E5].
- O próprio CleanMyMac tem um fluxo de autodesinstalação. A linha dele não
  mostra itens incluídos (`inventory.md`), então não há como redefini-lo por ali
  [E6].

### No CleanYourMac (design)
- **Redefinir** é uma ação explícita, ao lado de Desinstalar, para **qualquer
  app** da lista. Remove arquivos relacionados e **mantém o bundle**.
- Para app protegido, é a **única** ação (Desinstalar fica indisponível).
- Destino: **Lixo** (como Desinstalar). Ordem e travas: `removal.md`
  ("Redefinir").

## Locais varridos
Os mesmos de `related-files.md`. Redefinir não procura nada a mais: usa a mesma
lista de `RelatedFile` do app e muda só a marcação e o que pode ser selecionado.

## Inclusão (o que redefinir pode remover)
Todos os tipos de `related-files.md`, **menos**:
- `binaries` (o bundle principal e as cópias): nunca, por definição;
- `other` com recibo de pacote: nunca (o app continua instalado, e o recibo
  descreve a instalação dele; esquecer o recibo agora deixaria o `pkgutil`
  errado);
- `applications` (apps internos de jogos): nunca;
- `installers`: nunca (o instalador não é estado do app; vai pela seção de
  instaladores).

Ficam disponíveis, então: `supportingFiles`, `preferences`, `logs`,
`container`, `userData`, `loginItems`, `plugins`, `help`.

## Exclusão
- O próprio CleanYourMac: redefinir fica **bloqueado** (ele está sempre aberto
  enquanto roda; ver `removal.md`).
- App aberto: nada é movido enquanto ele roda. O usuário fecha o app (ou
  confirma forçar o encerramento); a opção de seguir sem fechar existe para
  redefinir, com aviso de que o app pode recriar os arquivos (`removal.md`).
- Para apps da Apple (`com.apple.*`), além das travas de `related-files.md`:
  **nada fora da pasta do usuário** fica selecionável, nem com o helper. Ex.:
  `/Library/Application Support/GarageBand` (952 MB, biblioteca de sons que o
  sistema e outros apps de áudio da Apple podem usar) e
  `/Library/Preferences/com.apple.dt.Xcode.plist`. Esses itens aparecem, mas
  sem checkbox, com uma dica.

## Recomendado (o que vem marcado)
- CleanMyMac: não observado (ver "Versão de referência"). Pelo código, marcar o
  app marca os recursos removíveis, e o bundle protegido não entra [E3].
- **Regra nossa** (ao escolher Redefinir):

| Tipo | Marcado ao redefinir | Por quê |
|---|---|---|
| `preferences` | sim | é o "estado de fábrica" do app |
| `supportingFiles` (suporte, caches, temporários) | sim, só os de `~` | idem; os de `/Library` vêm desmarcados |
| `logs` | sim | sem risco |
| `plugins`, `help` | não | o app continua instalado e pode depender deles |
| `loginItems` (item de sessão, launchd) | não | mudaria o comportamento do app instalado; `removal.md` só trata launchd marcado |
| `container` | **não** | guarda os dados do usuário (ver abaixo); exige a confirmação extra |
| `userData` | **não** | idem |

Itens em `/Library` (fora de `~`) vêm desmarcados ao redefinir, mesmo com o
helper aprovado. O usuário pode marcá-los (exceto nos apps da Apple, ver
"Exclusão").

Isto diverge do design ("a marcação segue a do CleanMyMac"): não foi possível
ver a marcação dele, e marcar contêineres por padrão apagaria, nesta máquina,
114 MB de conversas do WhatsApp ou 965 MB de máquinas virtuais do UTM numa
redefinição [E7]. Segurança antes de paridade.

## Confirmação extra (Dados do Usuário e Contêiner)
- Aparece quando, ao confirmar Redefinir, **algum item marcado** é do tipo
  `container` ou `userData`. Implementado em
  `UninstallerScanner.needsResetConfirmation(items:)` (verdadeiro se houver
  `kind == .container || kind == .userData` entre os marcados).
- Conteúdo (texto nosso): o nome do app, a lista dos itens desses dois tipos com
  caminho e tamanho, e o aviso de que ali ficam os dados criados pelo usuário no
  app (exemplos genéricos: mensagens, bibliotecas, projetos, máquinas virtuais),
  e de que eles vão para o Lixo e podem ser recuperados de lá até o Lixo ser
  esvaziado.
- Botões: cancelar (padrão, com Esc) e confirmar. Sem "não perguntar de novo".
- Desinstalar **não** mostra esta confirmação extra: lá, a confirmação geral de
  remoção já lista tudo, e o app vai embora junto.
- Os outros tipos não disparam a confirmação.

## Apps da Apple protegidos
- O que é protegido: `inventory.md` ("Protegido"): `Info.plist` com
  `SF_RESTRICTED`, caminho real em `/System`, ou bundle ID na nossa lista fixa de
  apps que o macOS reinstala (ex.: `com.apple.Safari`).
- Na v0.2, os apps de `/System/Applications` e os links do Cryptex (Safari) não
  entram na lista (`inventory.md`), então a redefinição de app protegido só
  acontece com um app protegido que esteja fora de `/System` (raro).
- Para eles: Desinstalar fica desabilitado; Redefinir disponível; nada fora de
  `~` é selecionável; contêiner e dados do usuário seguem a tabela acima e a
  confirmação extra.
- **Nunca** removemos o bundle, nem pelo helper, nem se o usuário marcar o item
  "Binários" (o item nem tem checkbox).
- GarageBand e Xcode (Apple, App Store, sem SIP) **não** são protegidos: podem
  ser desinstalados ou redefinidos.

## Agrupamento e nome exibido
Igual a `related-files.md`. O grupo Binários aparece no modo redefinir só como
referência, sem checkbox.

## Cálculo de tamanho
O total mostrado é a soma dos itens **marcados** (o bundle nunca entra). Regras
de `related-files.md`.

## Remoção
`removal.md`, seção "Redefinir": arquivos → Lixo; preferências com
`removePreference`; plists do launchd só se marcados (`unloadAndTrash`); item de
sessão só se marcado. Falha em um item não impede os outros (não há bundle para
proteger), e cada falha vai para o registro.

## Alertas e selos
- Confirmação geral da remoção (total e destino Lixo).
- Confirmação extra de Dados do Usuário/Contêiner.
- Dica nos itens sem checkbox (fora de `~` em app da Apple; bundle).
- Aviso, se o usuário seguir com o app aberto, de que ele pode recriar arquivos.

## requiresAdmin
- Análise: não.
- Limpeza: só para itens fora de `~` que o usuário marcar (nunca para apps da
  Apple).

## Evidências
- **E1**: busca de `reset`/`redefin` nos `localizable-*.json` de todos os
  frameworks em `re-notes/static/` (nenhuma ação de redefinir; a única menção é
  a da ajuda do app protegido).
- **E2**: chave `protected_system_application_info` (ApplicationsModule).
- **E3**: `CMResourcesFetcher fetchAllResourcesForApplication:addAppBundleToResourceList:`
  (bundle como recurso do tipo 4 com `removable` = não restrito e não protegido
  pela base) e `CMApplicationResource isRemovable`, decompilados.
- **E4**: `CMApplicationInfo isRestricted` (`isFileRestricted:` no
  `Info.plist`) e `isAppProtectedWithBundleId:` da base.
- **E5**: `ExcludedBundleRemover` e a chave
  `error_description_bundle_exclusion_app_cannot_be_removed_format`.
- **E6**: `ApplicationBundleSelfRemover`, chaves `uninstalling_cmm_*`, e a linha
  do CleanMyMac sem itens na baseline.
- **E7**: tamanhos desta máquina: `du -sk ~/Library/Containers/net.whatsapp.WhatsApp`
  (≈ 116 MB) e `~/Library/Containers/com.utmapp.UTM` (≈ 965 MB);
  `/Library/Application Support/GarageBand` (≈ 952 MB).

## Divergências conhecidas
- **Ação própria** de redefinir (o CleanMyMac faz isso desmarcando o bundle).
- **Marcação**: contêiner, dados do usuário, itens de início, plug-ins, ajuda e
  tudo fora de `~` vêm desmarcados ao redefinir. É provável que o CleanMyMac
  marque tudo o que é removível.
- **Apps da Apple**: nada fora de `~` é selecionável ao redefinir.
- **Recibos e instaladores**: fora da redefinição.
- **Confirmação extra** para contêiner e dados do usuário: não existe no
  CleanMyMac.
- **Lixo** em vez de apagar de vez (`removal.md`).

## Checklist de testes
1. App de teste com preferência, cache, contêiner e registro → Redefinir marca
   preferência, cache e registro; o contêiner vem desmarcado; o bundle fica.
2. Marcar o contêiner → `needsResetConfirmation` verdadeiro; cancelar → nada
   movido; confirmar → contêiner no Lixo falso dos testes, bundle intacto.
3. Só preferências marcadas → sem confirmação extra.
4. App protegido (`Info.plist` com `SF_RESTRICTED`, simulado) → Desinstalar
   indisponível; Redefinir disponível; o item Binários sem checkbox.
5. App `com.apple.*` com item em `/Library/Application Support/<Nome>` → item
   visível, sem checkbox, mesmo com o helper aprovado.
6. Item em `/Library` de app de terceiros → desmarcado ao redefinir;
   selecionável se o helper estiver aprovado.
7. Recibo de pacote do app → não aparece no modo redefinir.
8. App aberto → diálogo de fechar; seguir sem fechar → aviso e remoção.
9. Redefinir o CleanYourMac → bloqueado.
10. Plist do launchd marcado → `unloadAndTrash`; desmarcado → intocado.
11. Falha ao mover um item → os outros seguem; o registro tem a falha.
