import Foundation

nonisolated enum EchoLog {
    enum Category: String {
        case lifecycle
        case restore
        case persistence
        case browserCapture
        case performance
        case sessionDetail
    }

    static func lifecycle(_ message: String, error: Error? = nil) {
        log(.lifecycle, message, error: error)
    }

    static func restore(_ message: String, error: Error? = nil) {
        log(.restore, message, error: error)
    }

    static func persistence(_ message: String, error: Error? = nil) {
        log(.persistence, message, error: error)
    }

    static func browserCapture(_ message: String, error: Error? = nil) {
        log(.browserCapture, message, error: error)
    }

    static func performance(_ message: String, error: Error? = nil) {
        log(.performance, message, error: error)
    }

    static func sessionDetail(_ message: String, error: Error? = nil) {
        log(.sessionDetail, message, error: error)
    }

    private static func log(_ category: Category, _ message: String, error: Error?) {
        if let error {
            print("[\(category.rawValue)] \(message): \(error.localizedDescription)")
        } else {
            print("[\(category.rawValue)] \(message)")
        }
    }
}
