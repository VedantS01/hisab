import Foundation

/// Just enough of legacy Excel (CDF/OLE2 container + BIFF8 workbook) to read a bank
/// statement export: FAT and mini-FAT sector chains, the SST string table (including
/// CONTINUE-record splits), LABELSST string cells and NUMBER cells.
public enum MinimalXLS {
    public enum XLSError: Error { case notCDF, corrupt }

    /// Sparse grid: [row: [column: text]]. NUMBER cells are rendered with two
    /// decimals — statement amounts — matching what the text parsers see.
    public static func cells(in data: Data) throws -> [Int: [Int: String]] {
        let workbook = try workbookStream(in: data)
        var strings: [String] = []
        var grid: [Int: [Int: String]] = [:]

        // Records, kept separate so SST/CONTINUE boundaries are known.
        var records: [(id: UInt16, payload: Data)] = []
        var pos = workbook.startIndex
        while pos + 4 <= workbook.endIndex {
            let id = UInt16(workbook[pos]) | (UInt16(workbook[pos + 1]) << 8)
            let length = Int(workbook[pos + 2]) | (Int(workbook[pos + 3]) << 8)
            guard pos + 4 + length <= workbook.endIndex else { break }
            records.append((id, workbook.subdata(in: (pos + 4)..<(pos + 4 + length))))
            pos += 4 + length
        }

        for (index, record) in records.enumerated() {
            switch record.id {
            case 0x00FC:  // SST, possibly spanning CONTINUE records
                var segments = [record.payload]
                var next = index + 1
                while next < records.count, records[next].id == 0x003C {
                    segments.append(records[next].payload)
                    next += 1
                }
                strings = try parseSST(segments: segments)
            case 0x00FD:  // LABELSST: row, col, xf, isst
                let p = record.payload
                guard p.count >= 10 else { continue }
                let row = Int(u16(p, 0)), col = Int(u16(p, 2))
                let isst = Int(u32(p, 6))
                if strings.indices.contains(isst) {
                    grid[row, default: [:]][col] = strings[isst]
                }
            case 0x0203:  // NUMBER: row, col, xf, IEEE 754 double
                let p = record.payload
                guard p.count >= 14 else { continue }
                let row = Int(u16(p, 0)), col = Int(u16(p, 2))
                var bits: UInt64 = 0
                for i in 0..<8 { bits |= UInt64(p[p.startIndex + 6 + i]) << (8 * i) }
                let value = Double(bitPattern: bits)
                grid[row, default: [:]][col] = String(format: "%.2f", value)
            default:
                break
            }
        }
        return grid
    }

    // MARK: SST with CONTINUE handling

    private struct Cursor {
        let segments: [Data]
        var segment = 0
        var offset = 0

        var atSegmentStart: Bool { offset == 0 && segment > 0 }

        mutating func byte() throws -> UInt8 {
            while segment < segments.count, offset >= segments[segment].count {
                segment += 1; offset = 0
            }
            guard segment < segments.count else { throw XLSError.corrupt }
            let d = segments[segment]
            let b = d[d.startIndex + offset]
            offset += 1
            return b
        }

        mutating func skip(_ n: Int) throws { for _ in 0..<n { _ = try byte() } }
        mutating func u16() throws -> Int { let a = try byte(); let b = try byte(); return Int(a) | Int(b) << 8 }
        mutating func u32() throws -> Int {
            let a = try u16(); let b = try u16(); return a | b << 16
        }

        /// Remaining bytes in the current segment (0 = at a CONTINUE boundary).
        var remainingInSegment: Int {
            segment < segments.count ? segments[segment].count - offset : 0
        }
    }

    private static func parseSST(segments: [Data]) throws -> [String] {
        var cursor = Cursor(segments: segments)
        _ = try cursor.u32()                 // total refs
        let unique = try cursor.u32()
        var strings: [String] = []
        strings.reserveCapacity(unique)

        for _ in 0..<unique {
            let length = try cursor.u16()
            var flags = try cursor.byte()
            var richRuns = 0
            var extBytes = 0
            if flags & 0x08 != 0 { richRuns = try cursor.u16() }
            if flags & 0x04 != 0 { extBytes = try cursor.u32() }

            var scalars: [UInt16] = []
            scalars.reserveCapacity(length)
            var remaining = length
            while remaining > 0 {
                if cursor.remainingInSegment == 0 {
                    // A string continuing into a CONTINUE record re-declares its encoding.
                    flags = try cursor.byte()
                }
                if flags & 0x01 != 0 {
                    let lo = try cursor.byte(); let hi = try cursor.byte()
                    scalars.append(UInt16(lo) | UInt16(hi) << 8)
                } else {
                    scalars.append(UInt16(try cursor.byte()))
                }
                remaining -= 1
            }
            try cursor.skip(richRuns * 4)
            try cursor.skip(extBytes)
            strings.append(String(utf16CodeUnits: scalars, count: scalars.count))
        }
        return strings
    }

