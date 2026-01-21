//
//  AIChatModel.swift
//
//  Created by Artem Savkin
//

import Foundation
import llmfarm_core
import os
import SimilaritySearchKit
import SimilaritySearchKitDistilbert
import SimilaritySearchKitMiniLMAll
import SimilaritySearchKitMiniLMMultiQA
import SwiftUI

private extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1.0e18
    }
}

var AIChatModel_obj_ptr: UnsafeMutableRawPointer?

@MainActor
final class AIChatModel: ObservableObject {
    enum State {
        case none
        case loading
        case ragIndexLoading
        case ragSearch
        case completed
    }

    var chat: AI?
    var modelURL: String = ""
    var numberOfTokens = 0
    var total_sec = 0.0
    var action_button_icon = "paperplane"
    var model_loading = false
    var model_name = ""
    var chat_name = ""
    var start_predicting_time = DispatchTime.now()
    var first_predicted_token_time = DispatchTime.now()
    var tok_sec: Double = 0.0
    var ragIndexLoaded: Bool = false
    private var state_dump_path: String = ""
    private var title_backup = ""
    private var messages_lock = NSLock()
    var ragUrl: URL
    private var ragTop: Int = 3
    private var chunkSize: Int = 256
    private var chunkOverlap: Int = 100
    private var currentModel: EmbeddingModelType = .minilmMultiQA
    private var comparisonAlgorithm: SimilarityMetricType = .dotproduct
    private var chunkMethod: TextSplitterType = .recursive

    @Published var predicting = false
    @Published var AI_typing = 0
    @Published var state: State = .none
    @Published var messages: [Message] = []
    @Published var load_progress: Float = 0.0
    @Published var Title: String = ""
    @Published var is_mmodal: Bool = false
    @Published var cur_t_name: String = ""
    @Published var cur_eval_token_num: Int = 0
    @Published var query_tokens_count: Int = 0

    init() {
        let ragDir = GetRagDirRelPath(chat_name: chat_name)
        ragUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(ragDir) ?? URL(fileURLWithPath: "")
    }

    func ResetRAGUrl() {
        let ragDir = GetRagDirRelPath(chat_name: chat_name)
        ragUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(ragDir) ?? URL(fileURLWithPath: "")
    }

    private func model_load_progress_callback(_ progress: Float) -> Bool {
        DispatchQueue.main.async {
            self.load_progress = progress
        }
        return true
    }

    private func eval_callback(_ t: Int) -> Bool {
        DispatchQueue.main.async {
            if t == 0 {
                self.cur_eval_token_num += 1
            }
        }
        return false
    }

    private func after_model_load(_ load_result: String, in_text: String, attachment: String? = nil, attachment_type: String? = nil) {
        guard load_result == "[Done]", let chatModel = chat?.model, chatModel.context != nil else {
            finish_load(append_err_msg: true, msg_text: "Load Model Error: \(load_result)")
            return
        }

        finish_load()
        var system_prompt: String? = nil
        if chatModel.contextParams.system_prompt != "", chatModel.nPast == 0 {
            system_prompt = chatModel.contextParams.system_prompt + "\n"
            messages[messages.endIndex - 1].header = chatModel.contextParams.system_prompt
        }
        chatModel.parse_skip_tokens()
        Task {
            await self.Send(message: in_text, append_user_message: false, system_prompt: system_prompt, attachment: attachment, attachment_type: attachment_type)
        }
    }

    func hard_reload_chat() {
        remove_dump_state()
        chat?.model?.contextParams.save_load_state = false
        chat = nil
    }

    func remove_dump_state() {
        if FileManager.default.fileExists(atPath: state_dump_path) {
            try? FileManager.default.removeItem(atPath: state_dump_path)
        }
    }

    func reload_chat(_ chat_selection: [String: String]) {
        stop_predict()
        chat_name = chat_selection["chat"] ?? "Not selected"
        Title = chat_selection["title"] ?? ""
        is_mmodal = chat_selection["mmodal"] == "1"
        messages_lock.lock()
        messages = load_chat_history(chat_selection["chat"]! + ".json") ?? []
        messages_lock.unlock()
        state_dump_path = get_state_path_by_chat_name(chat_name) ?? ""
        ResetRAGUrl()
        ragIndexLoaded = false
        AI_typing = -Int.random(in: 0 ..< 100_000)
    }

    func update_chat_params() {
        guard let chat_config = getChatInfo(chat?.chatName ?? "") else { return }
        chat?.model?.contextParams = get_model_context_param_by_config(chat_config)
        chat?.model?.sampleParams = get_model_sample_param_by_config(chat_config)
    }

