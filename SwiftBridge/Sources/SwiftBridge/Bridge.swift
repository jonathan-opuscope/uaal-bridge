//
//  Bridge.swift
//
//  Created by Jonathan Thorpe on 30/05/2023.
//

import Foundation
import Combine
import OSLog

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier!
    static let bridge = Logger(subsystem: subsystem, category: "swift_bridge")
}


public class Bridge {
    
    private let messenger : BridgeMessenger
    private let listener : BridgeListener
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private var subjects : [String:PassthroughSubject<BridgeMessage, Never>] = [:]
    private var notificationSubscription : AnyCancellable?
    
    public init (messenger: BridgeMessenger, listener: BridgeListener) {
        self.messenger = messenger
        self.listener = listener
        self.notificationSubscription = self.listener.messages.sink { [weak self] notification in
            guard let self = self else { return }
            guard let subject = self.subjects[notification.path] else { return }
            subject.send(notification)
        }
    }
    
    public func send<T:Encodable>(path: String, content: T) throws {
        let data = try encoder.encode(content)
        try messenger.sendMessage(path: path, data: data)
    }
    
    public func publish(path : String) -> AnyPublisher<BridgeMessage, Never> {
        if let subject = subjects[path] {
            return subject.eraseToAnyPublisher()
        }
        let created = PassthroughSubject<BridgeMessage, Never>()
        subjects[path] = created
        return created.eraseToAnyPublisher()
    }
    
    public func publishContent<T:Decodable>(path : String) -> AnyPublisher<T, Never> {
        return publish(path: path).decodeContent()
    }
    
}
