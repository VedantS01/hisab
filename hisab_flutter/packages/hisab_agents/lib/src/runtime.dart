/// The model side of an agent behind one interface. In the app it is Apple's
/// models through the iOS channel (ChannelRuntime, lib/services/apple_model.dart);
/// in evals the same Swift runtime through tool/apple_model_cli
/// ([ProcessRuntime]); in tests, canned replies.
library;

import 'dart:convert';

/// A tool the model may call while answering. Its work runs in Dart; the
/// result goes back to the model as text.
class AgentTool {
  final String name;
  final String description;

  /// JSON Schema of the arguments object (see [Schema]).
  final Map<String, Object?> parameters;
  final Future<String> Function(Map<String, Object?> arguments) run;

  const AgentTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.run,
  });

  Map<String, Object?> toJson() =>
      {'name': name, 'description': description, 'parameters': parameters};
}

enum ModelChoice { auto, cloud, onDevice }

/// How much the cloud model thinks before answering; the on-device model
/// doesn't reason and ignores it.
enum Reasoning { light, moderate, deep }

class ModelRequest {
  final String instructions;
  final String prompt;

  /// JSON Schema the reply must follow; null for plain text.
  final Map<String, Object?>? schema;
  final List<AgentTool> tools;
  final Reasoning? reasoning;
  final ModelChoice model;

  /// Most likely token every time: for labelling, where variety is noise.
  final bool greedy;

  /// The request transforms the user's own content (statements, alerts),
  /// which the on-device model's default guardrails often refuse.
  final bool transform;

  const ModelRequest({
    required this.instructions,
    required this.prompt,
    this.schema,
    this.tools = const [],
    this.reasoning,
    this.model = ModelChoice.auto,
    this.greedy = false,
    this.transform = false,
  });

  Map<String, Object?> toJson() => {
        'instructions': instructions,
        'prompt': prompt,
        if (schema != null) 'schema': schema,
        if (tools.isNotEmpty) 'tools': [for (final t in tools) t.toJson()],
        if (reasoning != null) 'reasoning': reasoning!.name,
        'model': model.name,
        if (greedy) 'greedy': true,
        if (transform) 'transform': true,
      };
}

class ModelReply {
  /// JSON text when the request had a schema, else the model's text.
  final String content;

  /// cloud | onDevice
  final String model;

  /// Why a cloud request fell back on-device: network | unavailable |
  /// rateLimited | quota.
  final String? fallback;

  const ModelReply({required this.content, required this.model, this.fallback});

  factory ModelReply.fromJson(Map<String, Object?> json) => ModelReply(
        content: json['content'] as String? ?? '',
        model: json['model'] as String? ?? 'onDevice',
        fallback: json['fallback'] as String?,
      );

  Map<String, Object?> get json => jsonDecode(content) as Map<String, Object?>;
}

/// A request the models couldn't serve. [code]: unavailable, context
/// (too long for the model), refused, language, timeout, quota, tool,
/// failed.
class ModelFailure implements Exception {
  final String code;
  final String message;
  const ModelFailure(this.code, [this.message = '']);

  @override
  String toString() => 'ModelFailure($code${message.isEmpty ? '' : ': $message'})';
}

class ModelStatus {
  /// available, deviceNotEligible, appleIntelligenceNotEnabled,
  /// modelNotReady, unavailable, osTooOld, unsupported.
  final String onDevice;

  /// available, notEntitled, deviceNotEligible, systemNotReady, unavailable,
  /// osTooOld, unsupported.
  final String cloud;

  /// approaching | reached, when the cloud model's daily limit is near.
  final String? quota;

  const ModelStatus({required this.onDevice, required this.cloud, this.quota});

  static const unsupported = ModelStatus(onDevice: 'unsupported', cloud: 'unsupported');

  factory ModelStatus.fromJson(Map<String, Object?> json) => ModelStatus(
        onDevice: json['onDevice'] as String? ?? 'unavailable',
        cloud: json['cloud'] as String? ?? 'unavailable',
        quota: json['quota'] as String?,
      );

  bool get onDeviceReady => onDevice == 'available';
  bool get cloudReady => cloud == 'available';

  /// Some model can take a request now.
  bool get ready => onDeviceReady || cloudReady;
}

abstract interface class ModelRuntime {
  Future<ModelStatus> status();

  /// Throws [ModelFailure].
  Future<ModelReply> respond(ModelRequest request);
}

/// JSON Schema builders in the shape Apple's GenerationSchema decodes:
/// objects closed (`additionalProperties: false`) and ordered (`x-order`, the
/// order the model writes properties in).
abstract final class Schema {
  static Map<String, Object?> object(
    String title,
    Map<String, Map<String, Object?>> properties, {
    Set<String> optional = const {},
    String? description,
    Map<String, Map<String, Object?>>? defs,
  }) =>
      {
        'type': 'object',
        'title': title,
        if (description != null) 'description': description,
        'additionalProperties': false,
        'properties': properties,
        'required': [for (final k in properties.keys) if (!optional.contains(k)) k],
        'x-order': properties.keys.toList(),
        // Apple's decoder resolves a $ref by the definition's title.
        if (defs != null)
          r'$defs': {
            for (final MapEntry(:key, :value) in defs.entries) key: {'title': key, ...value}
          },
      };

  static Map<String, Object?> string({String? description, List<String>? oneOf}) => {
        'type': 'string',
        if (description != null) 'description': description,
        if (oneOf != null) 'enum': oneOf,
      };

  static Map<String, Object?> integer({String? description}) =>
      {'type': 'integer', if (description != null) 'description': description};

  static Map<String, Object?> boolean({String? description}) =>
      {'type': 'boolean', if (description != null) 'description': description};

  static Map<String, Object?> array(Map<String, Object?> items,
          {String? description, int? min, int? max}) =>
      {
        'type': 'array',
        if (description != null) 'description': description,
        'items': items,
        if (min != null) 'minItems': min,
        if (max != null) 'maxItems': max,
      };

  /// A property that is one of [defs]' named schemas.
  static Map<String, Object?> ref(String name, {String? description}) =>
      {r'$ref': '#/\$defs/$name', if (description != null) 'description': description};
}
