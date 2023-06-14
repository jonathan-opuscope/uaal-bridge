//
//  BridgeListener.swift
//
//  Created by Jonathan Thorpe on 29/05/2023.
//

import Foundation
import Combine
import OSLog

public class BridgeNotification : NSObject {
    static let notificationName = NSNotification.Name(rawValue: "BrideIncomingPayloadNotification")
    static let notificationPathKey = "BrideIncomingPathKey"
    static let notificationContentKey = "BrideIncomingContentKey"
}

public struct BridgeMessage : Codable {
    public let path : String
    public let content : String
    // need to define explicitely for use outside package
    public init(path: String, content: String) {
        self.path = path
        self.content = content
    }
}

public protocol BridgeListener {
    var messages : AnyPublisher<BridgeMessage, Never> { get }
}

public class BroadcastingBridgeListener : BridgeListener {
    
    public var messages : AnyPublisher<BridgeMessage, Never> {
        subject.eraseToAnyPublisher()
    }
    
    private let subject = PassthroughSubject<BridgeMessage, Never>()
    
    func broadcast(message : BridgeMessage) {
        self.subject.send(message)
    }
    
}

public class DefaultBridgeListener : BridgeListener {
    
    public var messages : AnyPublisher<BridgeMessage, Never> {
        subject.eraseToAnyPublisher()
    }
    
    private var subscription : AnyCancellable?
    private let subject = PassthroughSubject<BridgeMessage, Never>()
    
    public init() {
        subscription = NotificationCenter.default.publisher(for: BridgeNotification.notificationName).sink { value in
            guard let userInfo = value.userInfo else {
                return
            }
            guard let path = userInfo[BridgeNotification.notificationPathKey] as? String else {
                return
            }
            guard let content = userInfo[BridgeNotification.notificationContentKey] as? String else {
                return
            }
            self.subject.send(BridgeMessage(path: path, content: content))
        }
    }
}


public extension Publisher {
    
    func decodeContent<T:Decodable>(path: String) -> AnyPublisher<T, Self.Failure> where Output == BridgeMessage {
        self
            .filter { $0.path == path}
            .decodeContent()
    }
    
    func decodeContent<T:Decodable>() -> AnyPublisher<T, Self.Failure> where Output == BridgeMessage {
        self
            .map {
                do {
                    return try JSONDecoder().decode(T.self, from: Data($0.content.utf8))
                } catch {
                    Logger.bridge.error("Decode to \(String(describing: T.self)) error \(error) content : \($0.content)")
                    return nil
                }
            }
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }
}
