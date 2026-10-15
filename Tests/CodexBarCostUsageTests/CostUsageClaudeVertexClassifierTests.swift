import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageClaudeVertexClassifierTests {
    private static func fixtures() throws -> [[String: Any]] {
        var fixtures: [[String: Any]] = [
            [:], ["vertex": false], ["GCP": 0], ["vertex_enabled": NSNull()],
            ["metadata": ["provider": "anthropic"]],
            ["request": ["API_PROVIDER": "Google-Vertex-AI"]],
            ["context": ["client": ["backend": "vertex"]]],
            ["client": ["nested": [["platform": "vertexai"]]]],
            ["message": ["metadata": ["source": "VERTEX"]]],
            ["message": ["request": ["vendor": "vertex"]]],
            ["message": ["content": [["type": "tool_use", "input": ["gcp_project": false]]]]],
            ["message": ["content": [["type": "text", "text": "vertex"]]]],
            ["metadata": ["provider": false]], ["metadata": ["provider": 1]],
            ["metadata": ["provider": NSNull()]], ["metadata": ["provider": ["vertex"]]],
            ["metadata": ["provider": [["provider": "vertex"]]]],
            ["metadata": ["provider": [[["provider": "vertex"]]]]],
            ["metadata": ["provider": "gcp"]], ["not_provider": "vertex"],
            ["message": ["id": "msg_vrtx_123"]], ["requestId": "req_vrtx_123"],
            ["message": ["id": "msg_VRTX_123"]], ["requestId": "req_vrtx"],
            ["message": ["model": "claude-sonnet-4-6@20260217"]],
            ["message": ["model": "Claude-sonnet-4-6@20260217"]],
            ["message": ["model": "other@20260217"]],
        ]
        let markers = [
            "", "v", "verte", "vertex", "VERTEX", "VeRtEx", "prevertexpost", "vertices", "ver tex",
            "gcp", "GCP", "prefixGCPsuffix", "gc", "gc_p", "vertex\0", "\0vertex", "\r\nvertex",
            "vértex", "ve\u{301}rtex", "verteｘ", "ｖｅｒｔｅｘ", "vertex\u{301}", "gcp\u{301}",
            "日本vertex", "vertex🦞", "İVERTEX", "VERTEXİ", "ver\u{200D}tex", "\u{FEFF}vertex",
        ]
        let providerKeys = [
            "provider", "platform", "backend", "api_provider", "apiprovider", "api_type", "apitype",
            "source", "vendor", "client", "PROVIDER", "Api_Provider", "provider_suffix", "proviDERİ",
        ]
        for marker in markers {
            fixtures.append([marker: false])
            for key in providerKeys {
                fixtures.append(["metadata": [key: marker]])
            }
        }
        for body in [
            String(repeating: "synthetic text 123. ", count: 2048),
            String(repeating: "synthetic café 日本 🦞. ", count: 2048),
        ] {
            fixtures.append(["message": ["content": [["type": "text", "text": body + "vertex"]]]])
            fixtures.append(["metadata": ["provider": body]])
            fixtures.append(["metadata": ["provider": body + "VERTEX"]])
            fixtures.append([body + "GCP": 0])
        }
        // Decode escaped keys/values first, exactly as the JSONL ingestion path does.
        for json in [
            #"{"metadata":{"pro\u0076ider":"\u0076ertex"}}"#,
            #"{"metadata":{"\u0067cp":false}}"#,
            #"{"metadata":{"provider":"vertex\u0301"}}"#,
            #"{"metadata":{"provider":"\u65e5\u672cVERTEX"}}"#,
        ] {
            try fixtures.append(#require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]))
        }
        return try fixtures.map {
            try #require(JSONSerialization.jsonObject(
                with: JSONSerialization.data(withJSONObject: $0)) as? [String: Any])
        }
    }

    @Test
    func `decoded metadata preserves historical classification`() throws {
        for (index, fixture) in try Self.fixtures().enumerated() {
            #expect(
                CostUsageScanner.isVertexAIUsageEntry(obj: fixture)
                    == LegacyClaudeVertexClassifier.isVertexAIUsageEntry(obj: fixture),
                "fixture \(index)")
        }
        // Lock down surprising existing rules independently of the differential oracle.
        #expect(CostUsageScanner.isVertexAIUsageEntry(obj: ["vertex": false]))
        #expect(CostUsageScanner.isVertexAIUsageEntry(obj: ["GCP": 0]))
        #expect(!CostUsageScanner.isVertexAIUsageEntry(obj: ["provider": "gcp"]))
        #expect(!CostUsageScanner.isVertexAIUsageEntry(obj: ["nested": [[["provider": "vertex"]]]]))
        #expect(!CostUsageScanner.isVertexAIUsageEntry(obj: ["text": "vertex"]))
    }

    @Test
    func `raw decoded roots and deeply nested containers match frozen classifier`() throws {
        var roots: [Any] = try Self.fixtures().map {
            try JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: $0))
        }
        let mixed: NSDictionary = ["vertex": false, 7: "bad"]
        roots += [
            mixed,
            ["metadata": mixed],
            ["nested": [mixed]],
            ["message": NSDictionary(dictionary: ["id": "msg_vrtx_x", 7: false])],
            NSNull(),
            true,
            NSNumber(value: 2),
            "vertex",
            [],
            [[:]],
            ["nothing": NSObject()],
        ]
        var deep: [String: Any] = ["provider": "VERTEX"]
        for _ in 0..<128 {
            deep = ["nested": deep]
        }
        try roots.append(JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: deep)))
        for json in [
            #"{"message":{"id":"msg_\u0076rtx_123"}}"#,
            #"{"requestId":"req_\u0076rtx_123"}"#,
            #"{"message":{"model":"claude-test\u0040version"}}"#,
            #"{"metadata":{"pro\u0076ider":"VERTEX\u0130","empty":{}}}"#,
            #"{"metadata":{"café":{"provider":"vertex"},"cafe\u0301":{"GCP":null}}}"#,
            #"{"metadata":{"café":{"provider":"anthropic"},"cafe\u0301":{}}}"#,
            #"{"metadata":{"vertex":false,}}"#,
        ] {
            try roots.append(JSONSerialization.jsonObject(with: Data(json.utf8)))
        }
        for (index, root) in roots.enumerated() {
            let expected = (root as? [String: Any]).map {
                LegacyClaudeVertexClassifier.isVertexAIUsageEntry(obj: $0)
            } ?? false
            #expect(CostUsageScanner.isVertexAIUsageEntry(obj: root) == expected, "root \(index)")
            if JSONSerialization.isValidJSONObject(root),
               let decoded = try ClaudeJSONObject.decode(JSONSerialization.data(withJSONObject: root))
            {
                #expect(CostUsageScanner.isVertexAIUsageEntry(obj: decoded) == expected, "decoded root \(index)")
            }
        }
    }
}

