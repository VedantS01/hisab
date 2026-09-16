import XCTest
@testable import HisabCore

/// Ground-truth generator for the Flutter port: parses every real statement in
/// the gitignored samples/ directory with the Swift parsers and writes
/// {file: {source, count, hashes[]}} JSON. Gated on GT_OUT so normal runs and
/// CI never touch it. The Dart samples harness asserts byte-equal hash sets.
final class SamplesGroundTruthDump: XCTestCase {
    func testDumpGroundTruth() throws {
        guard let outPath = ProcessInfo.processInfo.environment["GT_OUT"] else {
            throw XCTSkip("GT_OUT not set")
        }
        let samplesDir = ProcessInfo.processInfo.environment["SAMPLES_DIR"]
            ?? "/Users/vedant/personal/hisab/samples"
        let passwords = ["Acct Statement_3293_23062026_13.38.47.pdf": "135244908"]
        let registry = ParserRegistry.live

        var result: [String: [String: Any]] = [:]
        let fm = FileManager.default
        for sub in try fm.contentsOfDirectory(atPath: samplesDir).sorted() {
            var isDir: ObjCBool = false
            let subPath = "\(samplesDir)/\(sub)"
            guard fm.fileExists(atPath: subPath, isDirectory: &isDir), isDir.boolValue else { continue }
            for file in try fm.contentsOfDirectory(atPath: subPath).sorted() {
                let path = "\(subPath)/\(file)"
                guard let data = fm.contents(atPath: path) else { continue }
                guard let parser = registry.detect(data: data, filename: file) else {
                    result["\(sub)/\(file)"] = ["error": "no parser"]
                    continue
                }
                do {
                    let doc = try parser.parse(data: data, password: passwords[file])
                    let hashes = doc.transactions.map { $0.contentHash(source: doc.source) }.sorted()
                    result["\(sub)/\(file)"] = ["source": doc.source.rawValue,
                                                "count": doc.transactions.count,
                                                "hashes": hashes]
                } catch {
                    result["\(sub)/\(file)"] = ["error": "\(error)"]
                }
            }
        }
        let json = try JSONSerialization.data(withJSONObject: result,
                                              options: [.prettyPrinted, .sortedKeys])
        try json.write(to: URL(fileURLWithPath: outPath))
        print("ground truth written: \(outPath)")
    }
}
