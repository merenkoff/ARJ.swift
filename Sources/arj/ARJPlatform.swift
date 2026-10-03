#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Terminates the process. Module-qualified so it is not shadowed by members named `exit`.
func terminateProcess(_ code: Int32) -> Never {
    #if canImport(Darwin)
    Darwin.exit(code)
    #elseif canImport(Glibc)
    Glibc.exit(code)
    #else
    Musl.exit(code)
    #endif
}
