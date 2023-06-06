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

@objc public class BridgeDemo : NSObject {
    
    private let bridge : Bridge
    private let workflowPerformer : BridgeWorkflowPerformer
    private let workflowRegister : BridgeWorkflowRegister
    
    public override init() {
        let messenger = UnityBridgeMessenger(gameObject: "Bridge", method: "OnBridgeMessage")
        let listener = DefaultBridgeListener()
        bridge = Bridge(messenger: messenger, listener: listener)
        workflowPerformer = BridgeWorkflowPerformer(bridge: bridge)
        workflowRegister = BridgeWorkflowRegister(bridge: bridge)
        super.init()
    }
    
    @objc public func start() {
        Task {
            try await runAll()
        }
    }
    
    private func runAll() async throws {
        try await testSingleWorkflow()
    }
    
    private func testSingleWorkflow() async throws {
        let procedure = "/test/simple"
        let payload = TestPayload(name: "Brigitte", number: 42, duration: 5)
        print("BridgeDemo testSimpleWorkflow start")
        let result : TestResult = try await workflowPerformer.perform(procedure: procedure, payload: payload)
        print("BridgeDemo testSimpleWorkflow result \(result)")
    }
    
    private func testConcurrentWorkflow() async throws {
        let procedure = "/test/simple"
        let payload1 = TestPayload(name: "Brigitte", number: 42, duration: 3)
        let payload2 = TestPayload(name: "Roger", number: 666, duration: 6)
        let payload3 = TestPayload(name: "Marguerite", number: 404, duration: 1)
        print("BridgeDemo testConcurrentWorkflow start")
        async let resultTask1 = workflowPerformer.perform(TestResult.self, procedure: procedure, payload: payload1)
        async let resultTask2 = workflowPerformer.perform(TestResult.self, procedure: procedure, payload: payload2)
        async let resultTask3 = workflowPerformer.perform(TestResult.self, procedure: procedure, payload: payload3)
        let result1 : TestResult = try await resultTask1
        let result2 : TestResult = try await resultTask2
        let result3 : TestResult = try await resultTask3
        print("BridgeDemo testSimpleWorkflow result \(result1) \(result2) \(result3)")
    }
    
    func testCancelledTestWorkflow() async throws {
        let procedure = "/test/simple"
        let payload = TestPayload(name: "Brigitte", number: 42, duration: 5)
        do {
            print("BridgeDemo testCancelledTestWorkflow start")
            // note cancellation requires Task or TaskGroup
            // https://www.hackingwithswift.com/quick-start/concurrency/how-to-cancel-a-task
            let resultTask = Task { () -> TestResult in
                return try await workflowPerformer.perform(procedure: procedure, payload: payload)
            }
            try await Task.sleep(nanoseconds: UInt64(3 * Double(NSEC_PER_SEC)))
            resultTask.cancel()
            let result = try await resultTask.value
            print("BridgeDemo testCancelledTestWorkflow got unexpected result \(result)")
        } catch is CancellationError {
            print("BridgeDemo testCancelledTestWorkflow got expected cancellation error")
        } catch {
            print("BridgeDemo testCancelledTestWorkflow got unexpected error \(error)")
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
    var duration : Float
}

struct TestResult : Codable {
    var message : String
    var success : Bool
}


