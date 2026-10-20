# CleanYourMac

App macOS open source, feito para estudo, que reimplementa funcionalidades de limpeza de apps como o CleanMyMac com código e arte próprios.

> Projeto independente, sem qualquer vínculo com a MacPaw. "CleanMyMac" é marca da MacPaw Inc.

**Status:** v0.1.0 — módulo **Limpeza** completo:

- **Detritos do sistema:** caches do usuário e do sistema, registros, binários universais, arquivos de idioma, itens de início e preferências defeituosos, versões de documentos, usuários apagados, backups de iPhone/iPad e detritos do Xcode.
- **Acúmulos de IA:** caches, registros, temporários e versões antigas de Claude Code, Claude, Codex, Gemini/Antigravity, Cursor, OpenCode e Chrome DevTools MCP, além de modelos locais do Ollama e do LM Studio.
- **Anexos do Mail** e **Lixos** (Lixo, lixos do iCloud e de discos, Lixo do Mail).

Você analisa, revisa item por item no Gerenciador de Limpeza e escolhe o que apagar. Nada vem marcado sozinho. A comparação com o CleanMyMac está em [`docs/re/parity/report-2026-10-20.md`](docs/re/parity/report-2026-10-20.md).

## Permissões

- **Acesso Total ao Disco** (Ajustes do Sistema → Privacidade e Segurança): sem ele, o macOS esconde dados do Mail, do Safari e de outros apps.
- **Gerenciamento de Apps**: necessário para remover código extra e idiomas de outros apps.
- **Senha de administrador**: pedida uma vez por limpeza, só quando há itens do sistema (e uma vez para medir os caches do sistema, se você quiser).

## Use com cuidado

O CleanYourMac apaga arquivos definitivamente (não vai para o Lixo). Revise antes de limpar. Builds de Debug simulam a limpeza por padrão (`CYM_DRY_RUN=0` desliga); o build Release limpa de verdade.

## Compilar

Requisitos: macOS 14+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open CleanYourMac.xcodeproj
```

Testes do Core: `swift test --package-path Core`
Testes do app: `scripts/test-app.sh`
CLI de diagnóstico (só leitura/simulação): `swift run --package-path Core cym scan` · `cym clean --dry-run`

## Documentação

- Design: `docs/superpowers/specs/`
- Plano: `docs/superpowers/plans/`
- Especificações de comportamento (engenharia reversa clean room): `docs/re/`

## Contribuir

Regras novas começam por uma especificação em `docs/re/specs/` (comportamento descrito com nossas palavras, com evidências) e por testes em fixtures — nunca pelo disco real. Veja `docs/re/README.md`.

## Licença

MIT
