//
//  BridgeDemo.swift
//  NativeiOSApp
//
//  Created by Jonathan Thorpe on 01/06/2023.
//  Copyright © 2023 unity. All rights reserved.
//

import Foundation
import UIKit
import SwiftBridge
import OSLog

private enum ImplementationError : Error {
    case tooBig
}

@objc public class BridgeDemo : NSObject {
    
    private let bridge : Bridge
    private let workflowPerformer : BridgeWorkflowPerformer
    private let workflowRegister : BridgeWorkflowRegister
    
    private enum Paths {
        static let startTest = "/test/start"
    }
    
    private enum Procedures {
        static let immediateGreeting = "/greeting/immediate"
        static let delayedGreeting = "/greeting/delayed"
        static let errorGreeting = "/greeting/error"
    }
    
    public override init() {
        let messenger = UnityBridgeMessenger(gameObject: "Bridge", method: "OnBridgeMessage")
        let listener = DefaultBridgeListener()
        bridge = Bridge(messenger: messenger, listener: listener)
        workflowPerformer = BridgeWorkflowPerformer(bridge: bridge)
        workflowRegister = BridgeWorkflowRegister(bridge: bridge)
        super.init()
        registerImplementations()
    }
    
    private func registerImplementations() {
        do {
            try workflowRegister.register(procedure: Procedures.delayedGreeting) { [weak self] (payload : TestPayload) in
                try await self?.sleep(seconds: payload.duration)
                return TestResult(message: "Hello \(payload.name)", processed: payload.number + 2)
            }
            try workflowRegister.register(procedure: Procedures.immediateGreeting) { (payload : TestPayload) in
                return TestResult(message: "Hello \(payload.name)", processed: payload.number + 2)
            }
            try workflowRegister.register(TestResult.self, procedure: Procedures.errorGreeting) { [weak self] (payload : TestPayload) in
                try await self?.sleep(seconds: payload.duration)
                throw ImplementationError.tooBig
            }
        } catch {
            print("BridgeDemo error registering implementations \(error)")
        }
    }
    
    private func sleep(seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * Double(NSEC_PER_SEC)))
    }
    
    @objc public func start() {
        Task {
            try await runAll()
            try bridge.send(path: Paths.startTest, content: "")
        }
    }
    
    private func runAll() async throws {
        try await testImmediateWorkflow()
        try await testDelayedWorkflow()
        try await testConcurrentWorkflow()
        try await testCancelledWorkflow()
    }
    
    private func testImmediateWorkflow() async throws {
        let payload = TestPayload(name: "Brigitte", number: 42, duration: 5)
        print("BridgeDemo testImmediateWorkflow start \(payload)")
        let result : TestResult = try await workflowPerformer.perform(procedure: Procedures.immediateGreeting, payload: payload)
        print("BridgeDemo testImmediateWorkflow result \(result)")
    }
    
    private func testDelayedWorkflow() async throws {
        let payload = TestPayload(name: "Brigitte", number: 42, duration: 5)
        print("BridgeDemo testDelayedWorkflow start \(payload)")
        let result : TestResult = try await workflowPerformer.perform(procedure: Procedures.delayedGreeting, payload: payload)
        print("BridgeDemo testDelayedWorkflow result \(result)")
    }
    
    private func testConcurrentWorkflow() async throws {
        let payload1 = TestPayload(name: "Brigitte", number: 42, duration: 3)
        let payload2 = TestPayload(name: "Roger", number: 666, duration: 6)
        let payload3 = TestPayload(name: "Marguerite", number: 404, duration: 1)
        print("BridgeDemo testConcurrentWorkflow start \(payload1) \(payload2) \(payload3)")
        async let task1 = workflowPerformer.perform(TestResult.self, procedure: Procedures.delayedGreeting, payload: payload1)
        async let task2 = workflowPerformer.perform(TestResult.self, procedure: Procedures.delayedGreeting, payload: payload2)
        async let task3 = workflowPerformer.perform(TestResult.self, procedure: Procedures.delayedGreeting, payload: payload3)
        let result1 : TestResult = try await task1
        let result2 : TestResult = try await task2
        let result3 : TestResult = try await task3
        print("BridgeDemo testConcurrentWorkflow result \(result1) \(result2) \(result3)")
    }
    
    private func testCancelledWorkflow() async throws {
        let payload = TestPayload(name: "Brigitte", number: 42, duration: 5)
        do {
            print("BridgeDemo testCancelledWorkflow start")
            // note cancellation requires Task or TaskGroup
            // https://www.hackingwithswift.com/quick-start/concurrency/how-to-cancel-a-task
            let task = Task { () -> TestResult in
                return try await workflowPerformer.perform(procedure: Procedures.delayedGreeting, payload: payload)
            }
            try await Task.sleep(nanoseconds: UInt64(3 * Double(NSEC_PER_SEC)))
            task.cancel()
            let result = try await task.value
            print("BridgeDemo testCancelledWorkflow got unexpected result \(result)")
        } catch is CancellationError {
            print("BridgeDemo testCancelledWorkflow got expected cancellation error")
        } catch {
            print("BridgeDemo testCancelledWorkflow got unexpected error \(error)")
        }
    }
    
    private func testErrorWorkflow() async throws {
        do {
            let payload = TestPayload(name: "Brigitte", number: 42, duration: 5)
            print("BridgeDemo testErrorWorkflow start")
            let result : TestResult = try await workflowPerformer.perform(procedure: Procedures.errorGreeting, payload: payload)
            print("BridgeDemo testErrorWorkflow unexpected result \(result)")
        } catch {
            print("BridgeDemo testErrorWorkflow got expected error \(error)")
        }
    }
}

enum UnityBridgeMessengerError : Error {
    case notInitialized
}

class UnityBridgeMessenger : BridgeMessenger {
    
    let gameObject : String
    let method : String
    
    let encoder = JSONEncoder()
    
    init(gameObject: String, method: String) {
        self.gameObject = gameObject
        self.method = method
    }
    
    func sendMessage(path: String, content: String) throws {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            throw UnityBridgeMessengerError.notInitialized
        }
        let payload = BridgeMessage(path: path, content: content)
        let message = String(decoding: try encoder.encode(payload), as: UTF8.self)
        appDelegate.sendMessageToGO(withName: gameObject, functionName: method, message: message)
    }
}

struct TestPayload : Codable {
    var name : String
    var number : Int
    var duration : Double
}

struct TestResult : Codable {
    var message : String
    var processed : Int
}


