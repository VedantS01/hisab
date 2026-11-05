import 'package:hisab_agents/hisab_agents.dart';

/// Replies from a script, recording every request.
class FakeRuntime implements ModelRuntime {
  final List<Object> script;
  final requests = <ModelRequest>[];
  FakeRuntime(this.script);

  @override
  Future<ModelStatus> status() async => const ModelStatus(onDevice: 'available', cloud: 'notEntitled');

  @override
  Future<ModelReply> respond(ModelRequest request) async {
    requests.add(request);
    final next = script.removeAt(0);
    if (next is ModelFailure) throw next;
    return ModelReply(content: next as String, model: 'onDevice');
  }
}
