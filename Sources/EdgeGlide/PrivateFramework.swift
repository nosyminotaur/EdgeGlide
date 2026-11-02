import Darwin
import Foundation

/// Loads private frameworks at run time with `dlopen` / `dlsym`, so a missing
/// framework or symbol degrades one feature instead of stopping the app.
struct PrivateFramework {
    let name: String
    private let handle: UnsafeMutableRawPointer

    /// Opens `/System/Library/PrivateFrameworks/<name>.framework/<name>`.
    static func open(_ name: String) -> Result<PrivateFramework, PrivateFrameworkError> {
        let path = "/System/Library/PrivateFrameworks/\(name).framework/\(name)"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            let reason = dlerror().map { String(cString: $0) } ?? "unknown dlopen error"
            return .failure(.frameworkMissing(name: name, reason: reason))
        }
        return .success(PrivateFramework(name: name, handle: handle))
    }

    /// Looks up a C function and casts it to `type`. Returns `nil` when the
    /// symbol is absent.
    func symbol<T>(_ symbol: String, as type: T.Type) -> T? {
        guard let pointer = dlsym(handle, symbol) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    /// Like `symbol(_:as:)` but throws a descriptive error when absent.
    func require<T>(_ symbol: String, as type: T.Type) throws -> T {
        guard let fn = self.symbol(symbol, as: type) else {
            throw PrivateFrameworkError.symbolMissing(framework: name, symbol: symbol)
        }
        return fn
    }
}

enum PrivateFrameworkError: LocalizedError {
    case frameworkMissing(name: String, reason: String)
    case symbolMissing(framework: String, symbol: String)

    var errorDescription: String? {
        switch self {
        case .frameworkMissing(let name, let reason):
            "\(name).framework could not be loaded: \(reason)"
        case .symbolMissing(let framework, let symbol):
            "\(framework) has no symbol \(symbol)"
        }
    }
}
