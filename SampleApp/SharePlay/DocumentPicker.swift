import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum DocumentPicker {
    static func pickFile(allowedTypes: [UTType]) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let documentPicker = UIDocumentPickerViewController(
                forOpeningContentTypes: allowedTypes,
                asCopy: false
            )
            
            // Create a delegate coordinator
            let coordinator = Coordinator(continuation: continuation)
            documentPicker.delegate = coordinator
            
            // Present the picker
            guard let rootViewController = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
                .first else {
                continuation.resume(throwing: PickerError.noRootViewController)
                return
            }
            
            // Hold a strong reference to coordinator
            objc_setAssociatedObject(
                documentPicker,
                "coordinator",
                coordinator,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            
            rootViewController.present(documentPicker, animated: true)
        }
    }
    
    private class Coordinator: NSObject, UIDocumentPickerDelegate {
        let continuation: CheckedContinuation<URL, Error>
        
        init(continuation: CheckedContinuation<URL, Error>) {
            self.continuation = continuation
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                continuation.resume(throwing: PickerError.noFileSelected)
                return
            }
            continuation.resume(returning: url)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            continuation.resume(throwing: PickerError.cancelled)
        }
    }
    
    enum PickerError: LocalizedError {
        case noRootViewController
        case noFileSelected
        case cancelled
        
        var errorDescription: String? {
            switch self {
            case .noRootViewController:
                return "Unable to present document picker"
            case .noFileSelected:
                return "No file was selected"
            case .cancelled:
                return "Document picker was cancelled"
            }
        }
    }
}