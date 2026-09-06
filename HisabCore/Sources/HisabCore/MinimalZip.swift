import Foundation
import Compression

/// Just enough of the ZIP format to read the members of an .xlsx produced by a
/// statement exporter: central-directory walk, stored (0) and deflate (8) entries.
public enum MinimalZip {
    public enum ZipError: Error { case notAZip, corrupt, unsupportedCompression }

    public static func entries(in data: Data) throws -> [String: Data] {
        guard data.count > 22, data.starts(with: [0x50, 0x4B]) else { throw ZipError.notAZip }

        // End-of-central-directory record: scan back for signature 0x06054b50.
        let eocdSig: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        var eocdOffset = -1
        let scanStart = max(0, data.count - 66_000)
        var index = data.count - 22
        while index >= scanStart {
            if data[index] == eocdSig[0], data[index + 1] == eocdSig[1],
               data[index + 2] == eocdSig[2], data[index + 3] == eocdSig[3] {
                eocdOffset = index
                break
            }
            index -= 1
        }
        guard eocdOffset >= 0 else { throw ZipError.corrupt }

        let entryCount = Int(u16(data, eocdOffset + 10))
        var offset = Int(u32(data, eocdOffset + 16))  // central directory start
        var result: [String: Data] = [:]

        for _ in 0..<entryCount {
            guard u32(data, offset) == 0x0201_4B50 else { throw ZipError.corrupt }
            let method = u16(data, offset + 10)
            let compSize = Int(u32(data, offset + 20))
            let uncompSize = Int(u32(data, offset + 24))
            let nameLen = Int(u16(data, offset + 28))
            let extraLen = Int(u16(data, offset + 30))
            let commentLen = Int(u16(data, offset + 32))
            let localOffset = Int(u32(data, offset + 42))
            guard let name = String(data: data.subdata(in: (offset + 46)..<(offset + 46 + nameLen)),
                                    encoding: .utf8) else { throw ZipError.corrupt }

            // Local header carries its own (possibly different) name/extra lengths.
            guard u32(data, localOffset) == 0x0403_4B50 else { throw ZipError.corrupt }
            let localNameLen = Int(u16(data, localOffset + 26))
            let localExtraLen = Int(u16(data, localOffset + 28))
            let dataStart = localOffset + 30 + localNameLen + localExtraLen
            guard dataStart + compSize <= data.count else { throw ZipError.corrupt }
            let compressed = data.subdata(in: dataStart..<(dataStart + compSize))

            switch method {
            case 0:
                result[name] = compressed
            case 8:
                result[name] = try inflate(compressed, expectedSize: uncompSize)
            default:
                throw ZipError.unsupportedCompression
            }
            offset += 46 + nameLen + extraLen + commentLen
        }
        return result
    }

    private static func inflate(_ compressed: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { dst in
            compressed.withUnsafeBytes { src in
                compression_decode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                    src.bindMemory(to: UInt8.self).baseAddress!, compressed.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { throw ZipError.corrupt }
        return output
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }
}
