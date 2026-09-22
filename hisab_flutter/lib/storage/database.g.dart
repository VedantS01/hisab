// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $StoredDocumentsTable extends StoredDocuments
    with TableInfo<$StoredDocumentsTable, StoredDocument> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredDocumentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sourceRawMeta =
      const VerificationMeta('sourceRaw');
  @override
  late final GeneratedColumn<String> sourceRaw = GeneratedColumn<String>(
      'source_raw', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _filenameMeta =
      const VerificationMeta('filename');
  @override
  late final GeneratedColumn<String> filename = GeneratedColumn<String>(
      'filename', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fileSha256Meta =
      const VerificationMeta('fileSha256');
  @override
  late final GeneratedColumn<String> fileSha256 = GeneratedColumn<String>(
      'file_sha256', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _periodStartMsMeta =
      const VerificationMeta('periodStartMs');
  @override
  late final GeneratedColumn<int> periodStartMs = GeneratedColumn<int>(
      'period_start_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _periodEndMsMeta =
      const VerificationMeta('periodEndMs');
  @override
  late final GeneratedColumn<int> periodEndMs = GeneratedColumn<int>(
      'period_end_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, sourceRaw, filename, fileSha256, periodStartMs, periodEndMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_documents';
  @override
  VerificationContext validateIntegrity(Insertable<StoredDocument> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('source_raw')) {
      context.handle(_sourceRawMeta,
          sourceRaw.isAcceptableOrUnknown(data['source_raw']!, _sourceRawMeta));
    } else if (isInserting) {
      context.missing(_sourceRawMeta);
    }
    if (data.containsKey('filename')) {
      context.handle(_filenameMeta,
          filename.isAcceptableOrUnknown(data['filename']!, _filenameMeta));
    } else if (isInserting) {
      context.missing(_filenameMeta);
    }
    if (data.containsKey('file_sha256')) {
      context.handle(
          _fileSha256Meta,
          fileSha256.isAcceptableOrUnknown(
              data['file_sha256']!, _fileSha256Meta));
    } else if (isInserting) {
      context.missing(_fileSha256Meta);
    }
    if (data.containsKey('period_start_ms')) {
      context.handle(
          _periodStartMsMeta,
          periodStartMs.isAcceptableOrUnknown(
              data['period_start_ms']!, _periodStartMsMeta));
    } else if (isInserting) {
      context.missing(_periodStartMsMeta);
    }
    if (data.containsKey('period_end_ms')) {
      context.handle(
          _periodEndMsMeta,
          periodEndMs.isAcceptableOrUnknown(
              data['period_end_ms']!, _periodEndMsMeta));
    } else if (isInserting) {
      context.missing(_periodEndMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StoredDocument map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredDocument(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      sourceRaw: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_raw'])!,
      filename: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}filename'])!,
      fileSha256: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_sha256'])!,
      periodStartMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}period_start_ms'])!,
      periodEndMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}period_end_ms'])!,
    );
  }

  @override
  $StoredDocumentsTable createAlias(String alias) {
    return $StoredDocumentsTable(attachedDatabase, alias);
  }
}

class StoredDocument extends DataClass implements Insertable<StoredDocument> {
  final String id;
  final String sourceRaw;
  final String filename;
  final String fileSha256;
  final int periodStartMs;
  final int periodEndMs;
  const StoredDocument(
      {required this.id,
      required this.sourceRaw,
      required this.filename,
      required this.fileSha256,
      required this.periodStartMs,
      required this.periodEndMs});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['source_raw'] = Variable<String>(sourceRaw);
    map['filename'] = Variable<String>(filename);
    map['file_sha256'] = Variable<String>(fileSha256);
    map['period_start_ms'] = Variable<int>(periodStartMs);
    map['period_end_ms'] = Variable<int>(periodEndMs);
    return map;
  }

  StoredDocumentsCompanion toCompanion(bool nullToAbsent) {
    return StoredDocumentsCompanion(
      id: Value(id),
      sourceRaw: Value(sourceRaw),
      filename: Value(filename),
      fileSha256: Value(fileSha256),
      periodStartMs: Value(periodStartMs),
      periodEndMs: Value(periodEndMs),
    );
  }

  factory StoredDocument.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredDocument(
      id: serializer.fromJson<String>(json['id']),
      sourceRaw: serializer.fromJson<String>(json['sourceRaw']),
      filename: serializer.fromJson<String>(json['filename']),
      fileSha256: serializer.fromJson<String>(json['fileSha256']),
      periodStartMs: serializer.fromJson<int>(json['periodStartMs']),
      periodEndMs: serializer.fromJson<int>(json['periodEndMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sourceRaw': serializer.toJson<String>(sourceRaw),
      'filename': serializer.toJson<String>(filename),
      'fileSha256': serializer.toJson<String>(fileSha256),
      'periodStartMs': serializer.toJson<int>(periodStartMs),
      'periodEndMs': serializer.toJson<int>(periodEndMs),
    };
  }

  StoredDocument copyWith(
          {String? id,
          String? sourceRaw,
          String? filename,
          String? fileSha256,
          int? periodStartMs,
          int? periodEndMs}) =>
      StoredDocument(
        id: id ?? this.id,
        sourceRaw: sourceRaw ?? this.sourceRaw,
        filename: filename ?? this.filename,
        fileSha256: fileSha256 ?? this.fileSha256,
        periodStartMs: periodStartMs ?? this.periodStartMs,
        periodEndMs: periodEndMs ?? this.periodEndMs,
      );
  StoredDocument copyWithCompanion(StoredDocumentsCompanion data) {
    return StoredDocument(
      id: data.id.present ? data.id.value : this.id,
      sourceRaw: data.sourceRaw.present ? data.sourceRaw.value : this.sourceRaw,
      filename: data.filename.present ? data.filename.value : this.filename,
      fileSha256:
          data.fileSha256.present ? data.fileSha256.value : this.fileSha256,
      periodStartMs: data.periodStartMs.present
          ? data.periodStartMs.value
          : this.periodStartMs,
      periodEndMs:
          data.periodEndMs.present ? data.periodEndMs.value : this.periodEndMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredDocument(')
          ..write('id: $id, ')
          ..write('sourceRaw: $sourceRaw, ')
          ..write('filename: $filename, ')
          ..write('fileSha256: $fileSha256, ')
          ..write('periodStartMs: $periodStartMs, ')
          ..write('periodEndMs: $periodEndMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, sourceRaw, filename, fileSha256, periodStartMs, periodEndMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredDocument &&
          other.id == this.id &&
          other.sourceRaw == this.sourceRaw &&
          other.filename == this.filename &&
          other.fileSha256 == this.fileSha256 &&
          other.periodStartMs == this.periodStartMs &&
          other.periodEndMs == this.periodEndMs);
}

class StoredDocumentsCompanion extends UpdateCompanion<StoredDocument> {
  final Value<String> id;
  final Value<String> sourceRaw;
  final Value<String> filename;
  final Value<String> fileSha256;
  final Value<int> periodStartMs;
  final Value<int> periodEndMs;
  final Value<int> rowid;
  const StoredDocumentsCompanion({
    this.id = const Value.absent(),
    this.sourceRaw = const Value.absent(),
    this.filename = const Value.absent(),
    this.fileSha256 = const Value.absent(),
    this.periodStartMs = const Value.absent(),
    this.periodEndMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredDocumentsCompanion.insert({
    required String id,
    required String sourceRaw,
    required String filename,
    required String fileSha256,
    required int periodStartMs,
    required int periodEndMs,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        sourceRaw = Value(sourceRaw),
        filename = Value(filename),
        fileSha256 = Value(fileSha256),
        periodStartMs = Value(periodStartMs),
        periodEndMs = Value(periodEndMs);
  static Insertable<StoredDocument> custom({
    Expression<String>? id,
    Expression<String>? sourceRaw,
    Expression<String>? filename,
    Expression<String>? fileSha256,
    Expression<int>? periodStartMs,
    Expression<int>? periodEndMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceRaw != null) 'source_raw': sourceRaw,
      if (filename != null) 'filename': filename,
      if (fileSha256 != null) 'file_sha256': fileSha256,
      if (periodStartMs != null) 'period_start_ms': periodStartMs,
      if (periodEndMs != null) 'period_end_ms': periodEndMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredDocumentsCompanion copyWith(
      {Value<String>? id,
      Value<String>? sourceRaw,
      Value<String>? filename,
      Value<String>? fileSha256,
      Value<int>? periodStartMs,
      Value<int>? periodEndMs,
      Value<int>? rowid}) {
    return StoredDocumentsCompanion(
      id: id ?? this.id,
      sourceRaw: sourceRaw ?? this.sourceRaw,
      filename: filename ?? this.filename,
      fileSha256: fileSha256 ?? this.fileSha256,
      periodStartMs: periodStartMs ?? this.periodStartMs,
      periodEndMs: periodEndMs ?? this.periodEndMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sourceRaw.present) {
      map['source_raw'] = Variable<String>(sourceRaw.value);
    }
    if (filename.present) {
      map['filename'] = Variable<String>(filename.value);
    }
    if (fileSha256.present) {
      map['file_sha256'] = Variable<String>(fileSha256.value);
    }
    if (periodStartMs.present) {
      map['period_start_ms'] = Variable<int>(periodStartMs.value);
    }
    if (periodEndMs.present) {
      map['period_end_ms'] = Variable<int>(periodEndMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredDocumentsCompanion(')
          ..write('id: $id, ')
          ..write('sourceRaw: $sourceRaw, ')
          ..write('filename: $filename, ')
          ..write('fileSha256: $fileSha256, ')
          ..write('periodStartMs: $periodStartMs, ')
          ..write('periodEndMs: $periodEndMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoredTransactionsTable extends StoredTransactions
    with TableInfo<$StoredTransactionsTable, StoredTransaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredTransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
      'uuid', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentHashMeta =
      const VerificationMeta('contentHash');
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
      'content_hash', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _sourceRawMeta =
      const VerificationMeta('sourceRaw');
  @override
  late final GeneratedColumn<String> sourceRaw = GeneratedColumn<String>(
      'source_raw', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dateMsMeta = const VerificationMeta('dateMs');
  @override
  late final GeneratedColumn<int> dateMs = GeneratedColumn<int>(
      'date_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _amountPaiseMeta =
      const VerificationMeta('amountPaise');
  @override
  late final GeneratedColumn<int> amountPaise = GeneratedColumn<int>(
      'amount_paise', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _directionMeta =
      const VerificationMeta('direction');
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
      'direction', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _counterpartyMeta =
      const VerificationMeta('counterparty');
  @override
  late final GeneratedColumn<String> counterparty = GeneratedColumn<String>(
      'counterparty', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _referenceMeta =
      const VerificationMeta('reference');
  @override
  late final GeneratedColumn<String> reference = GeneratedColumn<String>(
      'reference', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _narrationMeta =
      const VerificationMeta('narration');
  @override
  late final GeneratedColumn<String> narration = GeneratedColumn<String>(
      'narration', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryOverrideMeta =
      const VerificationMeta('categoryOverride');
  @override
  late final GeneratedColumn<String> categoryOverride = GeneratedColumn<String>(
      'category_override', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _documentIdMeta =
      const VerificationMeta('documentId');
  @override
  late final GeneratedColumn<String> documentId = GeneratedColumn<String>(
      'document_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        uuid,
        contentHash,
        sourceRaw,
        dateMs,
        amountPaise,
        direction,
        counterparty,
        reference,
        narration,
        categoryOverride,
        documentId
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_transactions';
  @override
  VerificationContext validateIntegrity(Insertable<StoredTransaction> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('uuid')) {
      context.handle(
          _uuidMeta, uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta));
    } else if (isInserting) {
      context.missing(_uuidMeta);
    }
    if (data.containsKey('content_hash')) {
      context.handle(
          _contentHashMeta,
          contentHash.isAcceptableOrUnknown(
              data['content_hash']!, _contentHashMeta));
    } else if (isInserting) {
      context.missing(_contentHashMeta);
    }
    if (data.containsKey('source_raw')) {
      context.handle(_sourceRawMeta,
          sourceRaw.isAcceptableOrUnknown(data['source_raw']!, _sourceRawMeta));
    } else if (isInserting) {
      context.missing(_sourceRawMeta);
    }
    if (data.containsKey('date_ms')) {
      context.handle(_dateMsMeta,
          dateMs.isAcceptableOrUnknown(data['date_ms']!, _dateMsMeta));
    } else if (isInserting) {
      context.missing(_dateMsMeta);
    }
    if (data.containsKey('amount_paise')) {
      context.handle(
          _amountPaiseMeta,
          amountPaise.isAcceptableOrUnknown(
              data['amount_paise']!, _amountPaiseMeta));
    } else if (isInserting) {
      context.missing(_amountPaiseMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(_directionMeta,
          direction.isAcceptableOrUnknown(data['direction']!, _directionMeta));
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('counterparty')) {
      context.handle(
          _counterpartyMeta,
          counterparty.isAcceptableOrUnknown(
              data['counterparty']!, _counterpartyMeta));
    } else if (isInserting) {
      context.missing(_counterpartyMeta);
    }
    if (data.containsKey('reference')) {
      context.handle(_referenceMeta,
          reference.isAcceptableOrUnknown(data['reference']!, _referenceMeta));
    }
    if (data.containsKey('narration')) {
      context.handle(_narrationMeta,
          narration.isAcceptableOrUnknown(data['narration']!, _narrationMeta));
    } else if (isInserting) {
      context.missing(_narrationMeta);
    }
    if (data.containsKey('category_override')) {
      context.handle(
          _categoryOverrideMeta,
          categoryOverride.isAcceptableOrUnknown(
              data['category_override']!, _categoryOverrideMeta));
    }
    if (data.containsKey('document_id')) {
      context.handle(
          _documentIdMeta,
          documentId.isAcceptableOrUnknown(
              data['document_id']!, _documentIdMeta));
    } else if (isInserting) {
      context.missing(_documentIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {uuid};
  @override
  StoredTransaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredTransaction(
      uuid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}uuid'])!,
      contentHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content_hash'])!,
      sourceRaw: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_raw'])!,
      dateMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}date_ms'])!,
      amountPaise: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}amount_paise'])!,
      direction: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}direction'])!,
      counterparty: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}counterparty'])!,
      reference: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}reference']),
      narration: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}narration'])!,
      categoryOverride: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}category_override']),
      documentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}document_id'])!,
    );
  }

  @override
  $StoredTransactionsTable createAlias(String alias) {
    return $StoredTransactionsTable(attachedDatabase, alias);
  }
}

class StoredTransaction extends DataClass
    implements Insertable<StoredTransaction> {
  final String uuid;
  final String contentHash;
  final String sourceRaw;
  final int dateMs;
  final int amountPaise;
  final String direction;
  final String counterparty;
  final String? reference;
  final String narration;
  final String? categoryOverride;
  final String documentId;
  const StoredTransaction(
      {required this.uuid,
      required this.contentHash,
      required this.sourceRaw,
      required this.dateMs,
      required this.amountPaise,
      required this.direction,
      required this.counterparty,
      this.reference,
      required this.narration,
      this.categoryOverride,
      required this.documentId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['uuid'] = Variable<String>(uuid);
    map['content_hash'] = Variable<String>(contentHash);
    map['source_raw'] = Variable<String>(sourceRaw);
    map['date_ms'] = Variable<int>(dateMs);
    map['amount_paise'] = Variable<int>(amountPaise);
    map['direction'] = Variable<String>(direction);
    map['counterparty'] = Variable<String>(counterparty);
    if (!nullToAbsent || reference != null) {
      map['reference'] = Variable<String>(reference);
    }
    map['narration'] = Variable<String>(narration);
    if (!nullToAbsent || categoryOverride != null) {
      map['category_override'] = Variable<String>(categoryOverride);
    }
    map['document_id'] = Variable<String>(documentId);
    return map;
  }

  StoredTransactionsCompanion toCompanion(bool nullToAbsent) {
    return StoredTransactionsCompanion(
      uuid: Value(uuid),
      contentHash: Value(contentHash),
      sourceRaw: Value(sourceRaw),
      dateMs: Value(dateMs),
      amountPaise: Value(amountPaise),
      direction: Value(direction),
      counterparty: Value(counterparty),
      reference: reference == null && nullToAbsent
          ? const Value.absent()
          : Value(reference),
      narration: Value(narration),
      categoryOverride: categoryOverride == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryOverride),
      documentId: Value(documentId),
    );
  }

  factory StoredTransaction.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredTransaction(
      uuid: serializer.fromJson<String>(json['uuid']),
      contentHash: serializer.fromJson<String>(json['contentHash']),
      sourceRaw: serializer.fromJson<String>(json['sourceRaw']),
      dateMs: serializer.fromJson<int>(json['dateMs']),
      amountPaise: serializer.fromJson<int>(json['amountPaise']),
      direction: serializer.fromJson<String>(json['direction']),
      counterparty: serializer.fromJson<String>(json['counterparty']),
      reference: serializer.fromJson<String?>(json['reference']),
      narration: serializer.fromJson<String>(json['narration']),
      categoryOverride: serializer.fromJson<String?>(json['categoryOverride']),
      documentId: serializer.fromJson<String>(json['documentId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'uuid': serializer.toJson<String>(uuid),
      'contentHash': serializer.toJson<String>(contentHash),
      'sourceRaw': serializer.toJson<String>(sourceRaw),
      'dateMs': serializer.toJson<int>(dateMs),
      'amountPaise': serializer.toJson<int>(amountPaise),
      'direction': serializer.toJson<String>(direction),
      'counterparty': serializer.toJson<String>(counterparty),
      'reference': serializer.toJson<String?>(reference),
      'narration': serializer.toJson<String>(narration),
      'categoryOverride': serializer.toJson<String?>(categoryOverride),
      'documentId': serializer.toJson<String>(documentId),
    };
  }

  StoredTransaction copyWith(
          {String? uuid,
          String? contentHash,
          String? sourceRaw,
          int? dateMs,
          int? amountPaise,
          String? direction,
          String? counterparty,
          Value<String?> reference = const Value.absent(),
          String? narration,
          Value<String?> categoryOverride = const Value.absent(),
          String? documentId}) =>
      StoredTransaction(
        uuid: uuid ?? this.uuid,
        contentHash: contentHash ?? this.contentHash,
        sourceRaw: sourceRaw ?? this.sourceRaw,
        dateMs: dateMs ?? this.dateMs,
        amountPaise: amountPaise ?? this.amountPaise,
        direction: direction ?? this.direction,
        counterparty: counterparty ?? this.counterparty,
        reference: reference.present ? reference.value : this.reference,
        narration: narration ?? this.narration,
        categoryOverride: categoryOverride.present
            ? categoryOverride.value
            : this.categoryOverride,
        documentId: documentId ?? this.documentId,
      );
  StoredTransaction copyWithCompanion(StoredTransactionsCompanion data) {
    return StoredTransaction(
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      contentHash:
          data.contentHash.present ? data.contentHash.value : this.contentHash,
      sourceRaw: data.sourceRaw.present ? data.sourceRaw.value : this.sourceRaw,
      dateMs: data.dateMs.present ? data.dateMs.value : this.dateMs,
      amountPaise:
          data.amountPaise.present ? data.amountPaise.value : this.amountPaise,
      direction: data.direction.present ? data.direction.value : this.direction,
      counterparty: data.counterparty.present
          ? data.counterparty.value
          : this.counterparty,
      reference: data.reference.present ? data.reference.value : this.reference,
      narration: data.narration.present ? data.narration.value : this.narration,
      categoryOverride: data.categoryOverride.present
          ? data.categoryOverride.value
          : this.categoryOverride,
      documentId:
          data.documentId.present ? data.documentId.value : this.documentId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredTransaction(')
          ..write('uuid: $uuid, ')
          ..write('contentHash: $contentHash, ')
          ..write('sourceRaw: $sourceRaw, ')
          ..write('dateMs: $dateMs, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('direction: $direction, ')
          ..write('counterparty: $counterparty, ')
          ..write('reference: $reference, ')
          ..write('narration: $narration, ')
          ..write('categoryOverride: $categoryOverride, ')
          ..write('documentId: $documentId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      uuid,
      contentHash,
      sourceRaw,
      dateMs,
      amountPaise,
      direction,
      counterparty,
      reference,
      narration,
      categoryOverride,
      documentId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredTransaction &&
          other.uuid == this.uuid &&
          other.contentHash == this.contentHash &&
          other.sourceRaw == this.sourceRaw &&
          other.dateMs == this.dateMs &&
          other.amountPaise == this.amountPaise &&
          other.direction == this.direction &&
          other.counterparty == this.counterparty &&
          other.reference == this.reference &&
          other.narration == this.narration &&
          other.categoryOverride == this.categoryOverride &&
          other.documentId == this.documentId);
}

class StoredTransactionsCompanion extends UpdateCompanion<StoredTransaction> {
  final Value<String> uuid;
  final Value<String> contentHash;
  final Value<String> sourceRaw;
  final Value<int> dateMs;
  final Value<int> amountPaise;
  final Value<String> direction;
  final Value<String> counterparty;
  final Value<String?> reference;
  final Value<String> narration;
  final Value<String?> categoryOverride;
  final Value<String> documentId;
  final Value<int> rowid;
  const StoredTransactionsCompanion({
    this.uuid = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.sourceRaw = const Value.absent(),
    this.dateMs = const Value.absent(),
    this.amountPaise = const Value.absent(),
    this.direction = const Value.absent(),
    this.counterparty = const Value.absent(),
    this.reference = const Value.absent(),
    this.narration = const Value.absent(),
    this.categoryOverride = const Value.absent(),
    this.documentId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredTransactionsCompanion.insert({
    required String uuid,
    required String contentHash,
    required String sourceRaw,
    required int dateMs,
    required int amountPaise,
    required String direction,
    required String counterparty,
    this.reference = const Value.absent(),
    required String narration,
    this.categoryOverride = const Value.absent(),
    required String documentId,
    this.rowid = const Value.absent(),
  })  : uuid = Value(uuid),
        contentHash = Value(contentHash),
        sourceRaw = Value(sourceRaw),
        dateMs = Value(dateMs),
        amountPaise = Value(amountPaise),
        direction = Value(direction),
        counterparty = Value(counterparty),
        narration = Value(narration),
        documentId = Value(documentId);
  static Insertable<StoredTransaction> custom({
    Expression<String>? uuid,
    Expression<String>? contentHash,
    Expression<String>? sourceRaw,
    Expression<int>? dateMs,
    Expression<int>? amountPaise,
    Expression<String>? direction,
    Expression<String>? counterparty,
    Expression<String>? reference,
    Expression<String>? narration,
    Expression<String>? categoryOverride,
    Expression<String>? documentId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (uuid != null) 'uuid': uuid,
      if (contentHash != null) 'content_hash': contentHash,
      if (sourceRaw != null) 'source_raw': sourceRaw,
      if (dateMs != null) 'date_ms': dateMs,
      if (amountPaise != null) 'amount_paise': amountPaise,
      if (direction != null) 'direction': direction,
      if (counterparty != null) 'counterparty': counterparty,
      if (reference != null) 'reference': reference,
      if (narration != null) 'narration': narration,
      if (categoryOverride != null) 'category_override': categoryOverride,
      if (documentId != null) 'document_id': documentId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredTransactionsCompanion copyWith(
      {Value<String>? uuid,
      Value<String>? contentHash,
      Value<String>? sourceRaw,
      Value<int>? dateMs,
      Value<int>? amountPaise,
      Value<String>? direction,
      Value<String>? counterparty,
      Value<String?>? reference,
      Value<String>? narration,
      Value<String?>? categoryOverride,
      Value<String>? documentId,
      Value<int>? rowid}) {
    return StoredTransactionsCompanion(
      uuid: uuid ?? this.uuid,
      contentHash: contentHash ?? this.contentHash,
      sourceRaw: sourceRaw ?? this.sourceRaw,
      dateMs: dateMs ?? this.dateMs,
      amountPaise: amountPaise ?? this.amountPaise,
      direction: direction ?? this.direction,
      counterparty: counterparty ?? this.counterparty,
      reference: reference ?? this.reference,
      narration: narration ?? this.narration,
      categoryOverride: categoryOverride ?? this.categoryOverride,
      documentId: documentId ?? this.documentId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (sourceRaw.present) {
      map['source_raw'] = Variable<String>(sourceRaw.value);
    }
    if (dateMs.present) {
      map['date_ms'] = Variable<int>(dateMs.value);
    }
    if (amountPaise.present) {
      map['amount_paise'] = Variable<int>(amountPaise.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (counterparty.present) {
      map['counterparty'] = Variable<String>(counterparty.value);
    }
    if (reference.present) {
      map['reference'] = Variable<String>(reference.value);
    }
    if (narration.present) {
      map['narration'] = Variable<String>(narration.value);
    }
    if (categoryOverride.present) {
      map['category_override'] = Variable<String>(categoryOverride.value);
    }
    if (documentId.present) {
      map['document_id'] = Variable<String>(documentId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredTransactionsCompanion(')
          ..write('uuid: $uuid, ')
          ..write('contentHash: $contentHash, ')
          ..write('sourceRaw: $sourceRaw, ')
          ..write('dateMs: $dateMs, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('direction: $direction, ')
          ..write('counterparty: $counterparty, ')
          ..write('reference: $reference, ')
          ..write('narration: $narration, ')
          ..write('categoryOverride: $categoryOverride, ')
          ..write('documentId: $documentId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoredCategoryRulesTable extends StoredCategoryRules
    with TableInfo<$StoredCategoryRulesTable, StoredCategoryRule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredCategoryRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _patternMeta =
      const VerificationMeta('pattern');
  @override
  late final GeneratedColumn<String> pattern = GeneratedColumn<String>(
      'pattern', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, pattern, category, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_category_rules';
  @override
  VerificationContext validateIntegrity(Insertable<StoredCategoryRule> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('pattern')) {
      context.handle(_patternMeta,
          pattern.isAcceptableOrUnknown(data['pattern']!, _patternMeta));
    } else if (isInserting) {
      context.missing(_patternMeta);
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StoredCategoryRule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredCategoryRule(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      pattern: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}pattern'])!,
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category'])!,
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
    );
  }

  @override
  $StoredCategoryRulesTable createAlias(String alias) {
    return $StoredCategoryRulesTable(attachedDatabase, alias);
  }
}

class StoredCategoryRule extends DataClass
    implements Insertable<StoredCategoryRule> {
  final String id;
  final String pattern;
  final String category;
  final int sortOrder;
  const StoredCategoryRule(
      {required this.id,
      required this.pattern,
      required this.category,
      required this.sortOrder});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['pattern'] = Variable<String>(pattern);
    map['category'] = Variable<String>(category);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  StoredCategoryRulesCompanion toCompanion(bool nullToAbsent) {
    return StoredCategoryRulesCompanion(
      id: Value(id),
      pattern: Value(pattern),
      category: Value(category),
      sortOrder: Value(sortOrder),
    );
  }

  factory StoredCategoryRule.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredCategoryRule(
      id: serializer.fromJson<String>(json['id']),
      pattern: serializer.fromJson<String>(json['pattern']),
      category: serializer.fromJson<String>(json['category']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'pattern': serializer.toJson<String>(pattern),
      'category': serializer.toJson<String>(category),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  StoredCategoryRule copyWith(
          {String? id, String? pattern, String? category, int? sortOrder}) =>
      StoredCategoryRule(
        id: id ?? this.id,
        pattern: pattern ?? this.pattern,
        category: category ?? this.category,
        sortOrder: sortOrder ?? this.sortOrder,
      );
  StoredCategoryRule copyWithCompanion(StoredCategoryRulesCompanion data) {
    return StoredCategoryRule(
      id: data.id.present ? data.id.value : this.id,
      pattern: data.pattern.present ? data.pattern.value : this.pattern,
      category: data.category.present ? data.category.value : this.category,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredCategoryRule(')
          ..write('id: $id, ')
          ..write('pattern: $pattern, ')
          ..write('category: $category, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, pattern, category, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredCategoryRule &&
          other.id == this.id &&
          other.pattern == this.pattern &&
          other.category == this.category &&
          other.sortOrder == this.sortOrder);
}

class StoredCategoryRulesCompanion extends UpdateCompanion<StoredCategoryRule> {
  final Value<String> id;
  final Value<String> pattern;
  final Value<String> category;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const StoredCategoryRulesCompanion({
    this.id = const Value.absent(),
    this.pattern = const Value.absent(),
    this.category = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredCategoryRulesCompanion.insert({
    required String id,
    required String pattern,
    required String category,
    required int sortOrder,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        pattern = Value(pattern),
        category = Value(category),
        sortOrder = Value(sortOrder);
  static Insertable<StoredCategoryRule> custom({
    Expression<String>? id,
    Expression<String>? pattern,
    Expression<String>? category,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (pattern != null) 'pattern': pattern,
      if (category != null) 'category': category,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredCategoryRulesCompanion copyWith(
      {Value<String>? id,
      Value<String>? pattern,
      Value<String>? category,
      Value<int>? sortOrder,
      Value<int>? rowid}) {
    return StoredCategoryRulesCompanion(
      id: id ?? this.id,
      pattern: pattern ?? this.pattern,
      category: category ?? this.category,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (pattern.present) {
      map['pattern'] = Variable<String>(pattern.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredCategoryRulesCompanion(')
          ..write('id: $id, ')
          ..write('pattern: $pattern, ')
          ..write('category: $category, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoredMatchesTable extends StoredMatches
    with TableInfo<$StoredMatchesTable, StoredMatche> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredMatchesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _monthKeyMeta =
      const VerificationMeta('monthKey');
  @override
  late final GeneratedColumn<String> monthKey = GeneratedColumn<String>(
      'month_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _appUuidMeta =
      const VerificationMeta('appUuid');
  @override
  late final GeneratedColumn<String> appUuid = GeneratedColumn<String>(
      'app_uuid', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _bankUuidMeta =
      const VerificationMeta('bankUuid');
  @override
  late final GeneratedColumn<String> bankUuid = GeneratedColumn<String>(
      'bank_uuid', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _tierMeta = const VerificationMeta('tier');
  @override
  late final GeneratedColumn<String> tier = GeneratedColumn<String>(
      'tier', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, monthKey, appUuid, bankUuid, tier];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_matches';
  @override
  VerificationContext validateIntegrity(Insertable<StoredMatche> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('month_key')) {
      context.handle(_monthKeyMeta,
          monthKey.isAcceptableOrUnknown(data['month_key']!, _monthKeyMeta));
    } else if (isInserting) {
      context.missing(_monthKeyMeta);
    }
    if (data.containsKey('app_uuid')) {
      context.handle(_appUuidMeta,
          appUuid.isAcceptableOrUnknown(data['app_uuid']!, _appUuidMeta));
    } else if (isInserting) {
      context.missing(_appUuidMeta);
    }
    if (data.containsKey('bank_uuid')) {
      context.handle(_bankUuidMeta,
          bankUuid.isAcceptableOrUnknown(data['bank_uuid']!, _bankUuidMeta));
    } else if (isInserting) {
      context.missing(_bankUuidMeta);
    }
    if (data.containsKey('tier')) {
      context.handle(
          _tierMeta, tier.isAcceptableOrUnknown(data['tier']!, _tierMeta));
    } else if (isInserting) {
      context.missing(_tierMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StoredMatche map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredMatche(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      monthKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}month_key'])!,
      appUuid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}app_uuid'])!,
      bankUuid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}bank_uuid'])!,
      tier: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tier'])!,
    );
  }

  @override
  $StoredMatchesTable createAlias(String alias) {
    return $StoredMatchesTable(attachedDatabase, alias);
  }
}

class StoredMatche extends DataClass implements Insertable<StoredMatche> {
  final String id;
  final String monthKey;
  final String appUuid;
  final String bankUuid;
  final String tier;
  const StoredMatche(
      {required this.id,
      required this.monthKey,
      required this.appUuid,
      required this.bankUuid,
      required this.tier});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['month_key'] = Variable<String>(monthKey);
    map['app_uuid'] = Variable<String>(appUuid);
    map['bank_uuid'] = Variable<String>(bankUuid);
    map['tier'] = Variable<String>(tier);
    return map;
  }

  StoredMatchesCompanion toCompanion(bool nullToAbsent) {
    return StoredMatchesCompanion(
      id: Value(id),
      monthKey: Value(monthKey),
      appUuid: Value(appUuid),
      bankUuid: Value(bankUuid),
      tier: Value(tier),
    );
  }

  factory StoredMatche.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredMatche(
      id: serializer.fromJson<String>(json['id']),
      monthKey: serializer.fromJson<String>(json['monthKey']),
      appUuid: serializer.fromJson<String>(json['appUuid']),
      bankUuid: serializer.fromJson<String>(json['bankUuid']),
      tier: serializer.fromJson<String>(json['tier']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'monthKey': serializer.toJson<String>(monthKey),
      'appUuid': serializer.toJson<String>(appUuid),
      'bankUuid': serializer.toJson<String>(bankUuid),
      'tier': serializer.toJson<String>(tier),
    };
  }

  StoredMatche copyWith(
          {String? id,
          String? monthKey,
          String? appUuid,
          String? bankUuid,
          String? tier}) =>
      StoredMatche(
        id: id ?? this.id,
        monthKey: monthKey ?? this.monthKey,
        appUuid: appUuid ?? this.appUuid,
        bankUuid: bankUuid ?? this.bankUuid,
        tier: tier ?? this.tier,
      );
  StoredMatche copyWithCompanion(StoredMatchesCompanion data) {
    return StoredMatche(
      id: data.id.present ? data.id.value : this.id,
      monthKey: data.monthKey.present ? data.monthKey.value : this.monthKey,
      appUuid: data.appUuid.present ? data.appUuid.value : this.appUuid,
      bankUuid: data.bankUuid.present ? data.bankUuid.value : this.bankUuid,
      tier: data.tier.present ? data.tier.value : this.tier,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredMatche(')
          ..write('id: $id, ')
          ..write('monthKey: $monthKey, ')
          ..write('appUuid: $appUuid, ')
          ..write('bankUuid: $bankUuid, ')
          ..write('tier: $tier')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, monthKey, appUuid, bankUuid, tier);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredMatche &&
          other.id == this.id &&
          other.monthKey == this.monthKey &&
          other.appUuid == this.appUuid &&
          other.bankUuid == this.bankUuid &&
          other.tier == this.tier);
}

class StoredMatchesCompanion extends UpdateCompanion<StoredMatche> {
  final Value<String> id;
  final Value<String> monthKey;
  final Value<String> appUuid;
  final Value<String> bankUuid;
  final Value<String> tier;
  final Value<int> rowid;
  const StoredMatchesCompanion({
    this.id = const Value.absent(),
    this.monthKey = const Value.absent(),
    this.appUuid = const Value.absent(),
    this.bankUuid = const Value.absent(),
    this.tier = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredMatchesCompanion.insert({
    required String id,
    required String monthKey,
    required String appUuid,
    required String bankUuid,
    required String tier,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        monthKey = Value(monthKey),
        appUuid = Value(appUuid),
        bankUuid = Value(bankUuid),
        tier = Value(tier);
  static Insertable<StoredMatche> custom({
    Expression<String>? id,
    Expression<String>? monthKey,
    Expression<String>? appUuid,
    Expression<String>? bankUuid,
    Expression<String>? tier,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (monthKey != null) 'month_key': monthKey,
      if (appUuid != null) 'app_uuid': appUuid,
      if (bankUuid != null) 'bank_uuid': bankUuid,
      if (tier != null) 'tier': tier,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredMatchesCompanion copyWith(
      {Value<String>? id,
      Value<String>? monthKey,
      Value<String>? appUuid,
      Value<String>? bankUuid,
      Value<String>? tier,
      Value<int>? rowid}) {
    return StoredMatchesCompanion(
      id: id ?? this.id,
      monthKey: monthKey ?? this.monthKey,
      appUuid: appUuid ?? this.appUuid,
      bankUuid: bankUuid ?? this.bankUuid,
      tier: tier ?? this.tier,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (monthKey.present) {
      map['month_key'] = Variable<String>(monthKey.value);
    }
    if (appUuid.present) {
      map['app_uuid'] = Variable<String>(appUuid.value);
    }
    if (bankUuid.present) {
      map['bank_uuid'] = Variable<String>(bankUuid.value);
    }
    if (tier.present) {
      map['tier'] = Variable<String>(tier.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredMatchesCompanion(')
          ..write('id: $id, ')
          ..write('monthKey: $monthKey, ')
          ..write('appUuid: $appUuid, ')
          ..write('bankUuid: $bankUuid, ')
          ..write('tier: $tier, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PinnedMonthsTable extends PinnedMonths
    with TableInfo<$PinnedMonthsTable, PinnedMonth> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PinnedMonthsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _monthKeyMeta =
      const VerificationMeta('monthKey');
  @override
  late final GeneratedColumn<String> monthKey = GeneratedColumn<String>(
      'month_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [monthKey];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pinned_months';
  @override
  VerificationContext validateIntegrity(Insertable<PinnedMonth> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('month_key')) {
      context.handle(_monthKeyMeta,
          monthKey.isAcceptableOrUnknown(data['month_key']!, _monthKeyMeta));
    } else if (isInserting) {
      context.missing(_monthKeyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {monthKey};
  @override
  PinnedMonth map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PinnedMonth(
      monthKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}month_key'])!,
    );
  }

  @override
  $PinnedMonthsTable createAlias(String alias) {
    return $PinnedMonthsTable(attachedDatabase, alias);
  }
}

class PinnedMonth extends DataClass implements Insertable<PinnedMonth> {
  final String monthKey;
  const PinnedMonth({required this.monthKey});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['month_key'] = Variable<String>(monthKey);
    return map;
  }

  PinnedMonthsCompanion toCompanion(bool nullToAbsent) {
    return PinnedMonthsCompanion(
      monthKey: Value(monthKey),
    );
  }

  factory PinnedMonth.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PinnedMonth(
      monthKey: serializer.fromJson<String>(json['monthKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'monthKey': serializer.toJson<String>(monthKey),
    };
  }

  PinnedMonth copyWith({String? monthKey}) => PinnedMonth(
        monthKey: monthKey ?? this.monthKey,
      );
  PinnedMonth copyWithCompanion(PinnedMonthsCompanion data) {
    return PinnedMonth(
      monthKey: data.monthKey.present ? data.monthKey.value : this.monthKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PinnedMonth(')
          ..write('monthKey: $monthKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => monthKey.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PinnedMonth && other.monthKey == this.monthKey);
}

class PinnedMonthsCompanion extends UpdateCompanion<PinnedMonth> {
  final Value<String> monthKey;
  final Value<int> rowid;
  const PinnedMonthsCompanion({
    this.monthKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PinnedMonthsCompanion.insert({
    required String monthKey,
    this.rowid = const Value.absent(),
  }) : monthKey = Value(monthKey);
  static Insertable<PinnedMonth> custom({
    Expression<String>? monthKey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (monthKey != null) 'month_key': monthKey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PinnedMonthsCompanion copyWith({Value<String>? monthKey, Value<int>? rowid}) {
    return PinnedMonthsCompanion(
      monthKey: monthKey ?? this.monthKey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (monthKey.present) {
      map['month_key'] = Variable<String>(monthKey.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PinnedMonthsCompanion(')
          ..write('monthKey: $monthKey, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoredPendingMemosTable extends StoredPendingMemos
    with TableInfo<$StoredPendingMemosTable, StoredPendingMemo> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredPendingMemosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _captureHashMeta =
      const VerificationMeta('captureHash');
  @override
  late final GeneratedColumn<String> captureHash = GeneratedColumn<String>(
      'capture_hash', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _amountPaiseMeta =
      const VerificationMeta('amountPaise');
  @override
  late final GeneratedColumn<int> amountPaise = GeneratedColumn<int>(
      'amount_paise', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _directionMeta =
      const VerificationMeta('direction');
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
      'direction', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payeeMeta = const VerificationMeta('payee');
  @override
  late final GeneratedColumn<String> payee = GeneratedColumn<String>(
      'payee', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payeeNormalizedMeta =
      const VerificationMeta('payeeNormalized');
  @override
  late final GeneratedColumn<String> payeeNormalized = GeneratedColumn<String>(
      'payee_normalized', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _vpaMeta = const VerificationMeta('vpa');
  @override
  late final GeneratedColumn<String> vpa = GeneratedColumn<String>(
      'vpa', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _accountTailMeta =
      const VerificationMeta('accountTail');
  @override
  late final GeneratedColumn<String> accountTail = GeneratedColumn<String>(
      'account_tail', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _dateMsMeta = const VerificationMeta('dateMs');
  @override
  late final GeneratedColumn<int> dateMs = GeneratedColumn<int>(
      'date_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _capturedAtMsMeta =
      const VerificationMeta('capturedAtMs');
  @override
  late final GeneratedColumn<int> capturedAtMs = GeneratedColumn<int>(
      'captured_at_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _assignedCategoryMeta =
      const VerificationMeta('assignedCategory');
  @override
  late final GeneratedColumn<String> assignedCategory = GeneratedColumn<String>(
      'assigned_category', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _mergedTxnUuidMeta =
      const VerificationMeta('mergedTxnUuid');
  @override
  late final GeneratedColumn<String> mergedTxnUuid = GeneratedColumn<String>(
      'merged_txn_uuid', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _notifiedAtMsMeta =
      const VerificationMeta('notifiedAtMs');
  @override
  late final GeneratedColumn<int> notifiedAtMs = GeneratedColumn<int>(
      'notified_at_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        captureHash,
        amountPaise,
        direction,
        payee,
        payeeNormalized,
        vpa,
        accountTail,
        dateMs,
        capturedAtMs,
        note,
        assignedCategory,
        mergedTxnUuid,
        notifiedAtMs
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_pending_memos';
  @override
  VerificationContext validateIntegrity(Insertable<StoredPendingMemo> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('capture_hash')) {
      context.handle(
          _captureHashMeta,
          captureHash.isAcceptableOrUnknown(
              data['capture_hash']!, _captureHashMeta));
    } else if (isInserting) {
      context.missing(_captureHashMeta);
    }
    if (data.containsKey('amount_paise')) {
      context.handle(
          _amountPaiseMeta,
          amountPaise.isAcceptableOrUnknown(
              data['amount_paise']!, _amountPaiseMeta));
    } else if (isInserting) {
      context.missing(_amountPaiseMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(_directionMeta,
          direction.isAcceptableOrUnknown(data['direction']!, _directionMeta));
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('payee')) {
      context.handle(
          _payeeMeta, payee.isAcceptableOrUnknown(data['payee']!, _payeeMeta));
    } else if (isInserting) {
      context.missing(_payeeMeta);
    }
    if (data.containsKey('payee_normalized')) {
      context.handle(
          _payeeNormalizedMeta,
          payeeNormalized.isAcceptableOrUnknown(
              data['payee_normalized']!, _payeeNormalizedMeta));
    } else if (isInserting) {
      context.missing(_payeeNormalizedMeta);
    }
    if (data.containsKey('vpa')) {
      context.handle(
          _vpaMeta, vpa.isAcceptableOrUnknown(data['vpa']!, _vpaMeta));
    }
    if (data.containsKey('account_tail')) {
      context.handle(
          _accountTailMeta,
          accountTail.isAcceptableOrUnknown(
              data['account_tail']!, _accountTailMeta));
    }
    if (data.containsKey('date_ms')) {
      context.handle(_dateMsMeta,
          dateMs.isAcceptableOrUnknown(data['date_ms']!, _dateMsMeta));
    } else if (isInserting) {
      context.missing(_dateMsMeta);
    }
    if (data.containsKey('captured_at_ms')) {
      context.handle(
          _capturedAtMsMeta,
          capturedAtMs.isAcceptableOrUnknown(
              data['captured_at_ms']!, _capturedAtMsMeta));
    } else if (isInserting) {
      context.missing(_capturedAtMsMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('assigned_category')) {
      context.handle(
          _assignedCategoryMeta,
          assignedCategory.isAcceptableOrUnknown(
              data['assigned_category']!, _assignedCategoryMeta));
    }
    if (data.containsKey('merged_txn_uuid')) {
      context.handle(
          _mergedTxnUuidMeta,
          mergedTxnUuid.isAcceptableOrUnknown(
              data['merged_txn_uuid']!, _mergedTxnUuidMeta));
    }
    if (data.containsKey('notified_at_ms')) {
      context.handle(
          _notifiedAtMsMeta,
          notifiedAtMs.isAcceptableOrUnknown(
              data['notified_at_ms']!, _notifiedAtMsMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {captureHash};
  @override
  StoredPendingMemo map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredPendingMemo(
      captureHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}capture_hash'])!,
      amountPaise: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}amount_paise'])!,
      direction: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}direction'])!,
      payee: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payee'])!,
      payeeNormalized: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}payee_normalized'])!,
      vpa: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}vpa']),
      accountTail: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}account_tail']),
      dateMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}date_ms'])!,
      capturedAtMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}captured_at_ms'])!,
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      assignedCategory: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}assigned_category']),
      mergedTxnUuid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}merged_txn_uuid']),
      notifiedAtMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}notified_at_ms']),
    );
  }

  @override
  $StoredPendingMemosTable createAlias(String alias) {
    return $StoredPendingMemosTable(attachedDatabase, alias);
  }
}

class StoredPendingMemo extends DataClass
    implements Insertable<StoredPendingMemo> {
  final String captureHash;
  final int amountPaise;
  final String direction;
  final String payee;
  final String payeeNormalized;
  final String? vpa;
  final String? accountTail;
  final int dateMs;
  final int capturedAtMs;
  final String? note;
  final String? assignedCategory;
  final String? mergedTxnUuid;
  final int? notifiedAtMs;
  const StoredPendingMemo(
      {required this.captureHash,
      required this.amountPaise,
      required this.direction,
      required this.payee,
      required this.payeeNormalized,
      this.vpa,
      this.accountTail,
      required this.dateMs,
      required this.capturedAtMs,
      this.note,
      this.assignedCategory,
      this.mergedTxnUuid,
      this.notifiedAtMs});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['capture_hash'] = Variable<String>(captureHash);
    map['amount_paise'] = Variable<int>(amountPaise);
    map['direction'] = Variable<String>(direction);
    map['payee'] = Variable<String>(payee);
    map['payee_normalized'] = Variable<String>(payeeNormalized);
    if (!nullToAbsent || vpa != null) {
      map['vpa'] = Variable<String>(vpa);
    }
    if (!nullToAbsent || accountTail != null) {
      map['account_tail'] = Variable<String>(accountTail);
    }
    map['date_ms'] = Variable<int>(dateMs);
    map['captured_at_ms'] = Variable<int>(capturedAtMs);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || assignedCategory != null) {
      map['assigned_category'] = Variable<String>(assignedCategory);
    }
    if (!nullToAbsent || mergedTxnUuid != null) {
      map['merged_txn_uuid'] = Variable<String>(mergedTxnUuid);
    }
    if (!nullToAbsent || notifiedAtMs != null) {
      map['notified_at_ms'] = Variable<int>(notifiedAtMs);
    }
    return map;
  }

  StoredPendingMemosCompanion toCompanion(bool nullToAbsent) {
    return StoredPendingMemosCompanion(
      captureHash: Value(captureHash),
      amountPaise: Value(amountPaise),
      direction: Value(direction),
      payee: Value(payee),
      payeeNormalized: Value(payeeNormalized),
      vpa: vpa == null && nullToAbsent ? const Value.absent() : Value(vpa),
      accountTail: accountTail == null && nullToAbsent
          ? const Value.absent()
          : Value(accountTail),
      dateMs: Value(dateMs),
      capturedAtMs: Value(capturedAtMs),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      assignedCategory: assignedCategory == null && nullToAbsent
          ? const Value.absent()
          : Value(assignedCategory),
      mergedTxnUuid: mergedTxnUuid == null && nullToAbsent
          ? const Value.absent()
          : Value(mergedTxnUuid),
      notifiedAtMs: notifiedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(notifiedAtMs),
    );
  }

  factory StoredPendingMemo.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredPendingMemo(
      captureHash: serializer.fromJson<String>(json['captureHash']),
      amountPaise: serializer.fromJson<int>(json['amountPaise']),
      direction: serializer.fromJson<String>(json['direction']),
      payee: serializer.fromJson<String>(json['payee']),
      payeeNormalized: serializer.fromJson<String>(json['payeeNormalized']),
      vpa: serializer.fromJson<String?>(json['vpa']),
      accountTail: serializer.fromJson<String?>(json['accountTail']),
      dateMs: serializer.fromJson<int>(json['dateMs']),
      capturedAtMs: serializer.fromJson<int>(json['capturedAtMs']),
      note: serializer.fromJson<String?>(json['note']),
      assignedCategory: serializer.fromJson<String?>(json['assignedCategory']),
      mergedTxnUuid: serializer.fromJson<String?>(json['mergedTxnUuid']),
      notifiedAtMs: serializer.fromJson<int?>(json['notifiedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'captureHash': serializer.toJson<String>(captureHash),
      'amountPaise': serializer.toJson<int>(amountPaise),
      'direction': serializer.toJson<String>(direction),
      'payee': serializer.toJson<String>(payee),
      'payeeNormalized': serializer.toJson<String>(payeeNormalized),
      'vpa': serializer.toJson<String?>(vpa),
      'accountTail': serializer.toJson<String?>(accountTail),
      'dateMs': serializer.toJson<int>(dateMs),
      'capturedAtMs': serializer.toJson<int>(capturedAtMs),
      'note': serializer.toJson<String?>(note),
      'assignedCategory': serializer.toJson<String?>(assignedCategory),
      'mergedTxnUuid': serializer.toJson<String?>(mergedTxnUuid),
      'notifiedAtMs': serializer.toJson<int?>(notifiedAtMs),
    };
  }

  StoredPendingMemo copyWith(
          {String? captureHash,
          int? amountPaise,
          String? direction,
          String? payee,
          String? payeeNormalized,
          Value<String?> vpa = const Value.absent(),
          Value<String?> accountTail = const Value.absent(),
          int? dateMs,
          int? capturedAtMs,
          Value<String?> note = const Value.absent(),
          Value<String?> assignedCategory = const Value.absent(),
          Value<String?> mergedTxnUuid = const Value.absent(),
          Value<int?> notifiedAtMs = const Value.absent()}) =>
      StoredPendingMemo(
        captureHash: captureHash ?? this.captureHash,
        amountPaise: amountPaise ?? this.amountPaise,
        direction: direction ?? this.direction,
        payee: payee ?? this.payee,
        payeeNormalized: payeeNormalized ?? this.payeeNormalized,
        vpa: vpa.present ? vpa.value : this.vpa,
        accountTail: accountTail.present ? accountTail.value : this.accountTail,
        dateMs: dateMs ?? this.dateMs,
        capturedAtMs: capturedAtMs ?? this.capturedAtMs,
        note: note.present ? note.value : this.note,
        assignedCategory: assignedCategory.present
            ? assignedCategory.value
            : this.assignedCategory,
        mergedTxnUuid:
            mergedTxnUuid.present ? mergedTxnUuid.value : this.mergedTxnUuid,
        notifiedAtMs:
            notifiedAtMs.present ? notifiedAtMs.value : this.notifiedAtMs,
      );
  StoredPendingMemo copyWithCompanion(StoredPendingMemosCompanion data) {
    return StoredPendingMemo(
      captureHash:
          data.captureHash.present ? data.captureHash.value : this.captureHash,
      amountPaise:
          data.amountPaise.present ? data.amountPaise.value : this.amountPaise,
      direction: data.direction.present ? data.direction.value : this.direction,
      payee: data.payee.present ? data.payee.value : this.payee,
      payeeNormalized: data.payeeNormalized.present
          ? data.payeeNormalized.value
          : this.payeeNormalized,
      vpa: data.vpa.present ? data.vpa.value : this.vpa,
      accountTail:
          data.accountTail.present ? data.accountTail.value : this.accountTail,
      dateMs: data.dateMs.present ? data.dateMs.value : this.dateMs,
      capturedAtMs: data.capturedAtMs.present
          ? data.capturedAtMs.value
          : this.capturedAtMs,
      note: data.note.present ? data.note.value : this.note,
      assignedCategory: data.assignedCategory.present
          ? data.assignedCategory.value
          : this.assignedCategory,
      mergedTxnUuid: data.mergedTxnUuid.present
          ? data.mergedTxnUuid.value
          : this.mergedTxnUuid,
      notifiedAtMs: data.notifiedAtMs.present
          ? data.notifiedAtMs.value
          : this.notifiedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredPendingMemo(')
          ..write('captureHash: $captureHash, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('direction: $direction, ')
          ..write('payee: $payee, ')
          ..write('payeeNormalized: $payeeNormalized, ')
          ..write('vpa: $vpa, ')
          ..write('accountTail: $accountTail, ')
          ..write('dateMs: $dateMs, ')
          ..write('capturedAtMs: $capturedAtMs, ')
          ..write('note: $note, ')
          ..write('assignedCategory: $assignedCategory, ')
          ..write('mergedTxnUuid: $mergedTxnUuid, ')
          ..write('notifiedAtMs: $notifiedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      captureHash,
      amountPaise,
      direction,
      payee,
      payeeNormalized,
      vpa,
      accountTail,
      dateMs,
      capturedAtMs,
      note,
      assignedCategory,
      mergedTxnUuid,
      notifiedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredPendingMemo &&
          other.captureHash == this.captureHash &&
          other.amountPaise == this.amountPaise &&
          other.direction == this.direction &&
          other.payee == this.payee &&
          other.payeeNormalized == this.payeeNormalized &&
          other.vpa == this.vpa &&
          other.accountTail == this.accountTail &&
          other.dateMs == this.dateMs &&
          other.capturedAtMs == this.capturedAtMs &&
          other.note == this.note &&
          other.assignedCategory == this.assignedCategory &&
          other.mergedTxnUuid == this.mergedTxnUuid &&
          other.notifiedAtMs == this.notifiedAtMs);
}

class StoredPendingMemosCompanion extends UpdateCompanion<StoredPendingMemo> {
  final Value<String> captureHash;
  final Value<int> amountPaise;
  final Value<String> direction;
  final Value<String> payee;
  final Value<String> payeeNormalized;
  final Value<String?> vpa;
  final Value<String?> accountTail;
  final Value<int> dateMs;
  final Value<int> capturedAtMs;
  final Value<String?> note;
  final Value<String?> assignedCategory;
  final Value<String?> mergedTxnUuid;
  final Value<int?> notifiedAtMs;
  final Value<int> rowid;
  const StoredPendingMemosCompanion({
    this.captureHash = const Value.absent(),
    this.amountPaise = const Value.absent(),
    this.direction = const Value.absent(),
    this.payee = const Value.absent(),
    this.payeeNormalized = const Value.absent(),
    this.vpa = const Value.absent(),
    this.accountTail = const Value.absent(),
    this.dateMs = const Value.absent(),
    this.capturedAtMs = const Value.absent(),
    this.note = const Value.absent(),
    this.assignedCategory = const Value.absent(),
    this.mergedTxnUuid = const Value.absent(),
    this.notifiedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredPendingMemosCompanion.insert({
    required String captureHash,
    required int amountPaise,
    required String direction,
    required String payee,
    required String payeeNormalized,
    this.vpa = const Value.absent(),
    this.accountTail = const Value.absent(),
    required int dateMs,
    required int capturedAtMs,
    this.note = const Value.absent(),
    this.assignedCategory = const Value.absent(),
    this.mergedTxnUuid = const Value.absent(),
    this.notifiedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : captureHash = Value(captureHash),
        amountPaise = Value(amountPaise),
        direction = Value(direction),
        payee = Value(payee),
        payeeNormalized = Value(payeeNormalized),
        dateMs = Value(dateMs),
        capturedAtMs = Value(capturedAtMs);
  static Insertable<StoredPendingMemo> custom({
    Expression<String>? captureHash,
    Expression<int>? amountPaise,
    Expression<String>? direction,
    Expression<String>? payee,
    Expression<String>? payeeNormalized,
    Expression<String>? vpa,
    Expression<String>? accountTail,
    Expression<int>? dateMs,
    Expression<int>? capturedAtMs,
    Expression<String>? note,
    Expression<String>? assignedCategory,
    Expression<String>? mergedTxnUuid,
    Expression<int>? notifiedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (captureHash != null) 'capture_hash': captureHash,
      if (amountPaise != null) 'amount_paise': amountPaise,
      if (direction != null) 'direction': direction,
      if (payee != null) 'payee': payee,
      if (payeeNormalized != null) 'payee_normalized': payeeNormalized,
      if (vpa != null) 'vpa': vpa,
      if (accountTail != null) 'account_tail': accountTail,
      if (dateMs != null) 'date_ms': dateMs,
      if (capturedAtMs != null) 'captured_at_ms': capturedAtMs,
      if (note != null) 'note': note,
      if (assignedCategory != null) 'assigned_category': assignedCategory,
      if (mergedTxnUuid != null) 'merged_txn_uuid': mergedTxnUuid,
      if (notifiedAtMs != null) 'notified_at_ms': notifiedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredPendingMemosCompanion copyWith(
      {Value<String>? captureHash,
      Value<int>? amountPaise,
      Value<String>? direction,
      Value<String>? payee,
      Value<String>? payeeNormalized,
      Value<String?>? vpa,
      Value<String?>? accountTail,
      Value<int>? dateMs,
      Value<int>? capturedAtMs,
      Value<String?>? note,
      Value<String?>? assignedCategory,
      Value<String?>? mergedTxnUuid,
      Value<int?>? notifiedAtMs,
      Value<int>? rowid}) {
    return StoredPendingMemosCompanion(
      captureHash: captureHash ?? this.captureHash,
      amountPaise: amountPaise ?? this.amountPaise,
      direction: direction ?? this.direction,
      payee: payee ?? this.payee,
      payeeNormalized: payeeNormalized ?? this.payeeNormalized,
      vpa: vpa ?? this.vpa,
      accountTail: accountTail ?? this.accountTail,
      dateMs: dateMs ?? this.dateMs,
      capturedAtMs: capturedAtMs ?? this.capturedAtMs,
      note: note ?? this.note,
      assignedCategory: assignedCategory ?? this.assignedCategory,
      mergedTxnUuid: mergedTxnUuid ?? this.mergedTxnUuid,
      notifiedAtMs: notifiedAtMs ?? this.notifiedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (captureHash.present) {
      map['capture_hash'] = Variable<String>(captureHash.value);
    }
    if (amountPaise.present) {
      map['amount_paise'] = Variable<int>(amountPaise.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (payee.present) {
      map['payee'] = Variable<String>(payee.value);
    }
    if (payeeNormalized.present) {
      map['payee_normalized'] = Variable<String>(payeeNormalized.value);
    }
    if (vpa.present) {
      map['vpa'] = Variable<String>(vpa.value);
    }
    if (accountTail.present) {
      map['account_tail'] = Variable<String>(accountTail.value);
    }
    if (dateMs.present) {
      map['date_ms'] = Variable<int>(dateMs.value);
    }
    if (capturedAtMs.present) {
      map['captured_at_ms'] = Variable<int>(capturedAtMs.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (assignedCategory.present) {
      map['assigned_category'] = Variable<String>(assignedCategory.value);
    }
    if (mergedTxnUuid.present) {
      map['merged_txn_uuid'] = Variable<String>(mergedTxnUuid.value);
    }
    if (notifiedAtMs.present) {
      map['notified_at_ms'] = Variable<int>(notifiedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredPendingMemosCompanion(')
          ..write('captureHash: $captureHash, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('direction: $direction, ')
          ..write('payee: $payee, ')
          ..write('payeeNormalized: $payeeNormalized, ')
          ..write('vpa: $vpa, ')
          ..write('accountTail: $accountTail, ')
          ..write('dateMs: $dateMs, ')
          ..write('capturedAtMs: $capturedAtMs, ')
          ..write('note: $note, ')
          ..write('assignedCategory: $assignedCategory, ')
          ..write('mergedTxnUuid: $mergedTxnUuid, ')
          ..write('notifiedAtMs: $notifiedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $StoredDocumentsTable storedDocuments =
      $StoredDocumentsTable(this);
  late final $StoredTransactionsTable storedTransactions =
      $StoredTransactionsTable(this);
  late final $StoredCategoryRulesTable storedCategoryRules =
      $StoredCategoryRulesTable(this);
  late final $StoredMatchesTable storedMatches = $StoredMatchesTable(this);
  late final $PinnedMonthsTable pinnedMonths = $PinnedMonthsTable(this);
  late final $StoredPendingMemosTable storedPendingMemos =
      $StoredPendingMemosTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        storedDocuments,
        storedTransactions,
        storedCategoryRules,
        storedMatches,
        pinnedMonths,
        storedPendingMemos
      ];
}

typedef $$StoredDocumentsTableCreateCompanionBuilder = StoredDocumentsCompanion
    Function({
  required String id,
  required String sourceRaw,
  required String filename,
  required String fileSha256,
  required int periodStartMs,
  required int periodEndMs,
  Value<int> rowid,
});
typedef $$StoredDocumentsTableUpdateCompanionBuilder = StoredDocumentsCompanion
    Function({
  Value<String> id,
  Value<String> sourceRaw,
  Value<String> filename,
  Value<String> fileSha256,
  Value<int> periodStartMs,
  Value<int> periodEndMs,
  Value<int> rowid,
});

class $$StoredDocumentsTableFilterComposer
    extends Composer<_$AppDatabase, $StoredDocumentsTable> {
  $$StoredDocumentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceRaw => $composableBuilder(
      column: $table.sourceRaw, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get filename => $composableBuilder(
      column: $table.filename, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fileSha256 => $composableBuilder(
      column: $table.fileSha256, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get periodStartMs => $composableBuilder(
      column: $table.periodStartMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get periodEndMs => $composableBuilder(
      column: $table.periodEndMs, builder: (column) => ColumnFilters(column));
}

class $$StoredDocumentsTableOrderingComposer
    extends Composer<_$AppDatabase, $StoredDocumentsTable> {
  $$StoredDocumentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceRaw => $composableBuilder(
      column: $table.sourceRaw, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get filename => $composableBuilder(
      column: $table.filename, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fileSha256 => $composableBuilder(
      column: $table.fileSha256, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get periodStartMs => $composableBuilder(
      column: $table.periodStartMs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get periodEndMs => $composableBuilder(
      column: $table.periodEndMs, builder: (column) => ColumnOrderings(column));
}

class $$StoredDocumentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $StoredDocumentsTable> {
  $$StoredDocumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceRaw =>
      $composableBuilder(column: $table.sourceRaw, builder: (column) => column);

  GeneratedColumn<String> get filename =>
      $composableBuilder(column: $table.filename, builder: (column) => column);

  GeneratedColumn<String> get fileSha256 => $composableBuilder(
      column: $table.fileSha256, builder: (column) => column);

  GeneratedColumn<int> get periodStartMs => $composableBuilder(
      column: $table.periodStartMs, builder: (column) => column);

  GeneratedColumn<int> get periodEndMs => $composableBuilder(
      column: $table.periodEndMs, builder: (column) => column);
}

class $$StoredDocumentsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $StoredDocumentsTable,
    StoredDocument,
    $$StoredDocumentsTableFilterComposer,
    $$StoredDocumentsTableOrderingComposer,
    $$StoredDocumentsTableAnnotationComposer,
    $$StoredDocumentsTableCreateCompanionBuilder,
    $$StoredDocumentsTableUpdateCompanionBuilder,
    (
      StoredDocument,
      BaseReferences<_$AppDatabase, $StoredDocumentsTable, StoredDocument>
    ),
    StoredDocument,
    PrefetchHooks Function()> {
  $$StoredDocumentsTableTableManager(
      _$AppDatabase db, $StoredDocumentsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredDocumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredDocumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredDocumentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> sourceRaw = const Value.absent(),
            Value<String> filename = const Value.absent(),
            Value<String> fileSha256 = const Value.absent(),
            Value<int> periodStartMs = const Value.absent(),
            Value<int> periodEndMs = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              StoredDocumentsCompanion(
            id: id,
            sourceRaw: sourceRaw,
            filename: filename,
            fileSha256: fileSha256,
            periodStartMs: periodStartMs,
            periodEndMs: periodEndMs,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String sourceRaw,
            required String filename,
            required String fileSha256,
            required int periodStartMs,
            required int periodEndMs,
            Value<int> rowid = const Value.absent(),
          }) =>
              StoredDocumentsCompanion.insert(
            id: id,
            sourceRaw: sourceRaw,
            filename: filename,
            fileSha256: fileSha256,
            periodStartMs: periodStartMs,
            periodEndMs: periodEndMs,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$StoredDocumentsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $StoredDocumentsTable,
    StoredDocument,
    $$StoredDocumentsTableFilterComposer,
    $$StoredDocumentsTableOrderingComposer,
    $$StoredDocumentsTableAnnotationComposer,
    $$StoredDocumentsTableCreateCompanionBuilder,
    $$StoredDocumentsTableUpdateCompanionBuilder,
    (
      StoredDocument,
      BaseReferences<_$AppDatabase, $StoredDocumentsTable, StoredDocument>
    ),
    StoredDocument,
    PrefetchHooks Function()>;
typedef $$StoredTransactionsTableCreateCompanionBuilder
    = StoredTransactionsCompanion Function({
  required String uuid,
  required String contentHash,
  required String sourceRaw,
  required int dateMs,
  required int amountPaise,
  required String direction,
  required String counterparty,
  Value<String?> reference,
  required String narration,
  Value<String?> categoryOverride,
  required String documentId,
  Value<int> rowid,
});
typedef $$StoredTransactionsTableUpdateCompanionBuilder
    = StoredTransactionsCompanion Function({
  Value<String> uuid,
  Value<String> contentHash,
  Value<String> sourceRaw,
  Value<int> dateMs,
  Value<int> amountPaise,
  Value<String> direction,
  Value<String> counterparty,
  Value<String?> reference,
  Value<String> narration,
  Value<String?> categoryOverride,
  Value<String> documentId,
  Value<int> rowid,
});

class $$StoredTransactionsTableFilterComposer
    extends Composer<_$AppDatabase, $StoredTransactionsTable> {
  $$StoredTransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get uuid => $composableBuilder(
      column: $table.uuid, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get contentHash => $composableBuilder(
      column: $table.contentHash, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceRaw => $composableBuilder(
      column: $table.sourceRaw, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get dateMs => $composableBuilder(
      column: $table.dateMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get amountPaise => $composableBuilder(
      column: $table.amountPaise, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get direction => $composableBuilder(
      column: $table.direction, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get counterparty => $composableBuilder(
      column: $table.counterparty, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get reference => $composableBuilder(
      column: $table.reference, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get narration => $composableBuilder(
      column: $table.narration, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get categoryOverride => $composableBuilder(
      column: $table.categoryOverride,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get documentId => $composableBuilder(
      column: $table.documentId, builder: (column) => ColumnFilters(column));
}

class $$StoredTransactionsTableOrderingComposer
    extends Composer<_$AppDatabase, $StoredTransactionsTable> {
  $$StoredTransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get uuid => $composableBuilder(
      column: $table.uuid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get contentHash => $composableBuilder(
      column: $table.contentHash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceRaw => $composableBuilder(
      column: $table.sourceRaw, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get dateMs => $composableBuilder(
      column: $table.dateMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get amountPaise => $composableBuilder(
      column: $table.amountPaise, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get direction => $composableBuilder(
      column: $table.direction, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get counterparty => $composableBuilder(
      column: $table.counterparty,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get reference => $composableBuilder(
      column: $table.reference, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get narration => $composableBuilder(
      column: $table.narration, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get categoryOverride => $composableBuilder(
      column: $table.categoryOverride,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get documentId => $composableBuilder(
      column: $table.documentId, builder: (column) => ColumnOrderings(column));
}

class $$StoredTransactionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $StoredTransactionsTable> {
  $$StoredTransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<String> get contentHash => $composableBuilder(
      column: $table.contentHash, builder: (column) => column);

  GeneratedColumn<String> get sourceRaw =>
      $composableBuilder(column: $table.sourceRaw, builder: (column) => column);

  GeneratedColumn<int> get dateMs =>
      $composableBuilder(column: $table.dateMs, builder: (column) => column);

  GeneratedColumn<int> get amountPaise => $composableBuilder(
      column: $table.amountPaise, builder: (column) => column);

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get counterparty => $composableBuilder(
      column: $table.counterparty, builder: (column) => column);

  GeneratedColumn<String> get reference =>
      $composableBuilder(column: $table.reference, builder: (column) => column);

  GeneratedColumn<String> get narration =>
      $composableBuilder(column: $table.narration, builder: (column) => column);

  GeneratedColumn<String> get categoryOverride => $composableBuilder(
      column: $table.categoryOverride, builder: (column) => column);

  GeneratedColumn<String> get documentId => $composableBuilder(
      column: $table.documentId, builder: (column) => column);
}

class $$StoredTransactionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $StoredTransactionsTable,
    StoredTransaction,
    $$StoredTransactionsTableFilterComposer,
    $$StoredTransactionsTableOrderingComposer,
    $$StoredTransactionsTableAnnotationComposer,
    $$StoredTransactionsTableCreateCompanionBuilder,
    $$StoredTransactionsTableUpdateCompanionBuilder,
    (
      StoredTransaction,
      BaseReferences<_$AppDatabase, $StoredTransactionsTable, StoredTransaction>
    ),
    StoredTransaction,
    PrefetchHooks Function()> {
  $$StoredTransactionsTableTableManager(
      _$AppDatabase db, $StoredTransactionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredTransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredTransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredTransactionsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> uuid = const Value.absent(),
            Value<String> contentHash = const Value.absent(),
            Value<String> sourceRaw = const Value.absent(),
            Value<int> dateMs = const Value.absent(),
            Value<int> amountPaise = const Value.absent(),
            Value<String> direction = const Value.absent(),
            Value<String> counterparty = const Value.absent(),
            Value<String?> reference = const Value.absent(),
            Value<String> narration = const Value.absent(),
            Value<String?> categoryOverride = const Value.absent(),
            Value<String> documentId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              StoredTransactionsCompanion(
            uuid: uuid,
            contentHash: contentHash,
            sourceRaw: sourceRaw,
            dateMs: dateMs,
            amountPaise: amountPaise,
            direction: direction,
            counterparty: counterparty,
            reference: reference,
            narration: narration,
            categoryOverride: categoryOverride,
            documentId: documentId,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String uuid,
            required String contentHash,
            required String sourceRaw,
            required int dateMs,
            required int amountPaise,
            required String direction,
            required String counterparty,
            Value<String?> reference = const Value.absent(),
            required String narration,
            Value<String?> categoryOverride = const Value.absent(),
            required String documentId,
            Value<int> rowid = const Value.absent(),
          }) =>
              StoredTransactionsCompanion.insert(
            uuid: uuid,
            contentHash: contentHash,
            sourceRaw: sourceRaw,
            dateMs: dateMs,
            amountPaise: amountPaise,
            direction: direction,
            counterparty: counterparty,
            reference: reference,
            narration: narration,
            categoryOverride: categoryOverride,
            documentId: documentId,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$StoredTransactionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $StoredTransactionsTable,
    StoredTransaction,
    $$StoredTransactionsTableFilterComposer,
    $$StoredTransactionsTableOrderingComposer,
    $$StoredTransactionsTableAnnotationComposer,
    $$StoredTransactionsTableCreateCompanionBuilder,
    $$StoredTransactionsTableUpdateCompanionBuilder,
    (
      StoredTransaction,
      BaseReferences<_$AppDatabase, $StoredTransactionsTable, StoredTransaction>
    ),
    StoredTransaction,
    PrefetchHooks Function()>;
typedef $$StoredCategoryRulesTableCreateCompanionBuilder
    = StoredCategoryRulesCompanion Function({
  required String id,
  required String pattern,
  required String category,
  required int sortOrder,
  Value<int> rowid,
});
typedef $$StoredCategoryRulesTableUpdateCompanionBuilder
    = StoredCategoryRulesCompanion Function({
  Value<String> id,
  Value<String> pattern,
  Value<String> category,
  Value<int> sortOrder,
  Value<int> rowid,
});

class $$StoredCategoryRulesTableFilterComposer
    extends Composer<_$AppDatabase, $StoredCategoryRulesTable> {
  $$StoredCategoryRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pattern => $composableBuilder(
      column: $table.pattern, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));
}

class $$StoredCategoryRulesTableOrderingComposer
    extends Composer<_$AppDatabase, $StoredCategoryRulesTable> {
  $$StoredCategoryRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pattern => $composableBuilder(
      column: $table.pattern, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));
}

class $$StoredCategoryRulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $StoredCategoryRulesTable> {
  $$StoredCategoryRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get pattern =>
      $composableBuilder(column: $table.pattern, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$StoredCategoryRulesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $StoredCategoryRulesTable,
    StoredCategoryRule,
    $$StoredCategoryRulesTableFilterComposer,
    $$StoredCategoryRulesTableOrderingComposer,
    $$StoredCategoryRulesTableAnnotationComposer,
    $$StoredCategoryRulesTableCreateCompanionBuilder,
    $$StoredCategoryRulesTableUpdateCompanionBuilder,
    (
      StoredCategoryRule,
      BaseReferences<_$AppDatabase, $StoredCategoryRulesTable,
          StoredCategoryRule>
    ),
    StoredCategoryRule,
    PrefetchHooks Function()> {
  $$StoredCategoryRulesTableTableManager(
      _$AppDatabase db, $StoredCategoryRulesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredCategoryRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredCategoryRulesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredCategoryRulesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> pattern = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              StoredCategoryRulesCompanion(
            id: id,
            pattern: pattern,
            category: category,
            sortOrder: sortOrder,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String pattern,
            required String category,
            required int sortOrder,
            Value<int> rowid = const Value.absent(),
          }) =>
              StoredCategoryRulesCompanion.insert(
            id: id,
            pattern: pattern,
            category: category,
            sortOrder: sortOrder,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$StoredCategoryRulesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $StoredCategoryRulesTable,
    StoredCategoryRule,
    $$StoredCategoryRulesTableFilterComposer,
    $$StoredCategoryRulesTableOrderingComposer,
    $$StoredCategoryRulesTableAnnotationComposer,
    $$StoredCategoryRulesTableCreateCompanionBuilder,
    $$StoredCategoryRulesTableUpdateCompanionBuilder,
    (
      StoredCategoryRule,
      BaseReferences<_$AppDatabase, $StoredCategoryRulesTable,
          StoredCategoryRule>
    ),
    StoredCategoryRule,
    PrefetchHooks Function()>;
typedef $$StoredMatchesTableCreateCompanionBuilder = StoredMatchesCompanion
    Function({
  required String id,
  required String monthKey,
  required String appUuid,
  required String bankUuid,
  required String tier,
  Value<int> rowid,
});
typedef $$StoredMatchesTableUpdateCompanionBuilder = StoredMatchesCompanion
    Function({
  Value<String> id,
  Value<String> monthKey,
  Value<String> appUuid,
  Value<String> bankUuid,
  Value<String> tier,
  Value<int> rowid,
});

class $$StoredMatchesTableFilterComposer
    extends Composer<_$AppDatabase, $StoredMatchesTable> {
  $$StoredMatchesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get monthKey => $composableBuilder(
      column: $table.monthKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get appUuid => $composableBuilder(
      column: $table.appUuid, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get bankUuid => $composableBuilder(
      column: $table.bankUuid, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tier => $composableBuilder(
      column: $table.tier, builder: (column) => ColumnFilters(column));
}

class $$StoredMatchesTableOrderingComposer
    extends Composer<_$AppDatabase, $StoredMatchesTable> {
  $$StoredMatchesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get monthKey => $composableBuilder(
      column: $table.monthKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get appUuid => $composableBuilder(
      column: $table.appUuid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get bankUuid => $composableBuilder(
      column: $table.bankUuid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tier => $composableBuilder(
      column: $table.tier, builder: (column) => ColumnOrderings(column));
}

class $$StoredMatchesTableAnnotationComposer
    extends Composer<_$AppDatabase, $StoredMatchesTable> {
  $$StoredMatchesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get monthKey =>
      $composableBuilder(column: $table.monthKey, builder: (column) => column);

  GeneratedColumn<String> get appUuid =>
      $composableBuilder(column: $table.appUuid, builder: (column) => column);

  GeneratedColumn<String> get bankUuid =>
      $composableBuilder(column: $table.bankUuid, builder: (column) => column);

  GeneratedColumn<String> get tier =>
      $composableBuilder(column: $table.tier, builder: (column) => column);
}

class $$StoredMatchesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $StoredMatchesTable,
    StoredMatche,
    $$StoredMatchesTableFilterComposer,
    $$StoredMatchesTableOrderingComposer,
    $$StoredMatchesTableAnnotationComposer,
    $$StoredMatchesTableCreateCompanionBuilder,
    $$StoredMatchesTableUpdateCompanionBuilder,
    (
      StoredMatche,
      BaseReferences<_$AppDatabase, $StoredMatchesTable, StoredMatche>
    ),
    StoredMatche,
    PrefetchHooks Function()> {
  $$StoredMatchesTableTableManager(_$AppDatabase db, $StoredMatchesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredMatchesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredMatchesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredMatchesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> monthKey = const Value.absent(),
            Value<String> appUuid = const Value.absent(),
            Value<String> bankUuid = const Value.absent(),
            Value<String> tier = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              StoredMatchesCompanion(
            id: id,
            monthKey: monthKey,
            appUuid: appUuid,
            bankUuid: bankUuid,
            tier: tier,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String monthKey,
            required String appUuid,
            required String bankUuid,
            required String tier,
            Value<int> rowid = const Value.absent(),
          }) =>
              StoredMatchesCompanion.insert(
            id: id,
            monthKey: monthKey,
            appUuid: appUuid,
            bankUuid: bankUuid,
            tier: tier,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$StoredMatchesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $StoredMatchesTable,
    StoredMatche,
    $$StoredMatchesTableFilterComposer,
    $$StoredMatchesTableOrderingComposer,
    $$StoredMatchesTableAnnotationComposer,
    $$StoredMatchesTableCreateCompanionBuilder,
    $$StoredMatchesTableUpdateCompanionBuilder,
    (
      StoredMatche,
      BaseReferences<_$AppDatabase, $StoredMatchesTable, StoredMatche>
    ),
    StoredMatche,
    PrefetchHooks Function()>;
typedef $$PinnedMonthsTableCreateCompanionBuilder = PinnedMonthsCompanion
    Function({
  required String monthKey,
  Value<int> rowid,
});
typedef $$PinnedMonthsTableUpdateCompanionBuilder = PinnedMonthsCompanion
    Function({
  Value<String> monthKey,
  Value<int> rowid,
});

class $$PinnedMonthsTableFilterComposer
    extends Composer<_$AppDatabase, $PinnedMonthsTable> {
  $$PinnedMonthsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get monthKey => $composableBuilder(
      column: $table.monthKey, builder: (column) => ColumnFilters(column));
}

class $$PinnedMonthsTableOrderingComposer
    extends Composer<_$AppDatabase, $PinnedMonthsTable> {
  $$PinnedMonthsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get monthKey => $composableBuilder(
      column: $table.monthKey, builder: (column) => ColumnOrderings(column));
}

class $$PinnedMonthsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PinnedMonthsTable> {
  $$PinnedMonthsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get monthKey =>
      $composableBuilder(column: $table.monthKey, builder: (column) => column);
}

class $$PinnedMonthsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PinnedMonthsTable,
    PinnedMonth,
    $$PinnedMonthsTableFilterComposer,
    $$PinnedMonthsTableOrderingComposer,
    $$PinnedMonthsTableAnnotationComposer,
    $$PinnedMonthsTableCreateCompanionBuilder,
    $$PinnedMonthsTableUpdateCompanionBuilder,
    (
      PinnedMonth,
      BaseReferences<_$AppDatabase, $PinnedMonthsTable, PinnedMonth>
    ),
    PinnedMonth,
    PrefetchHooks Function()> {
  $$PinnedMonthsTableTableManager(_$AppDatabase db, $PinnedMonthsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PinnedMonthsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PinnedMonthsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PinnedMonthsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> monthKey = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PinnedMonthsCompanion(
            monthKey: monthKey,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String monthKey,
            Value<int> rowid = const Value.absent(),
          }) =>
              PinnedMonthsCompanion.insert(
            monthKey: monthKey,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PinnedMonthsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PinnedMonthsTable,
    PinnedMonth,
    $$PinnedMonthsTableFilterComposer,
    $$PinnedMonthsTableOrderingComposer,
    $$PinnedMonthsTableAnnotationComposer,
    $$PinnedMonthsTableCreateCompanionBuilder,
    $$PinnedMonthsTableUpdateCompanionBuilder,
    (
      PinnedMonth,
      BaseReferences<_$AppDatabase, $PinnedMonthsTable, PinnedMonth>
    ),
    PinnedMonth,
    PrefetchHooks Function()>;
typedef $$StoredPendingMemosTableCreateCompanionBuilder
    = StoredPendingMemosCompanion Function({
  required String captureHash,
  required int amountPaise,
  required String direction,
  required String payee,
  required String payeeNormalized,
  Value<String?> vpa,
  Value<String?> accountTail,
  required int dateMs,
  required int capturedAtMs,
  Value<String?> note,
  Value<String?> assignedCategory,
  Value<String?> mergedTxnUuid,
  Value<int?> notifiedAtMs,
  Value<int> rowid,
});
typedef $$StoredPendingMemosTableUpdateCompanionBuilder
    = StoredPendingMemosCompanion Function({
  Value<String> captureHash,
  Value<int> amountPaise,
  Value<String> direction,
  Value<String> payee,
  Value<String> payeeNormalized,
  Value<String?> vpa,
  Value<String?> accountTail,
  Value<int> dateMs,
  Value<int> capturedAtMs,
  Value<String?> note,
  Value<String?> assignedCategory,
  Value<String?> mergedTxnUuid,
  Value<int?> notifiedAtMs,
  Value<int> rowid,
});

class $$StoredPendingMemosTableFilterComposer
    extends Composer<_$AppDatabase, $StoredPendingMemosTable> {
  $$StoredPendingMemosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get captureHash => $composableBuilder(
      column: $table.captureHash, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get amountPaise => $composableBuilder(
      column: $table.amountPaise, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get direction => $composableBuilder(
      column: $table.direction, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payee => $composableBuilder(
      column: $table.payee, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payeeNormalized => $composableBuilder(
      column: $table.payeeNormalized,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get vpa => $composableBuilder(
      column: $table.vpa, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get accountTail => $composableBuilder(
      column: $table.accountTail, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get dateMs => $composableBuilder(
      column: $table.dateMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get capturedAtMs => $composableBuilder(
      column: $table.capturedAtMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get assignedCategory => $composableBuilder(
      column: $table.assignedCategory,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mergedTxnUuid => $composableBuilder(
      column: $table.mergedTxnUuid, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get notifiedAtMs => $composableBuilder(
      column: $table.notifiedAtMs, builder: (column) => ColumnFilters(column));
}

class $$StoredPendingMemosTableOrderingComposer
    extends Composer<_$AppDatabase, $StoredPendingMemosTable> {
  $$StoredPendingMemosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get captureHash => $composableBuilder(
      column: $table.captureHash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get amountPaise => $composableBuilder(
      column: $table.amountPaise, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get direction => $composableBuilder(
      column: $table.direction, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payee => $composableBuilder(
      column: $table.payee, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payeeNormalized => $composableBuilder(
      column: $table.payeeNormalized,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get vpa => $composableBuilder(
      column: $table.vpa, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get accountTail => $composableBuilder(
      column: $table.accountTail, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get dateMs => $composableBuilder(
      column: $table.dateMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get capturedAtMs => $composableBuilder(
      column: $table.capturedAtMs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get assignedCategory => $composableBuilder(
      column: $table.assignedCategory,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mergedTxnUuid => $composableBuilder(
      column: $table.mergedTxnUuid,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get notifiedAtMs => $composableBuilder(
      column: $table.notifiedAtMs,
      builder: (column) => ColumnOrderings(column));
}

class $$StoredPendingMemosTableAnnotationComposer
    extends Composer<_$AppDatabase, $StoredPendingMemosTable> {
  $$StoredPendingMemosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get captureHash => $composableBuilder(
      column: $table.captureHash, builder: (column) => column);

  GeneratedColumn<int> get amountPaise => $composableBuilder(
      column: $table.amountPaise, builder: (column) => column);

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get payee =>
      $composableBuilder(column: $table.payee, builder: (column) => column);

  GeneratedColumn<String> get payeeNormalized => $composableBuilder(
      column: $table.payeeNormalized, builder: (column) => column);

  GeneratedColumn<String> get vpa =>
      $composableBuilder(column: $table.vpa, builder: (column) => column);

  GeneratedColumn<String> get accountTail => $composableBuilder(
      column: $table.accountTail, builder: (column) => column);

  GeneratedColumn<int> get dateMs =>
      $composableBuilder(column: $table.dateMs, builder: (column) => column);

  GeneratedColumn<int> get capturedAtMs => $composableBuilder(
      column: $table.capturedAtMs, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get assignedCategory => $composableBuilder(
      column: $table.assignedCategory, builder: (column) => column);

  GeneratedColumn<String> get mergedTxnUuid => $composableBuilder(
      column: $table.mergedTxnUuid, builder: (column) => column);

  GeneratedColumn<int> get notifiedAtMs => $composableBuilder(
      column: $table.notifiedAtMs, builder: (column) => column);
}

class $$StoredPendingMemosTableTableManager extends RootTableManager<
    _$AppDatabase,
    $StoredPendingMemosTable,
    StoredPendingMemo,
    $$StoredPendingMemosTableFilterComposer,
    $$StoredPendingMemosTableOrderingComposer,
    $$StoredPendingMemosTableAnnotationComposer,
    $$StoredPendingMemosTableCreateCompanionBuilder,
    $$StoredPendingMemosTableUpdateCompanionBuilder,
    (
      StoredPendingMemo,
      BaseReferences<_$AppDatabase, $StoredPendingMemosTable, StoredPendingMemo>
    ),
    StoredPendingMemo,
    PrefetchHooks Function()> {
  $$StoredPendingMemosTableTableManager(
      _$AppDatabase db, $StoredPendingMemosTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredPendingMemosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredPendingMemosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredPendingMemosTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> captureHash = const Value.absent(),
            Value<int> amountPaise = const Value.absent(),
            Value<String> direction = const Value.absent(),
            Value<String> payee = const Value.absent(),
            Value<String> payeeNormalized = const Value.absent(),
            Value<String?> vpa = const Value.absent(),
            Value<String?> accountTail = const Value.absent(),
            Value<int> dateMs = const Value.absent(),
            Value<int> capturedAtMs = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<String?> assignedCategory = const Value.absent(),
            Value<String?> mergedTxnUuid = const Value.absent(),
            Value<int?> notifiedAtMs = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              StoredPendingMemosCompanion(
            captureHash: captureHash,
            amountPaise: amountPaise,
            direction: direction,
            payee: payee,
            payeeNormalized: payeeNormalized,
            vpa: vpa,
            accountTail: accountTail,
            dateMs: dateMs,
            capturedAtMs: capturedAtMs,
            note: note,
            assignedCategory: assignedCategory,
            mergedTxnUuid: mergedTxnUuid,
            notifiedAtMs: notifiedAtMs,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String captureHash,
            required int amountPaise,
            required String direction,
            required String payee,
            required String payeeNormalized,
            Value<String?> vpa = const Value.absent(),
            Value<String?> accountTail = const Value.absent(),
            required int dateMs,
            required int capturedAtMs,
            Value<String?> note = const Value.absent(),
            Value<String?> assignedCategory = const Value.absent(),
            Value<String?> mergedTxnUuid = const Value.absent(),
            Value<int?> notifiedAtMs = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              StoredPendingMemosCompanion.insert(
            captureHash: captureHash,
            amountPaise: amountPaise,
            direction: direction,
            payee: payee,
            payeeNormalized: payeeNormalized,
            vpa: vpa,
            accountTail: accountTail,
            dateMs: dateMs,
            capturedAtMs: capturedAtMs,
            note: note,
            assignedCategory: assignedCategory,
            mergedTxnUuid: mergedTxnUuid,
            notifiedAtMs: notifiedAtMs,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$StoredPendingMemosTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $StoredPendingMemosTable,
    StoredPendingMemo,
    $$StoredPendingMemosTableFilterComposer,
    $$StoredPendingMemosTableOrderingComposer,
    $$StoredPendingMemosTableAnnotationComposer,
    $$StoredPendingMemosTableCreateCompanionBuilder,
    $$StoredPendingMemosTableUpdateCompanionBuilder,
    (
      StoredPendingMemo,
      BaseReferences<_$AppDatabase, $StoredPendingMemosTable, StoredPendingMemo>
    ),
    StoredPendingMemo,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$StoredDocumentsTableTableManager get storedDocuments =>
      $$StoredDocumentsTableTableManager(_db, _db.storedDocuments);
  $$StoredTransactionsTableTableManager get storedTransactions =>
      $$StoredTransactionsTableTableManager(_db, _db.storedTransactions);
  $$StoredCategoryRulesTableTableManager get storedCategoryRules =>
      $$StoredCategoryRulesTableTableManager(_db, _db.storedCategoryRules);
  $$StoredMatchesTableTableManager get storedMatches =>
      $$StoredMatchesTableTableManager(_db, _db.storedMatches);
  $$PinnedMonthsTableTableManager get pinnedMonths =>
      $$PinnedMonthsTableTableManager(_db, _db.pinnedMonths);
  $$StoredPendingMemosTableTableManager get storedPendingMemos =>
      $$StoredPendingMemosTableTableManager(_db, _db.storedPendingMemos);
}
