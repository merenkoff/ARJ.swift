import Darwin
import Foundation

enum ARJGlob {
    /// Path-style glob using `fnmatch` (supports `*`, `?`; case-sensitive on macOS).
    static func matches(_ path: String, pattern: String) -> Bool {
        if pattern == "*" { return true }
        return pattern.withCString { p in
            path.withCString { s in
                fnmatch(p, s, 0) == 0
            }
        }
    }
}
