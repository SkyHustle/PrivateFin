//
//  InjectionIII.swift
//  LLMFarm
//
//  Hot reload support using InjectionIII
//

#if DEBUG
import Foundation

class InjectionIII {
    static func setup() {
        #if os(macOS)
        let bundlePath = "/Applications/InjectionIII.app/Contents/Resources/macOSInjection.bundle"
        #else
        let bundlePath = "/Applications/InjectionIII.app/Contents/Resources/iOSInjection.bundle"
        #endif
        
        guard let bundle = Bundle(path: bundlePath) else {
            print("⚠️ InjectionIII: Bundle not found at \(bundlePath)")
            print("⚠️ Make sure InjectionIII app is installed in /Applications/")
            return
        }
        
        guard bundle.load() else {
            print("⚠️ InjectionIII: Failed to load bundle")
            return
        }
        
        // Get the Injected class and call load
        if let injectedClass = bundle.classNamed("Injection") as? NSObject.Type {
            _ = injectedClass.perform(NSSelectorFromString("load"))
            print("✅ InjectionIII: Successfully loaded")
        } else {
            print("⚠️ InjectionIII: Injected class not found")
        }
    }
}
#endif
