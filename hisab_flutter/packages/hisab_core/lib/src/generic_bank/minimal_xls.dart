/// Just enough of legacy Excel (CDF/OLE2 + BIFF8) to read a bank statement
/// export. Direct port of MinimalXLS.swift: FAT and mini-FAT chains, the SST
/// string table with CONTINUE-record splits, LABELSST and NUMBER cells.
library;

import 'dart:typed_data';

class XlsCorruptException implements Exception {
  final String reason;
  const XlsCorruptException(this.reason);
}

class MinimalXls {
  /// Sparse grid: {row: {column: text}}. NUMBER cells rendered with two
  /// decimals — statement amounts — matching what the text parsers see.
  static Map<int, Map<int, String>> cells(List<int> bytes) {
    final data = Uint8List.fromList(bytes);
    final workbook = _workbookStream(data);
    var strings = <String>[];
    final grid = <int, Map<int, String>>{};

    final records = <(int, Uint8List)>[];
    var pos = 0;
    while (pos + 4 <= workbook.length) {
      final id = workbook[pos] | (workbook[pos + 1] << 8);
      final length = workbook[pos + 2] | (workbook[pos + 3] << 8);
      if (pos + 4 + length > workbook.length) break;
      records.add((id, Uint8List.sublistView(workbook, pos + 4, pos + 4 + length)));
      pos += 4 + length;
    }

    for (var index = 0; index < records.length; index++) {
      final (id, payload) = records[index];
      switch (id) {
        case 0x00FC: // SST, possibly spanning CONTINUE records
          final segments = [payload];
          var next = index + 1;
          while (next < records.length && records[next].$1 == 0x003C) {
            segments.add(records[next].$2);
            next++;
          }
          strings = _parseSst(segments);
        case 0x00FD: // LABELSST: row, col, xf, isst
          if (payload.length < 10) continue;
          final row = _u16(payload, 0), col = _u16(payload, 2);
          final isst = _u32(payload, 6);
          if (isst < strings.length) {
            grid.putIfAbsent(row, () => {})[col] = strings[isst];
          }
        case 0x0203: // NUMBER: row, col, xf, IEEE 754 double
          if (payload.length < 14) continue;
          final row = _u16(payload, 0), col = _u16(payload, 2);
          final value =
              ByteData.sublistView(payload, 6, 14).getFloat64(0, Endian.little);
          grid.putIfAbsent(row, () => {})[col] = value.toStringAsFixed(2);
        default:
          break;
      }
    }
    return grid;
  }

  // ---- SST with CONTINUE handling

  static List<String> _parseSst(List<Uint8List> segments) {
    final cursor = _Cursor(segments);
    cursor.u32(); // total refs
    final unique = cursor.u32();
    final strings = <String>[];

    for (var i = 0; i < unique; i++) {
      final length = cursor.u16();
      var flags = cursor.byte();
      var richRuns = 0;
      var extBytes = 0;
      if (flags & 0x08 != 0) richRuns = cursor.u16();
      if (flags & 0x04 != 0) extBytes = cursor.u32();

      final scalars = <int>[];
      var remaining = length;
      while (remaining > 0) {
        if (cursor.remainingInSegment == 0) {
          // A string continuing into a CONTINUE record re-declares its encoding.
          flags = cursor.byte();
        }
        if (flags & 0x01 != 0) {
          final lo = cursor.byte();
          final hi = cursor.byte();
          scalars.add(lo | (hi << 8));
        } else {
          scalars.add(cursor.byte());
        }
        remaining--;
      }
      cursor.skip(richRuns * 4);
      cursor.skip(extBytes);
      strings.add(String.fromCharCodes(scalars));
    }
    return strings;
  }

  // ---- CDF container

