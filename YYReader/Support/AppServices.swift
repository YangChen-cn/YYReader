import Observation

@MainActor
@Observable
final class AppServices {
    let verificationStore: WebVerificationStore
    let importCoordinator: NovelImportCoordinator
    let folderSync: FolderSyncController

    init() {
        let verificationStore = WebVerificationStore()
        let staticLoader = URLSessionHTMLLoader()
        let webKitLoader = WebKitHTMLLoader()
        webKitLoader.configureVerification(
            presenter: { session, url in
                verificationStore.present(session: session, url: url)
            },
            completion: { session in
                verificationStore.complete(session: session)
            }
        )
        let hybridLoader = HybridHTMLLoader(
            staticLoader: staticLoader,
            webKitLoader: webKitLoader
        )
        self.verificationStore = verificationStore
        self.importCoordinator = NovelImportCoordinator(loader: hybridLoader)
        self.folderSync = FolderSyncController()
    }
}
