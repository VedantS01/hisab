/// Domain types. Port of Domain.swift and Parsing.swift's value types.
library;

import 'year_month.dart';

enum SourceKind { paymentApp, bank }

/// Statement sources. The five original ids are frozen (they live inside
/// stored content hashes); new banks and apps use open ids like "bank:sbi"
/// or "upi:phonepe".
class Source {
  final String rawValue;
  const Source(this.rawValue);

  static const gpay = Source('gpay');
  static const paytm = Source('paytm');
  static const bhim = Source('bhim');
  static const hdfc = Source('hdfc');
  static const idfc = Source('idfc');

  /// Sources with first-party parsers; drives pickers, filters, and copy.
  static const builtIn = [gpay, paytm, bhim, hdfc, idfc];

  SourceKind get kind {
    switch (rawValue) {
      case 'gpay':
      case 'paytm':
      case 'bhim':
        return SourceKind.paymentApp;
      default:
        return rawValue.startsWith('upi:')
            ? SourceKind.paymentApp
            : SourceKind.bank;
    }
  }

  String get displayName {
    switch (rawValue) {
      case 'gpay':
        return 'Google Pay';
      case 'paytm':
        return 'Paytm';
      case 'bhim':
        return 'BHIM UPI';
      case 'hdfc':
        return 'HDFC Bank';
      case 'idfc':
        return 'IDFC First Bank';
      default:
        final slug = rawValue.split(':').last;
        if (slug.length <= 4) return slug.toUpperCase();
        return slug[0].toUpperCase() + slug.substring(1);
    }
  }

  /// Payment apps first, then banks, alphabetical by display name within kind.
  static List<Source> ordered(Iterable<Source> sources) {
    final unique = sources.toSet().toList();
    unique.sort((a, b) {
      if (a.kind != b.kind) return a.kind == SourceKind.paymentApp ? -1 : 1;
      return a.displayName.compareTo(b.displayName);
    });
    return unique;
  }

  @override
  bool operator ==(Object other) => other is Source && other.rawValue == rawValue;
  @override
  int get hashCode => rawValue.hashCode;
  @override
  String toString() => rawValue;
}

enum Direction { debit, credit }

/// An inclusive date range, month-resolved in IST.
class DatePeriod {
  final DateTime start;
  final DateTime end;
  const DatePeriod(this.start, this.end);

  List<YearMonth> get months => YearMonth.monthsFromThrough(
      YearMonth.fromDate(start), YearMonth.fromDate(end));
}

/// One transaction as read out of a statement file. Sign lives in
/// `direction`; `amountPaise` is positive.
class ParsedTransaction {
  final DateTime date;
  final int amountPaise;
  final Direction direction;
  final String counterparty;
  final String? reference;
  final String narration;

  const ParsedTransaction({
    required this.date,
    required this.amountPaise,
    required this.direction,
    required this.counterparty,
    required this.reference,
    required this.narration,
  });

  @override
  bool operator ==(Object other) =>
      other is ParsedTransaction &&
      other.date == date &&
      other.amountPaise == amountPaise &&
      other.direction == direction &&
      other.counterparty == counterparty &&
      other.reference == reference &&
      other.narration == narration;

  @override
  int get hashCode => Object.hash(
      date, amountPaise, direction, counterparty, reference, narration);
}

class ParsedDocument {
  final Source source;
  final DatePeriod? declaredPeriod;
  final List<ParsedTransaction> transactions;

  const ParsedDocument({
    required this.source,
    required this.declaredPeriod,
    required this.transactions,
  });

  /// Declared statement period when the format carries one, else row span.
  DatePeriod get effectivePeriod {
    final declared = declaredPeriod;
    if (declared != null) return declared;
    assert(transactions.isNotEmpty, 'document with no period and no rows');
    final dates = transactions.map((t) => t.date).toList()..sort();
    return DatePeriod(dates.first, dates.last);
  }
}

sealed class ParseException implements Exception {
  const ParseException();
}

class UnrecognizedFormatException extends ParseException {
  const UnrecognizedFormatException();
}

class PasswordRequiredException extends ParseException {
  const PasswordRequiredException();
}

class MalformedRowException extends ParseException {
  final int line; // 1-based
  final String raw;
  const MalformedRowException(this.line, this.raw);
  @override
  String toString() => 'MalformedRow($line, $raw)';
}

class EmptyDocumentException extends ParseException {
  const EmptyDocumentException();
}

/// A statement parser. Port of the StatementParser protocol.
abstract interface class StatementParser {
  Source get source;
  bool canParse(List<int> data, String filename);
  ParsedDocument parse(List<int> data, {String? password});
}

class ParserRegistry {
  final List<StatementParser> parsers;
  const ParserRegistry(this.parsers);

  StatementParser? detect(List<int> data, String filename) {
    for (final parser in parsers) {
      if (parser.canParse(data, filename)) return parser;
    }
    return null;
  }
}
