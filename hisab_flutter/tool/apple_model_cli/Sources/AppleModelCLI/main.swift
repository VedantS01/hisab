// JSON lines on stdin/stdout, one object per line:
//   in:  {"id":1,"type":"status"}
//        {"id":2,"type":"respond","request":{…AppleModelRuntime.Request…}}
//        {"type":"toolResult","callId":"…","result":"…"}   (answer to a toolCall)
//   out: {"id":1,"type":"status","status":{…}}
//        {"id":2,"type":"toolCall","callId":"…","name":"…","arguments":"…json…"}
//        {"id":2,"type":"reply","reply":{…}}  or  {"id":2,"type":"error","code":"…","message":"…"}
// Pass --cloud only from a build that holds the Private Cloud Compute entitlement.
import Foundation

actor ToolCalls {
    private var waiting: [String: CheckedContinuation<String, Error>] = [:]
    private var next = 0

    func call(requestId: Int, name: String, arguments: String) async throws -> String {
        next += 1
        let callId = "\(requestId)-\(next)"
        return try await withCheckedThrowingContinuation { continuation in
            waiting[callId] = continuation
            emit(["id": requestId, "type": "toolCall", "callId": callId, "name": name, "arguments": arguments])
        }
    }

    func resolve(_ callId: String, _ result: String) {
        waiting.removeValue(forKey: callId)?.resume(returning: result)
    }
}

let output = NSLock()
func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object),
          let line = String(data: data, encoding: .utf8) else { return }
    output.lock()
    print(line)
    fflush(stdout)
    output.unlock()
}

let cloudEntitled = CommandLine.arguments.contains("--cloud")
let toolCalls = ToolCalls()

while let line = readLine() {
    guard let data = line.data(using: .utf8),
          let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let type = message["type"] as? String else { continue }
    let id = message["id"] as? Int ?? 0
    let runtime = AppleModelRuntime(cloudEntitled: cloudEntitled) { name, arguments in
        try await toolCalls.call(requestId: id, name: name, arguments: arguments)
    }
    switch type {
    case "status":
        emit(["id": id, "type": "status", "status": runtime.status()])
    case "toolResult":
        if let callId = message["callId"] as? String {
            await toolCalls.resolve(callId, message["result"] as? String ?? "")
        }
    case "respond":
        let request: AppleModelRuntime.Request
        do {
            let json = try JSONSerialization.data(withJSONObject: message["request"] ?? [:])
            request = try JSONDecoder().decode(AppleModelRuntime.Request.self, from: json)
        } catch {
            emit(["id": id, "type": "error", "code": "badRequest", "message": "\(error)"])
            continue
        }
        // Detached: top-level code is main-actor-bound and readLine() blocks
        // the main thread, so an inheriting Task would never get to run.
        Task.detached {
            do {
                let reply = try await runtime.respond(request)
                let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reply))
                emit(["id": id, "type": "reply", "reply": encoded])
            } catch let failure as AppleModelRuntime.Failure {
                emit(["id": id, "type": "error", "code": failure.code, "message": failure.message])
            } catch {
                emit(["id": id, "type": "error", "code": "failed", "message": "\(error)"])
            }
        }
    default:
        continue
    }
}