    func load_model_by_chat_name_prepare(_ chat_name: String, in_text _: String, attachment _: String? = nil, attachment_type _: String? = nil) -> Bool? {
        guard let chat_config = getChatInfo(chat_name), let model_inference = chat_config["model_inference"], let model = chat_config["model"] else {
            return nil
        }

        model_name = model as! String
        guard let m_url = get_path_by_short_name(model_name) else {
            return nil
        }
        modelURL = m_url

        var model_sample_param = get_model_sample_param_by_config(chat_config)
        var model_context_param = get_model_context_param_by_config(chat_config)

        if let grammar = chat_config["grammar"] as? String, grammar != "<None>", grammar != "" {
            model_context_param.grammar_path = get_grammar_path_by_name(grammar)
        }

        chunkSize = chat_config["chunk_size"] as? Int ?? chunkSize
        chunkOverlap = chat_config["chunk_overlap"] as? Int ?? chunkOverlap
        ragTop = chat_config["rag_top"] as? Int ?? ragTop
        currentModel = getCurrentModelFromStr(chat_config["current_model"] as? String ?? "")
        comparisonAlgorithm = getComparisonAlgorithmFromStr(chat_config["comparison_algorithm"] as? String ?? "")
        chunkMethod = getChunkMethodFromStr(chat_config["chunk_method"] as? String ?? "")

        AIChatModel_obj_ptr = nil
        self.chat = AI(_modelPath: modelURL, _chatName: chat_name)
        guard let chat else {
            return nil
        }
        chat.initModel(model_context_param.model_inference, contextParams: model_context_param)
        guard let chatModel = chat.model else {
            return nil
        }
        chatModel.sampleParams = model_sample_param
        chatModel.contextParams = model_context_param

        return true
    }

    func load_model_by_chat_name(_ chat_name: String, in_text: String, attachment: String? = nil, attachment_type: String? = nil) -> Bool? {
        model_loading = true

        if chat?.model?.contextParams.save_load_state == true {
            chat?.model?.contextParams.state_dump_path = get_state_path_by_chat_name(chat_name) ?? ""
        }

        chat?.model?.modelLoadProgressCallback = { progress in
            self.model_load_progress_callback(progress)
        }
        chat?.model?.modelLoadCompleteCallback = { load_result in
            self.chat?.model?.evalCallback = self.eval_callback
            self.after_model_load(load_result, in_text: in_text, attachment: attachment, attachment_type: attachment_type)
        }
        chat?.loadModel()

        return true
    }

    private func update_last_message(_ message: inout Message) {
        messages_lock.lock()
        if let _ = messages.last {
            messages[messages.endIndex - 1] = message
        }
        messages_lock.unlock()
    }

    func save_chat_history_and_state() {
        save_chat_history(messages, chat_name + ".json")
        chat?.model?.save_state()
    }

    func stop_predict(is_error: Bool = false) {
        chat?.flagExit = true
        total_sec = Double(DispatchTime.now().uptimeNanoseconds - start_predicting_time.uptimeNanoseconds) / 1_000_000_000
        if let last_message = messages.last {
            messages_lock.lock()
            if last_message.state == .predicting || last_message.state == .none {
                messages[messages.endIndex - 1].state = .predicted(totalSecond: total_sec)
                messages[messages.endIndex - 1].tok_sec = Double(numberOfTokens) / total_sec
            }
            if is_error {
                messages[messages.endIndex - 1].state = .error
            }
            messages_lock.unlock()
        }
        predicting = false
        tok_sec = Double(numberOfTokens) / total_sec
        numberOfTokens = 0
        action_button_icon = "paperplane"
        AI_typing = 0
        save_chat_history_and_state()
        if is_error {
            chat = nil
        }
    }

    func check_stop_words(_ token: String, _ message_text: inout String) -> Bool {
        for stop_word in chat?.model?.contextParams.reverse_prompt ?? [] {
            if token == stop_word || message_text.hasSuffix(stop_word) {
                if stop_word.count > 0, message_text.count > stop_word.count {
                    message_text.removeLast(stop_word.count)
                }
                return false
            }
        }
        return true
    }

    func process_predicted_str(_ str: String, _: Double, _ message: inout Message) -> Bool {
        let check = check_stop_words(str, &message.text)
        if !check {
            stop_predict()
        }
        if check, chat?.flagExit != true, chat_name == chat?.chatName {
            message.state = .predicting
            message.text += str
            AI_typing += 1
            update_last_message(&message)
            numberOfTokens += 1
        } else {
            print("chat ended.")
        }
        return check
    }

    func finish_load(append_err_msg: Bool = false, msg_text: String = "") {
        if append_err_msg {
            messages.append(Message(sender: .system, state: .error, text: msg_text, tok_sec: 0))
            stop_predict(is_error: true)
        }
        state = .completed
        Title = title_backup
    }

