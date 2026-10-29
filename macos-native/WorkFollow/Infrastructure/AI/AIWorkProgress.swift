import Foundation

struct AITextUpdate: Decodable, Equatable, Sendable {
    let kind: String
    var text: String? = nil
    var message: String? = nil
}
