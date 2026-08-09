import Observation

@MainActor
@Observable
final class AppServices {
    let verificationStore: WebVerificationStore
    let importCoordinator: NovelImportCoordinator

    init() {
        let verificationStore = WebVerificationStore()
        let staticLoader = URLSessionHTMLLoader()
        let hybridLoader = HybridHTMLLoader(
            staticLoader: staticLoader,
            verificationStore: verificationStore
        )
        self.verificationStore = verificationStore
        self.importCoordinator = NovelImportCoordinator(loader: hybridLoader)
    }
}