    func finish_completion(_ final_str: String, _ message: inout Message) {
        cur_t_name = ""
        load_progress = 0
        print(final_str)
        AI_typing = 0
        total_sec = Double(DispatchTime.now().uptimeNanoseconds - start_predicting_time.uptimeNanoseconds) / 1_000_000_000
        if chat_name == chat?.chatName, chat?.flagExit != true {
            message.tok_sec = tok_sec != 0 ? tok_sec : Double(numberOfTokens) / total_sec
            message.state = .predicted(totalSecond: total_sec)
            update_last_message(&message)
        } else {
            print("chat ended.")
        }
        predicting = false
        numberOfTokens = 0
        action_button_icon = "paperplane"
        if final_str.hasPrefix("[Error]") {
            messages.append(Message(sender: .system, state: .error, text: "Eval \(final_str)", tok_sec: 0))
        }
        save_chat_history_and_state()
    }

    func LoadRAGIndex(ragURL: URL) async {
        updateIndexComponents(currentModel: currentModel, comparisonAlgorithm: comparisonAlgorithm, chunkMethod: chunkMethod)
        await loadExistingIndex(url: ragURL, name: "RAG_index")
        ragIndexLoaded = true
    }

    func RegenerateLstMessage() {
        // self.messages.removeLast()
    }

    func GenerateRagLLMQuery(_ inputText: String, _ searchResultsCount: Int, _ ragURL: URL, message _: String, append_user_message _: Bool = true, system_prompt: String? = nil, attachment _: String? = nil, attachment_type _: String? = nil) {
        let aiQueue = DispatchQueue(label: "LLMFarm-RAG", qos: .userInitiated, attributes: .concurrent)

        aiQueue.async {
            Task {
                if await !self.ragIndexLoaded {
                    await self.LoadRAGIndex(ragURL: ragURL)
                }
                DispatchQueue.main.async {
                    self.state = .ragSearch
                }
                let results = await searchIndexWithQuery(query: inputText, top: searchResultsCount)
                let llmPrompt = SimilarityIndex.exportLLMPrompt(query: inputText, results: results!)
                await self.Send(message: llmPrompt, append_user_message: false, system_prompt: system_prompt, attachment: llmPrompt, attachment_type: "rag")
            }
        }
    }

    func SetSendMsgTokensCount(_: Int) {
        // Implementation here
    }

    func SetGeneratedMsgTokensCount(_: Int) {
        // Implementation here
    }

    func Send(message in_text: String, append_user_message: Bool = true, system_prompt: String? = nil, attachment: String? = nil, attachment_type: String? = nil, useRag: Bool = false) async {
        AI_typing += 1

        if append_user_message {
            let requestMessage = Message(sender: .user, state: .typed, text: in_text, tok_sec: 0, attachment: attachment, attachment_type: attachment_type)
            messages.append(requestMessage)
        }

        if chat == nil {
            guard let _ = load_model_by_chat_name_prepare(chat_name, in_text: in_text, attachment: attachment, attachment_type: attachment_type) else {
                return
            }
        }

        if useRag {
            state = .ragIndexLoading
            GenerateRagLLMQuery(in_text, ragTop, ragUrl, message: in_text, append_user_message: append_user_message, system_prompt: system_prompt, attachment: attachment, attachment_type: attachment_type)
            return
        }

        if chat?.model?.context == nil {
            state = .loading
            title_backup = Title
            Title = "loading..."
            let res = load_model_by_chat_name(chat_name, in_text: in_text, attachment: attachment, attachment_type: attachment_type)
            if res == nil {
                finish_load(append_err_msg: true, msg_text: "Model load error")
            }
            return
        }

        if attachment != nil, attachment_type == "rag" {
            let requestMessage = Message(sender: .user_rag, state: .typed, text: in_text, tok_sec: 0, attachment: attachment, attachment_type: attachment_type)
            messages.append(requestMessage)
        }

        state = .completed
        chat?.chatName = chat_name
        chat?.flagExit = false
        var message = Message(sender: .system, text: "", tok_sec: 0)
        messages.append(message)
        numberOfTokens = 0
        total_sec = 0.0
        predicting = true
        action_button_icon = "stop.circle"
        let img_real_path = get_path_by_short_name(attachment ?? "unknown", dest: "cache/images")
        start_predicting_time = DispatchTime.now()
        chat?.conversation(in_text, { str, time in
            _ = self.process_predicted_str(str, time, &message)
        }, { _, _ in
            // Handle key-value pairs if needed
        }, { final_str in
            self.finish_completion(final_str, &message)
        }, system_prompt: system_prompt, img_path: img_real_path)
    }
}
