import Foundation

enum PreprocessError: Error, Equatable, CustomStringConvertible {
    case missingCommand
    case unknownCommand(String)
    case badSwitch(String)

    var description: String {
        switch self {
        case .missingCommand:
            return "missing command (expected: arj <cmd> ...)"
        case let .unknownCommand(cmd):
            return "unknown command: \(cmd)"
        case let .badSwitch(s):
            return "invalid switch: \(s)"
        }
    }
}

/// Converts classic `arj <cmd> ...` argv into long-form arguments for `ArgumentParser`.
enum ARJArgvPreprocessor {
    private static let commandMap: [String: String] = [
        "l": "list",
        "v": "verbose-list",
        "t": "test",
        "e": "extract-flat",
        "x": "extract",
        "p": "print",
        "s": "sample",
        "w": "search",
        "c": "comment",
        "a": "add",
        "d": "delete",
        "u": "update",
        "f": "freshen",
        "m": "move",
        "g": "garble",
        "r": "remove-paths",
        "n": "rename",
        "o": "order",
        "b": "batch",
        "i": "integrity",
        "j": "join",
        "k": "backup",
        "q": "recover",
        "y": "copy",
        "ac": "add-chapter",
        "cc": "convert-chapter",
        "dc": "delete-chapter",
    ]

    static func preprocess(_ argv: [String]) throws -> [String] {
        guard argv.count >= 2 else {
            throw PreprocessError.missingCommand
        }

        let program = argv[0]
        var rest = Array(argv.dropFirst())

        let cmdToken = rest.removeFirst()
        guard let subcommand = mapCommand(cmdToken) else {
            throw PreprocessError.unknownCommand(cmdToken)
        }

        var output: [String] = [program, subcommand]
        var positionals: [String] = []
        var listfileChar: Character = "!"

        for arg in rest {
            if arg.hasPrefix("--") {
                output.append(arg)
                continue
            }

            if arg.hasPrefix("-!") {
                guard arg.count >= 3 else {
                    throw PreprocessError.badSwitch(arg)
                }
                let idx = arg.index(arg.startIndex, offsetBy: 2)
                listfileChar = arg[idx]
                continue
            }

            if arg.hasPrefix("-"), arg != "-" {
                let expanded = try expandSwitch(arg)
                output.append(contentsOf: expanded)
                continue
            }

            if let first = arg.first, first == listfileChar {
                let path = String(arg.dropFirst())
                guard !path.isEmpty else {
                    throw PreprocessError.badSwitch(arg)
                }
                output.append(contentsOf: ["--listfile", path])
                continue
            }

            positionals.append(arg)
        }

        try appendPositionals(subcommand: subcommand, positionals: positionals, into: &output)
        return output
    }

    private static func mapCommand(_ token: String) -> String? {
        let lower = token.lowercased()
        if lower.count == 2 {
            return commandMap[lower]
        }
        if lower.count == 1 {
            return commandMap[lower]
        }
        return nil
    }

    private static func appendPositionals(
        subcommand: String,
        positionals: [String],
        into output: inout [String]
    ) throws {
        guard !positionals.isEmpty else { return }

        if subcommand == "search" {
            let archive = positionals[0]
            output.append(contentsOf: ["--archive", archive])
            if positionals.count > 1 {
                let pattern = positionals.dropFirst().joined(separator: " ")
                output.append(contentsOf: ["--search-pattern", pattern])
            }
            return
        }

        var pos = positionals
        output.append(contentsOf: ["--archive", pos.removeFirst()])
        if !pos.isEmpty {
            output.append(contentsOf: ["--base-dir", pos.removeFirst()])
        }
        for mask in pos {
            output.append(contentsOf: ["--mask", mask])
        }
    }

    private static func expandSwitch(_ token: String) throws -> [String] {
        var t = token

        if (t.hasSuffix("+") || t.hasSuffix("-")), t.count > 2, t.hasPrefix("-") {
            let last = t.last!
            if last == "+" || last == "-" {
                t.removeLast()
            }
        }

        switch true {
        case t == "-y" || t == "-Y":
            return ["--yes"]
        case t == "-i":
            return ["--no-progress"]
        case t == "-o":
            return ["--overwrite-prompt"]
        case t == "-r":
            return ["--recursive"]
        case t == "-jt":
            return ["--crc-test"]
        case t == "-_":
            return ["--lowercase-names"]
        case t == "-e":
            return ["--strip-paths"]
        case t == "-p":
            return ["--keep-paths"]
        case t == "-p1":
            return ["--keep-relative-paths"]
        case t.hasPrefix("-ht"):
            let path = String(t.dropFirst(3))
            guard !path.isEmpty else { throw PreprocessError.badSwitch(token) }
            return ["--target-dir", path]
        case t.hasPrefix("-g"):
            return ["--password", String(t.dropFirst(2))]
        case t.hasPrefix("-w") || t.hasPrefix("-z"):
            let path = String(t.dropFirst(2))
            guard !path.isEmpty else { throw PreprocessError.badSwitch(token) }
            let flag = t.hasPrefix("-w") ? "--work-dir" : "--comment-file"
            return [flag, path]
        case _ where t.hasPrefix("-m") && t.count == 3 && (t.last?.isNumber == true):
            return ["--compression-method", String(t.last!)]
        case t.hasPrefix("-x") && t.count > 2:
            return ["--exclude", String(t.dropFirst(2))]
        case t == "-u" || t == "-f" || t == "-n":
            return []
        case t.hasPrefix("-hb"):
            return []
        case t.hasPrefix("-j"):
            return []
        case t == "-b1" || t == "-b2":
            return []
        case t.hasPrefix("-v"):
            return []
        case t == "-je" || t.hasPrefix("-je"):
            return []
        case t == "-hk" || t == "-he" || t == "-2" || t == "-&":
            return []
        default:
            return []
        }
    }
}
