/// IDFC particulars extraction shared by the XLSX and PDF parsers.
/// Port of IDFCStatementText.extract.
library;

class IdfcStatementText {
  /// Counterparty/reference from the particulars, by transaction rail:
  /// "UPI/DR/<ref>/<name>/…", "NEFT/<ref>/<name>/…", "POS-…/<name>/<ref>/…".
  static (String, String?) extract(String particulars) {
    final parts = particulars.split('/').map((p) => p.trim()).toList();
    if (parts.length >= 4 &&
        parts[0] == 'UPI' &&
        (parts[1] == 'DR' || parts[1] == 'CR')) {
      return (parts[3], parts[2].isEmpty ? null : parts[2]);
    }
    if (parts.length >= 3 &&
        (parts[0] == 'NEFT' || parts[0] == 'IMPS' || parts[0] == 'RTGS')) {
      return (parts[2], parts[1].isEmpty ? null : parts[1]);
    }
    if (parts.length >= 3 && parts[0].startsWith('POS')) {
      final refCandidate = parts[2];
      final ref = refCandidate.isNotEmpty &&
              RegExp(r'^\d+$').hasMatch(refCandidate)
          ? refCandidate
          : null;
      return (parts[1], ref);
    }
    final name = particulars.length > 60
        ? particulars.substring(0, 60).trim()
        : particulars.trim();
    return (name, null);
  }
}
