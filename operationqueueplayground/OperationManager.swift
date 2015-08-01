//
//  OperationManager.swift
//  operationqueueplayground
//
//  Created by Sebastian Volland on 31/07/15.
//  Copyright © 2015 Sebastian Volland. All rights reserved.
//

import Foundation

let OperationChangedNotification = "OperationChangedNotification"

class Operation: NSOperation {

    enum UserState: CustomStringConvertible {
        case Queued
        case Processing
        case Cancelled
        case Finished

        var description: String {
            switch self {
            case Queued:
                return "Queued"
            case Processing:
                return "Processing"
            case Cancelled:
                return "Cancelled"
            case Finished:
                return "Finished"
            }
        }
    }

    enum OperationState: CustomStringConvertible {
        case Ready
        case Executing
        case Finished

        func keyPath() -> String {
            switch self {
            case Ready:
                return "isReady"
            case Executing:
                return "isExecuting"
            case Finished:
                return "isFinished"
            }
        }
        var description: String {
            switch self {
            case Ready:
                return "Ready"
            case Executing:
                return "Executing"
            case Finished:
                return "Finished"
            }
        }
    }

    var operationState = OperationState.Ready {
        willSet {
            willChangeValueForKey(newValue.keyPath())
            willChangeValueForKey(operationState.keyPath())
        }
        didSet {
            didChangeValueForKey(oldValue.keyPath())
            didChangeValueForKey(operationState.keyPath())

            notifyChange()
        }
    }

    var userState: UserState {
        if cancelled {
            return .Cancelled
        }

        switch operationState {
        case .Ready: return .Queued
        case .Executing: return .Processing
        case .Finished: return .Finished
        }
    }

    var id: Int {
        return ObjectIdentifier(self).hashValue
    }

    var hasStarted = false
    var didCopy = false

    var _progress = 0
    var progress: Int {
        get {
            return _progress
        }
        set {
            _progress = newValue
            notifyChange()
        }
    }

    var _paused = false
    var paused: Bool {
        get {
            return _paused
        }
        set {
            guard canPause else {
                return
            }

            _paused = newValue
            notifyChange()
        }
    }

    override var ready: Bool {
        return super.ready && operationState == .Ready
    }

    override var executing: Bool {
        return operationState == .Executing
    }

    override var finished: Bool {
        return operationState == .Finished
    }

    override var asynchronous: Bool {
        return true
    }

    override var description: String {
        let name = self.name ?? ""
        let pauseInfo = paused ? "[Paused] " : ""
        return "\(id) - \(name) - \(userState) \(pauseInfo)- \(progress)"
    }

    func notifyChange() {
        NSNotificationCenter.defaultCenter().postNotificationName(OperationChangedNotification, object: self)
    }

    override func cancel() {
        if canCancel {
            super.cancel()
            notifyChange()
        }
    }

    func pause() {
        paused = true
        notifyChange()
    }

    func resume() {
        paused = false
        notifyChange()
    }

    var canClear: Bool {
        return (hasStarted == false && userState == .Cancelled)
            || operationState == .Finished
    }

    var canCancel: Bool {
        return userState == .Queued
            || userState == .Processing
    }

    var canRetry: Bool {
        return userState == .Cancelled
    }

    var canPause: Bool {
        return userState == .Processing
            || userState == .Queued
            || userState == .Cancelled
    }

    func copyForRetry() -> Operation? {
        return nil
    }

}

class OperationManager: NSObject {

    var operationQueue = NSOperationQueue()
    var operations = [Operation]()
    var paused = false

    private var observeContext = 0
    private var operationChangedNotificationObserver: AnyObject?

    var didInsertOperation: ((index: Int, operation: Operation) -> ())?
    var didRemoveOperation: ((index: Int, operation: Operation) -> ())?
    var didUpdateOperation: ((index: Int, operation: Operation) -> ())?

    override init() {
        super.init()

        operationQueue.maxConcurrentOperationCount = 2
        operationQueue.addObserver(self, forKeyPath: "operations", options: .New, context: &observeContext)

        operationChangedNotificationObserver = NSNotificationCenter.defaultCenter().addObserverForName(OperationChangedNotification, object: nil, queue: NSOperationQueue.mainQueue()) { notification in
            guard let operation = notification.object as? Operation else {
                return
            }
            self.updateOperation(operation)
        }
    }

    deinit {
        operationQueue.removeObserver(self, forKeyPath: "operations", context: &observeContext)

        if operationChangedNotificationObserver != nil {
            NSNotificationCenter.defaultCenter().removeObserver(operationChangedNotificationObserver!)
        }
    }

    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        if context == &observeContext {
            performSelectorOnMainThread(Selector("reload"), withObject: nil, waitUntilDone: false)
            return
        }

        super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
    }

    private func insertOperation(operation: Operation) {
        self.operations.append(operation)
        didInsertOperation?(index: operations.count - 1, operation: operation)
    }

    private func updateOperation(operation: Operation) {
        if let idx = operations.indexOf(operation) {
            didUpdateOperation?(index: idx, operation: operation)
        }
    }

    func reload() {
        for operation in operationQueue.operations as! [Operation] {
            if self.operations.indexOf(operation) == nil && operation.canClear == false && operation.didCopy == false {
                insertOperation(operation)
            } else {
                updateOperation(operation)
            }
        }
    }

    var zombieCount: Int {
        var count = 0
        for op in operationQueue.operations as! [Operation] {
            if operations.indexOf(op) == nil {
                count++
            }
        }
        return count
    }

    func clear(operation: Operation) {
        guard operation.canClear else {
            return
        }

        guard let idx = operations.indexOf(operation) else {
            return
        }

        operations.removeAtIndex(idx)
        didRemoveOperation?(index: idx, operation: operation)
    }

    func retry(operation: Operation) {
        guard let idx = operations.indexOf(operation) else {
            return
        }

        guard let newOp = operation.copyForRetry() else {
            return
        }

        operations.replaceRange(idx...idx, with: [ newOp ])
        operationQueue.addOperation(newOp)
    }

    func requeue() {
        for operation in operations {
            if operation.userState == .Queued && !operation.hasStarted {
                operation.cancel()
                retry(operation)
            }
        }
    }

    func add(operation: Operation) {
        operation.paused = paused
        operationQueue.addOperation(operation)
        reload()
    }

    func pauseAll() {
        if paused {
            return
        }

        paused = true

        for operation in operations {
            operation.pause()
        }
    }

    func resumeAll() {
        if paused == false {
            return
        }

        paused = false

        for operation in operations {
            operation.resume()
        }
    }

    func clearAll() {
        for operation in operations {
            guard operation.canClear else {
                continue
            }

            if let idx = operations.indexOf(operation) {
                operations.removeAtIndex(idx)
                didRemoveOperation?(index: idx, operation: operation)
            }
        }
    }
    
    func cancelAll() {
        operationQueue.cancelAllOperations()
    }

    subscript(index: Int) -> Operation {
        return operations[index]
    }

    var count: Int {
        return operations.count
    }
    
}
