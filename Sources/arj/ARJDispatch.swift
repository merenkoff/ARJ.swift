import ArgumentParser
import Foundation

/// Dispatches to concrete `ParsableCommand` types after `ARJArgvPreprocessor` (avoids root-parser edge cases).
enum ARJDispatch {
    static func run(preprocessed argv: [String]) throws {
        guard argv.count >= 2 else {
            throw PreprocessError.missingCommand
        }
        let subcommand = argv[1]
        /// `ArgumentParser` expects arguments **without** the executable path (see `CommandParser.parse`).
        let parseArguments = Array(argv.dropFirst(2))

        if parseArguments == ["--help"] || parseArguments == ["-h"] {
            print(try subcommandHelpText(subcommand), terminator: "")
            return
        }

        switch subcommand {
        case "list":
            var cmd = try ListCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "verbose-list":
            var cmd = try VerboseListCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "test":
            var cmd = try TestCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "extract-flat":
            var cmd = try ExtractFlatCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "extract":
            var cmd = try ExtractCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "print":
            var cmd = try PrintCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "sample":
            var cmd = try SampleCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "search":
            var cmd = try SearchCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "comment":
            var cmd = try CommentCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "add":
            var cmd = try AddCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "delete":
            var cmd = try DeleteCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "update":
            var cmd = try UpdateCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "freshen":
            var cmd = try FreshenCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "move":
            var cmd = try MoveStubCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "garble":
            var cmd = try GarbleStubCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "remove-paths":
            var cmd = try RemovePathsStubCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "rename":
            var cmd = try RenameStubCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "order":
            var cmd = try OrderStubCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "batch":
            var cmd = try BatchStubCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "integrity":
            var cmd = try IntegrityStubCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "join":
            var cmd = try JoinStubCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "backup":
            var cmd = try BackupStubCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "recover":
            var cmd = try RecoverStubCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "copy":
            var cmd = try CopyStubCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "add-chapter":
            var cmd = try AddChapterStubCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "convert-chapter":
            var cmd = try ConvertChapterStubCommand.parseAsRoot(parseArguments)
            try cmd.run()
        case "delete-chapter":
            var cmd = try DeleteChapterStubCommand.parseAsRoot(parseArguments)
            try cmd.run()
        default:
            throw PreprocessError.unknownCommand(subcommand)
        }
    }

    private static func subcommandHelpText(_ subcommand: String) throws -> String {
        switch subcommand {
        case "list":
            return ListCommand.helpMessage(for: ListCommand.self)
        case "verbose-list":
            return VerboseListCommand.helpMessage(for: VerboseListCommand.self)
        case "test":
            return TestCommand.helpMessage(for: TestCommand.self)
        case "extract-flat":
            return ExtractFlatCommand.helpMessage(for: ExtractFlatCommand.self)
        case "extract":
            return ExtractCommand.helpMessage(for: ExtractCommand.self)
        case "print":
            return PrintCommand.helpMessage(for: PrintCommand.self)
        case "sample":
            return SampleCommand.helpMessage(for: SampleCommand.self)
        case "search":
            return SearchCommand.helpMessage(for: SearchCommand.self)
        case "comment":
            return CommentCommand.helpMessage(for: CommentCommand.self)
        case "add":
            return AddCommand.helpMessage(for: AddCommand.self)
        case "delete":
            return DeleteCommand.helpMessage(for: DeleteCommand.self)
        case "update":
            return UpdateCommand.helpMessage(for: UpdateCommand.self)
        case "freshen":
            return FreshenCommand.helpMessage(for: FreshenCommand.self)
        case "move":
            return MoveStubCommand.helpMessage(for: MoveStubCommand.self)
        case "garble":
            return GarbleStubCommand.helpMessage(for: GarbleStubCommand.self)
        case "remove-paths":
            return RemovePathsStubCommand.helpMessage(for: RemovePathsStubCommand.self)
        case "rename":
            return RenameStubCommand.helpMessage(for: RenameStubCommand.self)
        case "order":
            return OrderStubCommand.helpMessage(for: OrderStubCommand.self)
        case "batch":
            return BatchStubCommand.helpMessage(for: BatchStubCommand.self)
        case "integrity":
            return IntegrityStubCommand.helpMessage(for: IntegrityStubCommand.self)
        case "join":
            return JoinStubCommand.helpMessage(for: JoinStubCommand.self)
        case "backup":
            return BackupStubCommand.helpMessage(for: BackupStubCommand.self)
        case "recover":
            return RecoverStubCommand.helpMessage(for: RecoverStubCommand.self)
        case "copy":
            return CopyStubCommand.helpMessage(for: CopyStubCommand.self)
        case "add-chapter":
            return AddChapterStubCommand.helpMessage(for: AddChapterStubCommand.self)
        case "convert-chapter":
            return ConvertChapterStubCommand.helpMessage(for: ConvertChapterStubCommand.self)
        case "delete-chapter":
            return DeleteChapterStubCommand.helpMessage(for: DeleteChapterStubCommand.self)
        default:
            throw PreprocessError.unknownCommand(subcommand)
        }
    }
}
