import ARJArchive
import ArgumentParser
import Foundation

struct VerboseListCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "verbose-list",
        abstract: "Detailed archive listing with all information (ARJ: v)",
        discussion: """
        Show detailed information about all files in archive including dates, sizes, compression info.
        
        Usage: arj v <archive> [base_dir] [files/masks...]
        
        Examples:
          arj v archive.arj                    # Show all with details
          arj v archive.arj -x*.bak            # Exclude .bak files from listing
          arj v archive.arj !listfile.txt      # Only show files in listfile
          arj v archive.arj -g<password> | less # Encrypted, pipe to pager
        
        Output columns:
          Filename    Name of file in archive
          Original    Uncompressed size
          Compressed  Compressed size
          Ratio       Compression ratio percentage
          Attr        File attributes
          BPMGS       Bits per method/encryption flags (* = encrypted)
          Date/Time   Modification date/time (UTC)
          CRC32       Checksum value (hex)
          GUA         G = Garbled (encrypted)
        """
    )

    @OptionGroup var options: ArchiveOperationOptions

    func run() throws {
        try options.validateArchiveArgument()
        let archive = try ARJArchive(path: options.archive)
        let entries = try archive.entries()
        let masks = try ARJFilter.resolvedMasks(masks: options.masks, listfiles: options.listfiles)
        let filtered = ARJFilter.filterEntries(entries, masks: masks, excludes: options.excludes, includeDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let header = """
            Filename                                  Original  Compressed   Ratio Attr BPMGS          Date/Time           CRC32 GUA
            ----------------------------------------------------------------------------------------------------------------------------
            """
        print(header)

        for entry in filtered {
            let ratio: String
            if let r = entry.compressionRatio {
                ratio = String(format: "%5.1f%%", (1.0 - r) * 100)
            } else {
                ratio = "   — "
            }
            let nameCol = pad(entry.name, width: 40)
            let dateStr = dateFormatter.string(from: entry.modified)
            let bpmgs = entry.isEncrypted ? "  *   " : "      "
            let gua = entry.isEncrypted ? "G" : " "
            let line = String(
                format: "%@ %10u %10u %7@ %4u %@ %@ %08X %@",
                nameCol,
                entry.originalSize,
                entry.compressedSize,
                ratio,
                entry.fileType,
                bpmgs,
                dateStr,
                entry.crc32,
                gua
            )
            print(line)
        }
    }

    private func pad(_ string: String, width: Int) -> String {
        if string.count >= width {
            return String(string.prefix(width))
        }
        return string + String(repeating: " ", count: width - string.count)
    }
}