/// Frozen pre-optimization predicate: keep traversal and Foundation string semantics independent.
private enum LegacyClaudeVertexClassifier {
    private static let vertexProviderKeys: Set<String> = [
        "provider",
        "platform",
        "backend",
        "api_provider",
        "apiprovider",
        "api_type",
        "apitype",
        "source",
        "vendor",
        "client",
    ]

    static func isVertexAIUsageEntry(obj: [String: Any]) -> Bool {
        // Primary detection: Vertex AI message IDs and request IDs have "vrtx" prefix
        // e.g., "msg_vrtx_0154LUXjFVzQGUca3yK2RUeo", "req_vrtx_011CWjK86SWeFuXqZKUtgB1H"
        if let message = obj["message"] as? [String: Any],
           let messageId = message["id"] as? String,
           messageId.contains("_vrtx_")
        {
            return true
        }
        if let requestId = obj["requestId"] as? String,
           requestId.contains("_vrtx_")
        {
            return true
        }

        // Secondary detection: model name with @ version separator (Vertex AI format)
        // e.g., "claude-opus-4-5@20251101" vs "claude-opus-4-5-20251101"
        if let message = obj["message"] as? [String: Any],
           let model = message["model"] as? String,
           Self.modelNameLooksVertex(model)
        {
            return true
        }

        // Fallback: check for explicit Vertex AI metadata fields
        var candidates: [[String: Any]] = [obj]
        if let metadata = obj["metadata"] as? [String: Any] {
            candidates.append(metadata)
        }
        if let request = obj["request"] as? [String: Any] {
            candidates.append(request)
        }
        if let context = obj["context"] as? [String: Any] {
            candidates.append(context)
        }
        if let client = obj["client"] as? [String: Any] {
            candidates.append(client)
        }
        if let message = obj["message"] as? [String: Any] {
            if let metadata = message["metadata"] as? [String: Any] {
                candidates.append(metadata)
            }
            if let request = message["request"] as? [String: Any] {
                candidates.append(request)
            }
        }

        return candidates.contains { Self.containsVertexAIMetadata(in: $0) }
    }

    /// Detects Vertex AI model names by format.
    /// Vertex AI uses @ for version separator: claude-opus-4-5@20251101
    /// Anthropic API uses -: claude-opus-4-5-20251101
    private static func modelNameLooksVertex(_ model: String) -> Bool {
        // Vertex AI model format: claude-{variant}@{version}
        // Examples: claude-opus-4-5@20251101, claude-sonnet-4-5@20250514
        guard model.hasPrefix("claude-") else { return false }
        return model.contains("@")
    }

    private static func containsVertexAIMetadata(in dict: [String: Any]) -> Bool {
        for (key, value) in dict {
            let lowerKey = key.lowercased()
            if lowerKey.contains("vertex") || lowerKey.contains("gcp") {
                return true
            }
            if Self.vertexProviderKeys.contains(lowerKey),
               let text = value as? String,
               Self.stringLooksVertex(text)
            {
                return true
            }
            if let nested = value as? [String: Any] {
                if Self.containsVertexAIMetadata(in: nested) {
                    return true
                }
            } else if let array = value as? [Any] {
                if Self.containsVertexAIMetadata(in: array) {
                    return true
                }
            }
        }

        return false
    }

    private static func containsVertexAIMetadata(in array: [Any]) -> Bool {
        for entry in array {
            if let dict = entry as? [String: Any] {
                if self.containsVertexAIMetadata(in: dict) {
                    return true
                }
            }
        }

        return false
    }

    private static func stringLooksVertex(_ value: String) -> Bool {
        value.lowercased().contains("vertex")
    }
}
