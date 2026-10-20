# Engenharia reversa (clean room)

Objetivo: descrever **o comportamento** do módulo Limpeza do CleanMyMac 5.7.2
para que o CleanYourMac se comporte igual, sem copiar código, textos ou arte.

## Fluxo

1. **Evidência.** Observação (`scripts/re/capture-scan.sh`, a UI do CleanMyMac),
   inspeção estática (`scripts/re/extract-strings.sh`) e REA + Ghidra para as
   regras que só aparecem no código.
2. **Especificação.** Uma por grupo em `docs/re/specs/<grupo>.md`, escrita com
   nossas palavras a partir do `_TEMPLATE.md`. Cada regra cita a evidência que a
   sustenta (E1, E2…).
3. **Código.** Escrito só a partir das especificações, nunca a partir de
   pseudocódigo.

## O que entra e o que não entra no repositório

| Entra | Não entra |
|---|---|
| Especificações com nossas palavras | Pseudocódigo, assembly, saída do REA/Ghidra |
| Caminhos e critérios técnicos (são fatos) | Textos, ícones, imagens e animações do CleanMyMac |
| Baselines de tamanho/itens da análise | Arquivos ou tabelas de dados extraídos dele |

Tudo o que é bruto fica em `re-notes/`, que está no `.gitignore`.

## Regra de ouro

Só rodamos a **análise** do CleanMyMac. Nunca clicamos em Limpar nele.

## Ferramentas

- Ghidra 12.1.4 (`brew install ghidra`), JDK 21 (`brew install openjdk@21`)
- REA 6.7.0: `claude mcp add --scope local rea -e GHIDRA_INSTALL_DIR=/opt/homebrew/opt/ghidra/libexec -e JAVA_HOME=/opt/homebrew/opt/openjdk@21 -- npx -y rea-agents@6.7.0 mcp`
  (verificação: `rea doctor --provider ghidra --json` → `healthy: true`)
- CLI do REA sem MCP: `GHIDRA_INSTALL_DIR=… JAVA_HOME=… npx -y rea-agents@6.7.0 <comando>`

## Scripts

- `scripts/re/extract-strings.sh <Framework>` → `re-notes/static/<Framework>/`
  (`strings.txt`, `symbols.txt` e `localizable-<lang>.json` quando o framework
  tem textos).
- `sudo scripts/re/capture-scan.sh <rótulo> [segundos]` → `re-notes/fs/`.
  Abra o CleanMyMac antes de rodar e clique em Analisar quando o script pedir.
