import CoreFoundation
import Foundation

/// A shallow view at the same object boundaries as the JSON parser's conditional dictionary casts.
struct ClaudeJSONObject {
    private let coerced: [String: Any]?
    private let foundation: NSDictionary?

    init?(_ value: Any) {
        guard let coerced = value as? [String: Any] else { return nil }
        self.coerced = coerced
        self.foundation = nil
    }

    static func decode(_ data: Data) throws -> Self? {
        let value = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = value as? NSDictionary else { return nil }
        return Self(decoded: dictionary)
    }

    subscript(key: String) -> Any? {
        if let foundation { return foundation[key] }
        return self.coerced?[key]
    }

    func dictionary(_ key: String) -> Self? {
        if let foundation {
            guard let dictionary = foundation[key] as? NSDictionary else { return nil }
            return Self(decoded: dictionary)
        }
        return self[key].flatMap(Self.init)
    }

    func contains(where predicate: (String, ClaudeJSONValue) -> Bool) -> Bool {
        if let foundation {
            return Self.withEntries(foundation) { keys, values in
                for index in keys.indices {
                    guard let key = keys[index], let value = values[index],
                          let string = Self.object(key) as? String
                    else { return false }
                    if predicate(string, ClaudeJSONValue(decoded: Self.object(value))) { return true }
                }
                return false
            }
        }
        return self.coerced?.contains { predicate($0.key, ClaudeJSONValue($0.value)) } ?? false
    }

    /// Only JSONSerialization and descendants of its immutable containers may enter this path.
    fileprivate init(decoded dictionary: NSDictionary) {
        let asciiKeys = Self.withEntries(dictionary) { keys, _ in
            keys.allSatisfy { pointer in
                guard let pointer, let key = Self.object(pointer) as? String else { return false }
                return key.utf8.allSatisfy { $0 < 0x80 }
            }
        }
        if asciiKeys {
            self.foundation = dictionary
            self.coerced = nil
        } else {
            // Foundation retains canonical-equivalent keys that Swift collapses. Expose only
            // the actual shallow coercion's survivors, without inventing a collision order.
            self.foundation = nil
            self.coerced = dictionary as? [String: Any]
        }
    }

    fileprivate static func object(_ pointer: UnsafeRawPointer) -> AnyObject {
        Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }

    private static func withEntries(
        _ dictionary: NSDictionary,
        body: (UnsafeBufferPointer<UnsafeRawPointer?>, UnsafeBufferPointer<UnsafeRawPointer?>) -> Bool) -> Bool
    {
        withExtendedLifetime(dictionary) {
            let cfDictionary = unsafeBitCast(dictionary, to: CFDictionary.self)
            let count = CFDictionaryGetCount(cfDictionary)
            // Separate allocations avoid doubled-count arithmetic; empty dictionaries need no pointers.
            guard count > 0 else {
                return body(UnsafeBufferPointer(start: nil, count: 0), UnsafeBufferPointer(start: nil, count: 0))
            }
            return withUnsafeTemporaryAllocation(of: UnsafeRawPointer?.self, capacity: count) { keys in
                withUnsafeTemporaryAllocation(of: UnsafeRawPointer?.self, capacity: count) { values in
                    CFDictionaryGetKeysAndValues(cfDictionary, keys.baseAddress, values.baseAddress)
                    return body(UnsafeBufferPointer(keys), UnsafeBufferPointer(values))
                }
            }
        }
    }
}

struct ClaudeJSONValue {
    private let value: Any
    private let decoded: AnyObject?
    private static let stringID = CFStringGetTypeID()
    private static let dictionaryID = CFDictionaryGetTypeID()
    private static let arrayID = CFArrayGetTypeID()

    fileprivate init(decoded: AnyObject) {
        self.decoded = decoded
        self.value = decoded
    }

    init(_ value: Any) {
        self.value = value
        self.decoded = nil
    }

    var string: String? {
        if let decoded {
            guard CFGetTypeID(decoded) == Self.stringID else { return nil }
            return decoded as? String
        }
        return self.value as? String
    }

    var dictionary: ClaudeJSONObject? {
        if let decoded {
            guard CFGetTypeID(decoded) == Self.dictionaryID else { return nil }
            return ClaudeJSONObject(decoded: unsafeBitCast(decoded, to: NSDictionary.self))
        }
        return ClaudeJSONObject(self.value)
    }

    func arrayContainsDictionary(where predicate: (ClaudeJSONObject) -> Bool) -> Bool {
        if let decoded {
            guard CFGetTypeID(decoded) == Self.arrayID else { return false }
            return withExtendedLifetime(decoded) {
                let array = unsafeBitCast(decoded, to: CFArray.self)
                for index in 0..<CFArrayGetCount(array) {
                    guard let pointer = CFArrayGetValueAtIndex(array, index),
                          let dictionary = Self(decoded: ClaudeJSONObject.object(pointer)).dictionary
                    else { continue }
                    if predicate(dictionary) { return true }
                }
                return false
            }
        }
        guard let array = self.value as? [Any] else { return false }
        return array.contains { entry in
            guard let dictionary = ClaudeJSONObject(entry) else { return false }
            return predicate(dictionary)
        }
    }
}
