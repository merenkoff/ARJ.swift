import ARJArchive
import Darwin
import Foundation

enum ARJProgram {
    static func main() {
        _ = signal(SIGINT) { _ in
            _ = write(STDERR_FILENO, "\n", 1)
            _ = fflush(stderr)
            exit(Int32(ARJExitCode.userCtrlC.rawValue))
        }

        let raw = CommandLine.arguments
        if raw.count >= 2 {
            let first = raw[1]
            if first == "--help" || first == "-h" {
                printARJHelp(executable: raw[0])
                exit(Int32(ARJExitCode.success.rawValue))
            }
        }

        do {
            let argv = try ARJArgvPreprocessor.preprocess(raw)
            try ARJDispatch.run(preprocessed: argv)
            exit(Int32(ARJExitCode.success.rawValue))
        } catch let error as ARJCLIError {
            error.exitProcess()
        } catch let error as ARJError {
            let code = ARJErrorMapper.exitCode(for: error)
            code.exit(message: ARJErrorMapper.message(for: error))
        } catch let error as PreprocessError {
            ARJExitCode.userParameterError.exit(message: error.description)
        } catch {
            let text = error.localizedDescription
            FileHandle.standardError.write(Data("arj: \(text)\n".utf8))
            exit(Int32(ARJExitCode.userParameterError.rawValue))
        }
    }
}

private func printARJHelp(executable: String) {
    let name = URL(fileURLWithPath: executable).lastPathComponent
    print(
        """
        \(name) — ARJ-style CLI for ARJ.swift (read commands; write = stubs)

        Usage: \(name) <command> [-switches] <archive[.arj]> [base_dir] [files...]

        Read commands:  l list   v verbose   t test   e extract (flat)   x extract (paths)
                        p print  s sample    w search  c comment (show)

        Write (stubs):  a d u f m g r n o b i j k q y  ac cc dc

        Use \(name) <command> --help for per-command options (long flags after preprocessing).

        Exit codes 0…12 match classic ARJ errorlevels where applicable.
        """
    )
}

ARJProgram.main()
