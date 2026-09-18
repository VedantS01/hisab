/// Import flow: file picker → resolver → report / password prompt /
/// format-request sheet, mirroring ImportSheet.swift + FormatRequestSheet.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/import_service.dart';
import '../services/password_store.dart';
import '../state.dart';
import '../theme.dart';

Future<void> showImportFlow(BuildContext context) async {
  final state = AppScope.of(context);
  final result = await FilePicker.platform.pickFiles(withData: true);
  final file = result?.files.firstOrNull;
  final data = file?.bytes;
  if (file == null || data == null || !context.mounted) return;

  final supportedNames = state.importService.resolver.supportedFormatNames;

  Future<void> runImport(String? password) async {
    final report = await state.importService.importBytes(
        data: data, filename: file.name, password: password);
    if (password != null && !report.duplicateOfExistingFile) {
      await PasswordStore.setPassword(report.source, password);
    }
    if (context.mounted) _showReport(context, report);
  }

  Future<void> attempt(String? password) async {
    try {
      await runImport(password);
    } on PasswordRequiredException {
      if (!context.mounted) return;
      // The source isn't known until the file parses, so a locked file
      // is retried with every remembered password before asking.
      if (password == null) {
        for (final stored in await PasswordStore.allPasswords()) {
          try {
            await runImport(stored);
            return;
          } on UnsupportedFormatException catch (e) {
            if (context.mounted) {
              _showFormatRequest(context, e.fingerprint, null, supportedNames);
            }
            return;
          } on UnverifiedStatementException catch (e) {
            if (context.mounted) {
              _showFormatRequest(
                  context, e.fingerprint, e.detail, supportedNames);
            }
            return;
          } catch (_) {
            // Wrong password for this file — try the next one.
          }
        }
        if (!context.mounted) return;
      }
      final typed = await _askPassword(context, file.name);
      if (typed != null && typed.isNotEmpty) await attempt(typed);
    } on UnsupportedFormatException catch (e) {
      if (context.mounted) {
        _showFormatRequest(context, e.fingerprint, null, supportedNames);
      }
    } on UnverifiedStatementException catch (e) {
      if (context.mounted) {
        _showFormatRequest(context, e.fingerprint, e.detail, supportedNames);
      }
    } on ParseException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not parse ${file.name}: $e')));
      }
    }
  }

  await attempt(null);
}

Future<String?> _askPassword(BuildContext context, String filename) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Statement password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(filename, style: const TextStyle(fontSize: 12)),
          TextField(controller: controller, obscureText: true, autofocus: true),
          const Text('Remembered securely on this device.',
              style: TextStyle(fontSize: 11, color: Colors.black54)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Unlock')),
      ],
    ),
  );
}

void _showReport(BuildContext context, ImportReport report) {
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                report.duplicateOfExistingFile
                    ? Icons.copy_all
                    : Icons.verified,
                size: 44,
                color: report.duplicateOfExistingFile
                    ? Colors.black45
                    : HisabTheme.hara),
            const SizedBox(height: 12),
            Text(
              report.duplicateOfExistingFile
                  ? 'Already imported'
                  : '${report.newCount} new transaction${report.newCount == 1 ? '' : 's'}',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              report.duplicateOfExistingFile
                  ? 'This exact file is in your bahi already — nothing new to add.'
                  : '${report.source.displayName} · ${report.totalParsed} parsed · ${report.totalParsed - report.newCount} duplicates skipped',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            if (report.monthsTouched.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Months: ${report.monthsTouched.map((m) => m.displayName).join(', ')}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

void _showFormatRequest(BuildContext context, FormatFingerprint fingerprint,
    String? verificationDetail, List<String> supportedNames) {
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                verificationDetail == null
                    ? Icons.help_outline
                    : Icons.gpp_maybe,
                size: 44,
                color: HisabTheme.khataRed),
            const SizedBox(height: 12),
            Text(
              verificationDetail == null
                  ? "Hisab can't read this statement format yet."
                  : "Couldn't verify this statement.",
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              verificationDetail != null
                  ? 'The running balance doesn\'t add up ($verificationDetail). The file may be truncated or edited — nothing was imported.'
                  : (fingerprint.bankNameGuess != null
                          ? 'This looks like a ${fingerprint.bankNameGuess} statement. '
                          : '') +
                      'Support for new formats arrives in app updates. The request email contains only column labels and value shapes — no transactions.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            if (verificationDetail == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Hisab reads today: ${supportedNames.join(', ')} — plus '
                  'most Indian bank statements that print a running balance.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 11),
                ),
              ),
            const SizedBox(height: 16),
            if (verificationDetail == null)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: HisabTheme.khataRed),
                onPressed: () {
                  launchUrl(fingerprint.mailtoUri(appVersion: '1.1.0'));
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.mail_outline),
                label: const Text('Request support'),
              ),
          ],
        ),
      ),
    ),
  );
}
