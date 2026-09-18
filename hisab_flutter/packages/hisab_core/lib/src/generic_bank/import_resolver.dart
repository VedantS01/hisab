/// The one import entry point. Port of ImportResolver.swift: curated code
/// parsers, then bundled specs, then conservative inference — and never a
/// partial or best-guess import.
library;

import '../domain.dart';
import 'column_inference.dart';
import 'chain_interpreter.dart';
import 'format_fingerprint.dart';
import 'format_spec.dart';
import 'normalized_table.dart';
import 'spec_executor.dart';

sealed class Resolution {
  const Resolution();
}

class ResolutionParsed extends Resolution {
  final ParsedDocument document;
  const ResolutionParsed(this.document);
}

class ResolutionPasswordRequired extends Resolution {
  const ResolutionPasswordRequired();
}

/// No engine could read the file at all.
class ResolutionUnsupported extends Resolution {
  final FormatFingerprint fingerprint;
  const ResolutionUnsupported(this.fingerprint);
}

/// A table was read but no interpretation closed the balance chain.
class ResolutionUnverified extends Resolution {
  final FormatFingerprint fingerprint;
  final String detail;
  const ResolutionUnverified(this.fingerprint, this.detail);
}

/// Injected by the parsers module: returns true when the bytes are a PDF that
/// is password-locked and no password was supplied.
bool Function(List<int> data, String? password)? pdfIsLockedCheck;

class ImportResolver {
  final ParserRegistry registry;
  final List<FormatSpec> specs;
  const ImportResolver({required this.registry, required this.specs});

  /// Display names of formats with first-class support — dedicated
  /// parsers first, then bundled bank specs, deduplicated. Drives the
  /// "what Hisab reads" copy; the inference engine extends beyond it.
  List<String> get supportedFormatNames {
    final names = [for (final s in Source.builtIn) s.displayName];
    final seen = names.toSet();
    for (final bank in specs.map((s) => s.bankName).toList()..sort()) {
      if (seen.add(bank)) names.add(bank);
    }
    return names;
  }

  Resolution resolve(
      {required List<int> data,
      required String filename,
      String? password}) {
    // 1. Curated code parsers keep first claim; their errors fall through.
    final parser = registry.detect(data, filename);
    if (parser != null) {
      try {
        return ResolutionParsed(parser.parse(data, password: password));
      } on PasswordRequiredException {
        return const ResolutionPasswordRequired();
      } on ParseException {
        // fall through to the generic path
      }
    }

    final lockedCheck = pdfIsLockedCheck;
    if (filename.toLowerCase().endsWith('.pdf') &&
        lockedCheck != null &&
        lockedCheck(data, password)) {
      return const ResolutionPasswordRequired();
    }

    // 2. A table, or nothing.
    final table =
        NormalizedTable.from(data: data, filename: filename, password: password);
    if (table == null) {
      final ext =
          filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
      final empty = NormalizedTable(
          rows: [], container: ext.isEmpty ? 'unknown' : ext);
      return ResolutionUnsupported(FormatFingerprint.make(empty));
    }

    // 3. Bundled specs, in bundle order.
    String? brokenDetail;
    for (final spec in specs) {
      final outcome = SpecExecutor.execute(table: table, spec: spec);
      if (outcome is ChainValidated) {
        return ResolutionParsed(ParsedDocument(
            source: Source(spec.sourceID),
            declaredPeriod: null,
            transactions: outcome.transactions));
      }
      if (outcome is ChainBroken && brokenDetail == null) {
        brokenDetail = '${spec.id} row ${outcome.rowIndex}: ${outcome.detail}';
      }
    }

    // 4. Conservative inference.
    final fingerprint = FormatFingerprint.make(table);
    final result = ColumnInference.infer(table);
    if (result != null) {
      final guess = fingerprint.bankNameGuess;
      final slug = guess == null ? 'other' : slugify(guess);
      return ResolutionParsed(ParsedDocument(
          source: Source('bank:$slug'),
          declaredPeriod: null,
          transactions: result.transactions));
    }

    // 5. Refuse honestly.
    if (brokenDetail != null) {
      return ResolutionUnverified(fingerprint, brokenDetail);
    }
    return ResolutionUnsupported(fingerprint);
  }

  /// "Bank of Baroda" → "bankofbaroda". Deterministic so re-imports dedup.
  static String slugify(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
