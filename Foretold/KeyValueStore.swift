//
//  KeyValueStore.swift
//  Foretold
//
//  Platform-neutral persistence. `Defaults.standard` mirrors the subset of the
//  UserDefaults API that GameScene uses, so call sites are identical on both
//  targets (just `UserDefaults.standard` → `Defaults.standard`).
//
//    • mac  — a thin passthrough to UserDefaults (behavior unchanged)
//    • web  — browser localStorage via JavaScriptKit (persists across reloads;
//             UserDefaults on WASM would be in-memory only)
//
//  Values are the five types GameScene stores: Bool, Int, String, [String],
//  [String: Int]. Keys and semantics match UserDefaults (missing bool → false,
//  missing integer → 0, etc.).

#if canImport(SpriteKit)   // Apple platforms → real UserDefaults
import Foundation

struct Defaults {
    static let standard = Defaults()
    private let d = UserDefaults.standard

    func bool(forKey k: String) -> Bool { d.bool(forKey: k) }
    func integer(forKey k: String) -> Int { d.integer(forKey: k) }
    func string(forKey k: String) -> String? { d.string(forKey: k) }
    func stringArray(forKey k: String) -> [String]? { d.stringArray(forKey: k) }
    func dictionary(forKey k: String) -> [String: Any]? { d.dictionary(forKey: k) }
    func object(forKey k: String) -> Any? { d.object(forKey: k) }
    func removeObject(forKey k: String) { d.removeObject(forKey: k) }

    func set(_ v: Bool, forKey k: String) { d.set(v, forKey: k) }
    func set(_ v: Int, forKey k: String) { d.set(v, forKey: k) }
    func set(_ v: String, forKey k: String) { d.set(v, forKey: k) }
    func set(_ v: [String], forKey k: String) { d.set(v, forKey: k) }
    func set(_ v: [String: Int], forKey k: String) { d.set(v, forKey: k) }
}

#else   // WASM/web → browser localStorage
import JavaScriptKit

struct Defaults {
    static let standard = Defaults()

    private var storage: JSObject { JSObject.global.localStorage.object! }
    private var json: JSObject { JSObject.global.JSON.object! }

    private func raw(_ k: String) -> String? { storage.getItem!(k).string }
    private func write(_ k: String, _ v: String) { _ = storage.setItem!(k, v) }

    func bool(forKey k: String) -> Bool { raw(k) == "true" }
    func integer(forKey k: String) -> Int { Int(raw(k) ?? "") ?? 0 }
    func string(forKey k: String) -> String? { raw(k) }

    func stringArray(forKey k: String) -> [String]? {
        guard let s = raw(k), let arr = json.parse!(s).object else { return nil }
        let n = Int(arr.length.number ?? 0)
        return (0..<n).map { arr[$0].string ?? "" }
    }

    func dictionary(forKey k: String) -> [String: Any]? {
        guard let s = raw(k) else { return nil }
        let parsed = json.parse!(s)
        guard let obj = parsed.object else { return nil }
        let keys = JSObject.global.Object.object!.keys!(parsed).object!
        let n = Int(keys.length.number ?? 0)
        var result: [String: Any] = [:]
        for i in 0..<n {
            let key = keys[i].string ?? ""
            if let num = obj[key].number { result[key] = Int(num) }
        }
        return result
    }

    func object(forKey k: String) -> Any? {
        guard let s = raw(k) else { return nil }
        if s == "true" { return true }
        if s == "false" { return false }
        if let i = Int(s) { return i }
        return s
    }

    func removeObject(forKey k: String) { _ = storage.removeItem!(k) }

    func set(_ v: Bool, forKey k: String) { write(k, v ? "true" : "false") }
    func set(_ v: Int, forKey k: String) { write(k, String(v)) }
    func set(_ v: String, forKey k: String) { write(k, v) }
    func set(_ v: [String], forKey k: String) { write(k, json.stringify!(v.jsValue).string ?? "[]") }
    func set(_ v: [String: Int], forKey k: String) { write(k, json.stringify!(v.jsValue).string ?? "{}") }
}
#endif
