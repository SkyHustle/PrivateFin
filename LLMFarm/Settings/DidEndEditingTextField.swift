//
//  DidEndEditingTextField.swift
//  LlamaChat
//
//  Created by Alex Rozanski on 01/04/2023.
//

import SwiftUI

// DidEndEditingTextField(text: $name, didEndEditing: { newName in
//  viewModel.updateName(newName)
// })
#if os(macOS)
    struct DidEndEditingTextField: NSViewRepresentable {
        @Binding var text: String
        var didEndEditing: (String) -> Void

        class Coordinator: NSObject, NSTextFieldDelegate {
            var parent: DidEndEditingTextField

            init(_ parent: DidEndEditingTextField) {
                self.parent = parent
            }

            func controlTextDidChange(_ obj: Notification) {
                if let textField = obj.object as? NSTextField {
                    parent.text = textField.stringValue
                }
            }

            func controlTextDidEndEditing(_ obj: Notification) {
                if let textField = obj.object as? NSTextField {
                    parent.didEndEditing(textField.stringValue)
                }
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        func makeNSView(context: Context) -> NSTextField {
            let textField = NSTextField()
            textField.cell!.usesSingleLineMode = true
            textField.delegate = context.coordinator
            return textField
        }

        func updateNSView(_ nsView: NSTextField, context _: Context) {
            nsView.stringValue = text
        }
    }
#else
    struct DidEndEditingTextField: UIViewRepresentable {
        @Binding var text: String
        typealias UIViewType = UITextView
        var didEndEditing: (String) -> Void

        var configuration = { (_: UIViewType) in }

        func makeUIView(context _: UIViewRepresentableContext<Self>) -> UIViewType {
            UIViewType()
        }

        func updateUIView(_ uiView: UIViewType, context _: UIViewRepresentableContext<Self>) {
            configuration(uiView)
        }
    }
#endif
