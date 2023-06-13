//
//  BridgeWorkflowController.swift
//
//  Created by Jonathan Thorpe on 02/06/2023.
//

import Foundation
import Combine

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

public class BridgeWorkflowPerformer {
    
    private let bridge : Bridge
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private var subscriptions = Set<AnyCancellable>()
    private var continuations : [String:CheckedContinuation<WorkflowCompletion, Error>] = [:]
    
    public init(bridge: Bridge) {
        self.bridge = bridge
        self.bridge.publishContent(path: WorkflowCompletion.path).sink { [weak self] (completion : WorkflowCompletion) in
            guard let continuation = self?.continuations[completion.identifier] else {
                print("Received \(String(describing: WorkflowCompletion.self)) \(completion) for unknown identifier")
                return
            }
            print("Received \(String(describing: WorkflowCompletion.self)) \(completion)")
            continuation.resume(returning: completion)
            self?.continuations.removeValue(forKey: completion.identifier)
        }.store(in: &subscriptions)
        self.bridge.publishContent(path: WorkflowFailure.path).sink { [weak self] (failure : WorkflowFailure) in
            guard let continuation = self?.continuations[failure.identifier] else {
                print("Received \(String(describing: WorkflowFailure.self)) \(failure) for unknown identifier")
                return
            }
            print("Received \(String(describing: WorkflowFailure.self)) \(failure)")
            continuation.resume(throwing: failure.toError())
            self?.continuations.removeValue(forKey: failure.identifier)
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
                continuations[identifier] = continuation
                do {
                    let payload = String(decoding: try encoder.encode(payload), as: UTF8.self)
                    let request = WorkflowRequest(identifier: identifier, procedure: procedure, payload: payload)
                    try bridge.send(path: WorkflowRequest.path, content: request)
                } catch {
                    continuation.resume(throwing: error)
                    continuations.removeValue(forKey: identifier)
                }
            }
        }, onCancel: {
            // note : if we want immediate cancellation we can throw CancellationError on the continuation here
            try? bridge.send(path: WorkflowCancellation.path, content: WorkflowCancellation(identifier: identifier))
            
        })
    }
    
}
