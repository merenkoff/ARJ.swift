import ARJArchive
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
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
        \(name) — ARJ-style CLI for ARJ.swift (read and write support)

        Usage: \(name) <command> [-switches] <archive[.arj]> [base_dir] [files...]

        Read commands:  l list      List files in archive
                        v verbose   Verbose list with full details
                        t test      Test integrity
                        e extract   Extract files (flat, no directories)
                        x extract   Extract files (preserving paths)
                        p print     Print file contents to stdout
                        s sample    Show sample/first file
                        w search    Search for text pattern
                        c comment   Show archive comment (or set with -z<file>)

        Write commands: a add      Add files (creates the archive if needed)
                        u update   Add new files, replace older entries
                        f freshen  Replace older entries only
                        m move     Add files, then delete the originals
                        d delete   Delete entries by masks
                        r paths    Remove paths from entry names
                        c -z<file> Set archive comment

        Not implemented (exit 2): g n o b i j k q y  ac cc dc

        Common switches:
          -g<pass>          Password (read encrypted entries / garble added files)
          -ht<dir>          Target directory for extraction (-e/-x)
          -w<dir>           Work directory
          -y                Assume yes (don't prompt)
          -x<mask>          Exclude files matching mask (glob: *.bin, file?.dat)
          !<file>           Read file/mask list from file (one per line)
          -p                Keep full paths when extracting
          -p1               Keep relative paths
          -e                Strip all paths (extract to target dir only)
          -r                Recurse into subdirectories
          -_                Convert names to lowercase
          -o                Prompt before overwriting
          -i                No progress indicator
          -m0..4            Compression method for write commands (default -m1)
          -jt               CRC test mode
          -z<file>          Comment file (for write commands)

        Use \(name) <command> --help for per-command options (long flags after preprocessing).

        Exit codes:
          0    Success
          1    Warning (e.g. nothing matched)
          2    Fatal error / not implemented
          3    Password error / encryption issues
          6    File not found
          7    File I/O error
          9    Not an ARJ archive
          11   User aborted
          Others see classic ARJ errorlevels

        Examples:
          \(name) l archive.arj                    # List all files
          \(name) l archive.arj -x*.bin           # List except .bin files
          \(name) l archive.arj !listfile.txt     # List only files in listfile.txt
          \(name) x archive.arj -ht/tmp -y        # Extract to /tmp without prompts
          \(name) x archive.arj -x*.bak -x*.tmp   # Extract excluding .bak and .tmp
          \(name) t archive.arj -gsecret          # Test with password
          \(name) v archive.arj | less            # Verbose list (pipe to pager)
          \(name) a backup.arj docs *.txt -r     # Create/extend an archive (method 1)
          \(name) a backup.arj . -m4 -gsecret    # Fastest method, garbled with a password
        """
    )
}

ARJProgram.main()
