import Foundation
import Tokenizers
import Models
import Generation
import Hub
import CoreML

actor LocalSummarizerService {
    static let shared = LocalSummarizerService()
    
    private var model: LanguageModel?
    private var tokenizer: Tokenizer?
    private var isLoading = false
    
    private init() {}
    
    func loadModelIfNeeded() async throws {
        guard model == nil else { return }
        guard !isLoading else {
            while isLoading {
                try await Task.sleep(for: .milliseconds(100))
            }
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        print("[LocalSummarizerService] Loading local DistilGPT2 model...")
        
        let modelId = "distilbert/distilgpt2"
        let repo = Hub.Repo(id: modelId)
        
        // Fetch model files (config and CoreML model package format)
        let modelDirectory = try await Hub.snapshot(
            from: repo,
            matching: ["*.json", "*.mlmodelc/*", "*.mlpackage/*"]
        )
        
        let tokenizer = try await AutoTokenizer.from(pretrained: modelId)
        
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(at: modelDirectory, includingPropertiesForKeys: nil)
        
        let compiledModelURL: URL
        if let existingCompiled = contents.first(where: { $0.pathExtension == "mlmodelc" }) {
            compiledModelURL = existingCompiled
        } else if let uncompiledPackage = contents.first(where: { $0.pathExtension == "mlpackage" }) {
            print("[LocalSummarizerService] Compiling CoreML model package at \(uncompiledPackage.path)...")
            compiledModelURL = try await MLModel.compileModel(at: uncompiledPackage)
            print("[LocalSummarizerService] Compilation successful: \(compiledModelURL.path)")
        } else {
            throw NSError(
                domain: "LocalSummarizerService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No CoreML model (.mlpackage or .mlmodelc) found in snapshot"]
            )
        }
        
        let model = try LanguageModel.loadCompiled(url: compiledModelURL, tokenizer: tokenizer)
        
        self.tokenizer = tokenizer
        self.model = model
        print("[LocalSummarizerService] DistilGPT2 model successfully loaded.")
    }
    
    func summarize(activityText: String) async -> String? {
        do {
            try await loadModelIfNeeded()
            guard let model = model, let tokenizer = tokenizer else {
                return nil
            }
            
            let prompt = "Activity Log:\n\(activityText)\nSummary:"
            let inputTokens = tokenizer.encode(text: prompt)
            
            var config = GenerationConfig(maxNewTokens: 32)
            config.doSample = false // greedy search is faster and more deterministic for summaries
            
            let output = try await model.generate(config: config, tokens: inputTokens)
            
            let decoded = tokenizer.decode(tokens: output)
            
            var cleanSummary = decoded
            if cleanSummary.hasPrefix(prompt) {
                cleanSummary = String(cleanSummary.dropFirst(prompt.count))
            }
            cleanSummary = cleanSummary.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            return cleanSummary.isEmpty ? nil : cleanSummary
        } catch {
            print("[LocalSummarizerService] Local summarization failed: \(error)")
            return nil
        }
    }
}