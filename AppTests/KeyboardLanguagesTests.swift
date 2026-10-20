import Testing
import CleanYourMacCore

/// A análise roda fora da thread principal; ler os teclados ali derrubava o app (HIToolbox exige a main queue).
@Test func keyboardLanguagesFromBackgroundDoesNotCrash() async {
    let langs = await Task.detached { LanguageFilesScanner.enabledKeyboardLanguages() }.value
    #expect(!langs.isEmpty)
}
