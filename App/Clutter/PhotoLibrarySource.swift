import AppKit
import Photos
import CleanYourMacCore

/// Fototeca pelo PhotoKit público (docs/re/specs/clutter/similar-images.md §1): fotos como candidatas de Similares, com
/// miniatura local de 256 px (sem rede: foto só no iCloud fica de fora), e remoção para Apagados Recentemente.
/// O tamanho de cada foto não tem API pública barata; fica 0 ("—" na tela).
final class PhotoLibrarySource: PhotoRemoving, @unchecked Sendable {
    /// Pede a permissão uma vez (na análise da pasta pessoal) e lista as fotos.
    func candidates() -> [SimilarCandidate] {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            let done = DispatchSemaphore(value: 0)
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status = $0; done.signal() }
            done.wait()
        }
        guard status == .authorized || status == .limited else { return [] }
        let options = PHFetchOptions()
        options.includeAllBurstAssets = true
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        var out: [SimilarCandidate] = []
        out.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            let id = asset.localIdentifier
            out.append(SimilarCandidate(id: id, url: nil, date: asset.creationDate, size: 0) { Self.thumbnail(id) })
        }
        return out
    }

    static func thumbnail(_ id: String) -> CGImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        var result: CGImage?
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 256, height: 256), contentMode: .aspectFit,
                                              options: options) { image, _ in
            result = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        return result
    }

    func remove(_ ids: [String]) async -> Result<Void, CleanFailure> {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard assets.count > 0 else { return .failure(CleanFailure(reason: "item changed")) }
        do {
            // O macOS pede a confirmação; as fotos vão para Apagados Recentemente.
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(assets) }
            return .success(())
        } catch {
            return .failure(CleanFailure(reason: error.localizedDescription))
        }
    }
}
