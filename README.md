# CleanYourMac

App macOS open source, feito para estudo, que reimplementa funcionalidades de limpeza de apps como o CleanMyMac com código e arte próprios.

> Projeto independente, sem qualquer vínculo com a MacPaw. "CleanMyMac" é marca da MacPaw Inc.

**Status:** em desenvolvimento. A v1 terá o módulo **Limpeza** (Detritos do Sistema, Acúmulos de IA, Anexos do Mail, Lixos).

## Compilar

Requisitos: macOS 14+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open CleanYourMac.xcodeproj
```

Testes do Core: `swift test --package-path Core`
Testes do app: `xcodebuild -scheme CleanYourMac -destination 'platform=macOS' test`

## Documentação

- Design: `docs/superpowers/specs/`
- Plano: `docs/superpowers/plans/`
- Especificações de comportamento (engenharia reversa clean room): `docs/re/`

## Licença

MIT
