import UIKit

enum ShareThumbnailProvider {
    static func pngData() -> Data? {
        UIImage(named: "ShareThumbnail")?.pngData()
    }
}
