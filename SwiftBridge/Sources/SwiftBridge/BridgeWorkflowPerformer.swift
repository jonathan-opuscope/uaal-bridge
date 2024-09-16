//
//  BridgeWorkflowController.swift
//
//  Created by Jonathan Thorpe on 02/06/2023.
//

import Foundation
import Combine
import OSLog

extension WorkflowFailure {
    func toError() -> Error {
        switch type {
        case WorkflowFailure.ErrorTypes.invalidType:
            return WorkflowError.invalidProcedure(message)
        case WorkflowFailure.ErrorTypes.cancellationType:
            return CancellationError()
        default:
            return WorkflowError.runtime(type: type, message: message)
        }
    }
}

actor BridgeWorkflowPerformerState {
    
    enum StateError : Error {
        case unknownContinuation(String)
    }
    
    private var continuations : [String:CheckedContinuation<WorkflowCompletion, Error>] = [:]
    
    func store(_ continuation : CheckedContinuation<WorkflowCompletion, Error>, identifier: String) {
        continuations[identifier] = continuation
    }
    
    func complete(_ completion : WorkflowCompletion) throws {
        guard let continuation = continuations[completion.identifier] else {
            throw StateError.unknownContinuation(completion.identifier)
        }
        continuation.resume(returning: completion)
        continuations.removeValue(forKey: completion.identifier)
    }
    
    func fail(_ failure : WorkflowFailure) throws {
        guard let continuation = continuations[failure.identifier] else {
            throw StateError.unknownContinuation(failure.identifier)
        }
        continuation.resume(throwing: failure.toError())
        continuations.removeValue(forKey: failure.identifier)
    }
    
    func error(_ error : Error, identifier : String) throws {
        guard let continuation = continuations[identifier] else {
            throw StateError.unknownContinuation(identifier)
        }
        continuation.resume(throwing: error)
        continuations.removeValue(forKey: identifier)
    }
    
}

public class BridgeWorkflowPerformer {
    
    private let bridge : Bridge
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private let state = BridgeWorkflowPerformerState()
    
    private var subscriptions = Set<AnyCancellable>()
    
    public init(bridge: Bridge) {
        self.bridge = bridge
        self.bridge.publishContent(path: WorkflowCompletion.path).sink { (completion : WorkflowCompletion) in
            Task {
                try await self.state.complete(completion)
            }
        }.store(in: &subscriptions)
        self.bridge.publishContent(path: WorkflowFailure.path).sink { (failure : WorkflowFailure) in
            Task {
                try await self.state.fail(failure)
            }
        }.store(in: &subscriptions)
    }
    
    // used for type specialization with async let or other cases when specialization of return type isn't easy
    public func perform<TPayload, TResult>(_ t : TResult.Type, procedure: String, payload: TPayload) async throws -> TResult
    where TPayload : Encodable, TResult : Decodable {
        return try await perform(procedure: procedure, payload: payload)
    }
    
    public func perform<TPayload, TResult>(procedure: String, payload: TPayload) async throws -> TResult
    where TPayload : Encodable, TResult : Decodable {
        let completion = try await performWorkflow(procedure: procedure, payload: payload)
        return try decoder.decode(TResult.self, from: Data(completion.result.utf8))
    }
    
    private func performWorkflow<TPayload>(procedure: String, payload: TPayload) async throws -> WorkflowCompletion
    where TPayload : Encodable {
        let identifier = UUID().uuidString
        return try await withTaskCancellationHandler(operation: {
            return try await withCheckedThrowingContinuation { (continuation : CheckedContinuation<WorkflowCompletion, Error>) in
                Task {
                    await self.state.store(continuation, identifier: identifier)
                    do {
                        let payload = String(decoding: try encoder.encode(payload), as: UTF8.self)
                        let request = WorkflowRequest(identifier: identifier, procedure: procedure, payload: payload)
                        try self.bridge.send(path: WorkflowRequest.path, content: request)
                    } catch {
                        try await self.state.error(error, identifier: identifier)
                    }
                }
            }
        }, onCancel: {
            // note : if we want immediate cancellation we can throw CancellationError on the continuation here
            try? bridge.send(path: WorkflowCancellation.path, content: WorkflowCancellation(identifier: identifier))
            
        })
    }
    
}
