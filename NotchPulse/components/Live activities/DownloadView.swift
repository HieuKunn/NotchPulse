import Foundation
import SwiftUI

enum Browser {
    case safari
    case chrome
}

struct DownloadFile {
    var name: String
    var size: Int
    var formattedSize: String
    var browser: Browser
}

class DownloadWatcher: ObservableObject {
    @Published var downloadFiles: [DownloadFile] = []
}

struct DownloadArea: View {
    @EnvironmentObject var watcher: DownloadWatcher

    var body: some View {
        if let file = watcher.downloadFiles.first {
            HStack(alignment: .center) {
                HStack {
                    if file.browser == .safari {
                        AppIcon(for: "com.apple.safari")
                    } else {
                        Image(.chrome).resizable().scaledToFit().frame(width: 30, height: 30)
                    }
                    VStack(alignment: .leading) {
                        Text(loc("Download"))
                        Text(loc("In progress")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 12) {
                    VStack(alignment: .trailing) {
                        Text(file.formattedSize)
                        Text(file.name).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