    // MARK: CDF container

    static func workbookStream(in data: Data) throws -> Data {
        guard data.count > 512,
              data.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) else {
            throw XLSError.notCDF
        }
        let sectorSize = 1 << Int(u16(data, 30))
        let miniSectorSize = 1 << Int(u16(data, 32))
        let dirStart = i32(data, 48)
        let miniCutoff = Int(u32(data, 56))
        let miniFATStart = i32(data, 60)
        let difatStart = i32(data, 68)
        let difatCount = Int(u32(data, 72))

        func sector(_ index: Int) throws -> Data {
            let start = 512 + index * sectorSize
            guard start + sectorSize <= data.count else { throw XLSError.corrupt }
            return data.subdata(in: start..<(start + sectorSize))
        }

        // FAT via the header DIFAT (plus chained DIFAT sectors for big files).
        var fatSectors: [Int] = []
        for i in 0..<109 {
            let entry = i32(data, 76 + i * 4)
            if entry >= 0 { fatSectors.append(entry) }
        }
        var difatSector = difatStart
        var difatSeen = 0
        while difatSector >= 0, difatSeen < difatCount {
            let d = try sector(difatSector)
            for i in 0..<(sectorSize / 4 - 1) {
                let entry = i32(d, i * 4)
                if entry >= 0 { fatSectors.append(entry) }
            }
            difatSector = i32(d, sectorSize - 4)
            difatSeen += 1
        }
        var fat: [Int32] = []
        for s in fatSectors {
            let d = try sector(s)
            for i in 0..<(sectorSize / 4) {
                fat.append(Int32(truncatingIfNeeded: i32(d, i * 4)))
            }
        }

        func chain(_ start: Int) throws -> Data {
            var out = Data()
            var s = start
            var hops = 0
            while s >= 0 {
                out += try sector(s)
                guard fat.indices.contains(s), hops < fat.count + 1 else { throw XLSError.corrupt }
                s = Int(fat[s])
                hops += 1
            }
            return out
        }

        let directory = try chain(dirStart)
        var workbookStart = -1
        var workbookSize = 0
        var rootStart = -1
        var entry = 0
        while (entry + 1) * 128 <= directory.count {
            let base = entry * 128
            let nameLen = Int(u16(directory, base + 64))
            let type = directory[directory.startIndex + base + 66]
            if nameLen >= 2 {
                let nameData = directory.subdata(in: (base)..<(base + nameLen - 2))
                let name = String(data: nameData, encoding: .utf16LittleEndian) ?? ""
                let start = i32(directory, base + 116)
                let size = Int(u32(directory, base + 120))
                if type == 5 { rootStart = start }
                if type == 2, name == "Workbook" || name == "Book" {
                    workbookStart = start
                    workbookSize = size
                }
            }
            entry += 1
        }
        guard workbookStart >= -1, workbookSize > 0 else { throw XLSError.corrupt }

        if workbookSize >= miniCutoff {
            let stream = try chain(workbookStart)
            return stream.prefix(workbookSize)
        }

        // Mini-stream: chained through the mini FAT inside the root entry's stream.
        guard rootStart >= 0, miniFATStart >= 0 else { throw XLSError.corrupt }
        let miniStream = try chain(rootStart)
        let miniFATData = try chain(miniFATStart)
        var out = Data()
        var s = workbookStart
        while s >= 0, out.count < workbookSize {
            let start = s * miniSectorSize
            guard start + miniSectorSize <= miniStream.count else { throw XLSError.corrupt }
            out += miniStream.subdata(in: (miniStream.startIndex + start)..<(miniStream.startIndex + start + miniSectorSize))
            s = i32(miniFATData, s * 4)
        }
        return out.prefix(workbookSize)
    }

    private static func u16(_ data: Data, _ offset: Int) -> Int {
        Int(data[data.startIndex + offset]) | Int(data[data.startIndex + offset + 1]) << 8
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        var v: UInt32 = 0
        for i in 0..<4 { v |= UInt32(data[data.startIndex + offset + i]) << (8 * i) }
        return v
    }

    private static func i32(_ data: Data, _ offset: Int) -> Int {
        Int(Int32(bitPattern: u32(data, offset)))
    }
}