  static Uint8List _workbookStream(Uint8List data) {
    const magic = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
    if (data.length <= 512) throw const XlsCorruptException('too small');
    for (var i = 0; i < magic.length; i++) {
      if (data[i] != magic[i]) throw const XlsCorruptException('not CDF');
    }
    final sectorSize = 1 << _u16(data, 30);
    final miniSectorSize = 1 << _u16(data, 32);
    final dirStart = _i32(data, 48);
    final miniCutoff = _u32(data, 56);
    final miniFatStart = _i32(data, 60);
    final difatStart = _i32(data, 68);
    final difatCount = _u32(data, 72);

    Uint8List sector(int index) {
      final start = 512 + index * sectorSize;
      if (start + sectorSize > data.length) {
        throw const XlsCorruptException('sector out of range');
      }
      return Uint8List.sublistView(data, start, start + sectorSize);
    }

    final fatSectors = <int>[];
    for (var i = 0; i < 109; i++) {
      final entry = _i32(data, 76 + i * 4);
      if (entry >= 0) fatSectors.add(entry);
    }
    var difatSector = difatStart;
    var difatSeen = 0;
    while (difatSector >= 0 && difatSeen < difatCount) {
      final d = sector(difatSector);
      for (var i = 0; i < sectorSize ~/ 4 - 1; i++) {
        final entry = _i32(d, i * 4);
        if (entry >= 0) fatSectors.add(entry);
      }
      difatSector = _i32(d, sectorSize - 4);
      difatSeen++;
    }
    final fat = <int>[];
    for (final s in fatSectors) {
      final d = sector(s);
      for (var i = 0; i < sectorSize ~/ 4; i++) {
        fat.add(_i32(d, i * 4));
      }
    }

    Uint8List chain(int start) {
      final out = BytesBuilder();
      var s = start;
      var hops = 0;
      while (s >= 0) {
        out.add(sector(s));
        if (s >= fat.length || hops > fat.length) {
          throw const XlsCorruptException('broken chain');
        }
        s = fat[s];
        hops++;
      }
      return out.toBytes();
    }

    final directory = chain(dirStart);
    var workbookStart = -1;
    var workbookSize = 0;
    var rootStart = -1;
    var entry = 0;
    while ((entry + 1) * 128 <= directory.length) {
      final base = entry * 128;
      final nameLen = _u16(directory, base + 64);
      final type = directory[base + 66];
      if (nameLen >= 2) {
        final nameBytes = directory.sublist(base, base + nameLen - 2);
        final codeUnits = <int>[];
        for (var i = 0; i + 1 < nameBytes.length; i += 2) {
          codeUnits.add(nameBytes[i] | (nameBytes[i + 1] << 8));
        }
        final name = String.fromCharCodes(codeUnits);
        final start = _i32(directory, base + 116);
        final size = _u32(directory, base + 120);
        if (type == 5) rootStart = start;
        if (type == 2 && (name == 'Workbook' || name == 'Book')) {
          workbookStart = start;
          workbookSize = size;
        }
      }
      entry++;
    }
    if (workbookSize <= 0) throw const XlsCorruptException('no Workbook stream');

    if (workbookSize >= miniCutoff) {
      final stream = chain(workbookStart);
      return Uint8List.sublistView(stream, 0, workbookSize);
    }

    // Mini-stream: chained through the mini FAT inside the root entry's stream.
    if (rootStart < 0 || miniFatStart < 0) {
      throw const XlsCorruptException('no mini stream');
    }
    final miniStream = chain(rootStart);
    final miniFatData = chain(miniFatStart);
    final out = BytesBuilder();
    var s = workbookStart;
    while (s >= 0 && out.length < workbookSize) {
      final start = s * miniSectorSize;
      if (start + miniSectorSize > miniStream.length) {
        throw const XlsCorruptException('mini sector out of range');
      }
      out.add(Uint8List.sublistView(miniStream, start, start + miniSectorSize));
      s = _i32(miniFatData, s * 4);
    }
    return Uint8List.sublistView(out.toBytes(), 0, workbookSize);
  }

  static int _u16(Uint8List d, int o) => d[o] | (d[o + 1] << 8);
  static int _u32(Uint8List d, int o) =>
      d[o] | (d[o + 1] << 8) | (d[o + 2] << 16) | (d[o + 3] << 24);
  static int _i32(Uint8List d, int o) {
    final v = _u32(d, o);
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }
}

class _Cursor {
  final List<Uint8List> segments;
  int segment = 0;
  int offset = 0;
  _Cursor(this.segments);

  int byte() {
    while (segment < segments.length && offset >= segments[segment].length) {
      segment++;
      offset = 0;
    }
    if (segment >= segments.length) throw const XlsCorruptException('SST EOF');
    return segments[segment][offset++];
  }

  void skip(int n) {
    for (var i = 0; i < n; i++) {
      byte();
    }
  }

  int u16() => byte() | (byte() << 8);
  int u32() => u16() | (u16() << 16);

  int get remainingInSegment =>
      segment < segments.length ? segments[segment].length - offset : 0;
}
