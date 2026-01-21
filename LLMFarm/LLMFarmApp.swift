//
//  LLMFarmApp.swift
//  LLMFarm
//
//  Created by guinmoon on 20.05.2023.
//

import Darwin
import SwiftUI

// import llmfarm_core_cpp

@main
struct LLMFarmApp: App {
    @State var add_chat_dialog = false
    @State var edit_chat_dialog = false
    @State var current_detail_view_name: String? = "Chat"
    @State var model_name = ""
    @State var title = ""
    @StateObject var aiChatModel = AIChatModel()
    @StateObject var fineTuneModel = FineTuneModel()
    @StateObject var orientationInfo = OrientationInfo()
    @State var isLandscape: Bool = false
    @State private var chat_selection: [String: String]?
    @State var after_chat_edit: () -> Void = {}
    @State var tabIndex: Int = 0
    //    var set_res = setSignalHandler()

    func close_chat() {
        aiChatModel.stop_predict()
    }

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                ChatListView(tabSelection: .constant(0),
                             model_name: $model_name,
                             title: $title,
                             add_chat_dialog: $add_chat_dialog,
                             close_chat: close_chat,
                             edit_chat_dialog: $edit_chat_dialog,
                             chat_selection: $chat_selection,
                             after_chat_edit: $after_chat_edit).environmentObject(fineTuneModel)
                    .environmentObject(aiChatModel)
                    .frame(minWidth: 250, maxHeight: .infinity)
            }
            detail: {
                ChatView(
                    modelName: $model_name,
                    chatSelection: $chat_selection,
                    title: $title,
                    CloseChat: close_chat,
                    AfterChatEdit: $after_chat_edit,
                    addChatDialog: $add_chat_dialog,
                    editChatDialog: $edit_chat_dialog
                ).environmentObject(aiChatModel).environmentObject(orientationInfo)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationSplitViewStyle(.balanced)
            .background(.ultraThinMaterial)
        }
    }
}

#if canImport(HotSwiftUI)
@_exported import HotSwiftUI
#elseif canImport(Inject)
@_exported import Inject
#else
// This code can be found in the Swift package:
// https://github.com/johnno1962/HotSwiftUI

#if DEBUG
import Combine

private var loadInjectionOnce: () = {
        guard objc_getClass("InjectionClient") == nil else {
            return
        }
        #if os(macOS) || targetEnvironment(macCatalyst)
        let bundleName = "macOSInjection.bundle"
        #elseif os(tvOS)
        let bundleName = "tvOSInjection.bundle"
        #elseif os(visionOS)
        let bundleName = "xrOSInjection.bundle"
        #elseif targetEnvironment(simulator)
        let bundleName = "iOSInjection.bundle"
        #else
        let bundleName = "maciOSInjection.bundle"
        #endif
        let bundlePath = "/Applications/InjectionIII.app/Contents/Resources/"+bundleName
        guard let bundle = Bundle(path: bundlePath), bundle.load() else {
            return print("""
                ⚠️ Could not load injection bundle from \(bundlePath). \
                Have you downloaded the InjectionIII.app from either \
                https://github.com/johnno1962/InjectionIII/releases \
                or the Mac App Store?
                """)
        }
}()

public let injectionObserver = InjectionObserver()

public class InjectionObserver: ObservableObject {
    @Published var injectionNumber = 0
    var cancellable: AnyCancellable? = nil
    let publisher = PassthroughSubject<Void, Never>()
    init() {
        _ = loadInjectionOnce // .enableInjection() optional Xcode 16+
        cancellable = NotificationCenter.default.publisher(for:
            Notification.Name("INJECTION_BUNDLE_NOTIFICATION"))
            .sink { [weak self] change in
            self?.injectionNumber += 1
            self?.publisher.send()
        }
    }
}

extension SwiftUI.View {
    public func eraseToAnyView() -> some SwiftUI.View {
        _ = loadInjectionOnce
        return AnyView(self)
    }
    public func enableInjection() -> some SwiftUI.View {
        return eraseToAnyView()
    }
    public func loadInjection() -> some SwiftUI.View {
        return eraseToAnyView()
    }
    public func onInjection(bumpState: @escaping () -> ()) -> some SwiftUI.View {
        return self
            .onReceive(injectionObserver.publisher, perform: bumpState)
            .eraseToAnyView()
    }
}

@available(iOS 13.0, *)
@propertyWrapper
public struct ObserveInjection: DynamicProperty {
    @ObservedObject private var iO = injectionObserver
    public init() {}
    public private(set) var wrappedValue: Int {
        get {0} set {}
    }
}
#else
extension SwiftUI.View {
    @inline(__always)
    public func eraseToAnyView() -> some SwiftUI.View { return self }
    @inline(__always)
    public func enableInjection() -> some SwiftUI.View { return self }
    @inline(__always)
    public func loadInjection() -> some SwiftUI.View { return self }
    @inline(__always)
    public func onInjection(bumpState: @escaping () -> ()) -> some SwiftUI.View {
        return self
    }
}

@available(iOS 13.0, *)
@propertyWrapper
public struct ObserveInjection {
    public init() {}
    public private(set) var wrappedValue: Int {
        get {0} set {}
    }
}
#endif
#endif
