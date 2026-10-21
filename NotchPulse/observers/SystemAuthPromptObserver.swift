import Foundation

@MainActor
final class SystemAuthPromptObserver: ObservableObject {
    static let shared = SystemAuthPromptObserver()
    
    private init() {}
    
    func cleanup() {}
}
