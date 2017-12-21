//
//  NSManagedObjectContext+Extensions.swift
//  CoreDataSMS
//
//  Created by Robert Edwards on 2/23/15.
//  Copyright (c) 2015 Big Nerd Ranch. All rights reserved.
//

import CoreData

public typealias DataStackSaveCompletion = (DataStack.SaveResult) -> Void

/**
 Convenience extension to `NSManagedObjectContext` that ensures that saves to contexts of type
 `MainQueueConcurrencyType` and `PrivateQueueConcurrencyType` are dispatched on the correct GCD queue.
 */
public extension NSManagedObjectContext {

    /**
     Convenience method to synchronously save the `NSManagedObjectContext` if changes are present.
     Method also ensures that the save is executed on the correct queue when using Main/Private queue concurrency types.

     - throws: Errors produced by the `save()` function on the `NSManagedObjectContext`
     */
    public func saveContextAndWait() throws {
        switch concurrencyType {
        case .confinementConcurrencyType:
            try sharedSaveFlow()
        case .mainQueueConcurrencyType,
             .privateQueueConcurrencyType:
            try performAndWaitOrThrow(sharedSaveFlow)
        }
    }

    /**
     Convenience method to asynchronously save the `NSManagedObjectContext` if changes are present.
     Method also ensures that the save is executed on the correct queue when using Main/Private queue concurrency types.

     - parameter completion: Completion closure with a `SaveResult` to be executed upon the completion of the save operation.
     */
    public func saveContext(_ completion: DataStackSaveCompletion? = nil) {
        func saveFlow() {
            do {
                try sharedSaveFlow()
                completion?(.success)
            } catch let saveError {
                completion?(.failure(saveError))
            }
        }

        switch concurrencyType {
        case .confinementConcurrencyType:
            saveFlow()
        case .privateQueueConcurrencyType,
             .mainQueueConcurrencyType:
            perform(saveFlow)
        }
    }

    /**
     Convenience method to synchronously save the `NSManagedObjectContext` if changes are present.
     If any parent contexts are found, they too will be saved synchronously.
     Method also ensures that the save is executed on the correct queue when using Main/Private queue concurrency types.

     - throws: Errors produced by the `save()` function on the `NSManagedObjectContext`
     */
    public func saveContextToStoreAndWait() throws {
        func saveFlow() throws {
            try sharedSaveFlow()
            if let parentContext = parent {
                try parentContext.saveContextToStoreAndWait()
            }
        }

        switch concurrencyType {
        case .confinementConcurrencyType:
            try saveFlow()
        case .mainQueueConcurrencyType,
             .privateQueueConcurrencyType:
            try performAndWaitOrThrow(saveFlow)
        }
    }

    /**
     Convenience method to asynchronously save the `NSManagedObjectContext` if changes are present.
     If any parent contexts are found, they too will be saved asynchronously.
     Method also ensures that the save is executed on the correct queue when using Main/Private queue concurrency types.

     - parameter completion: Completion closure with a `SaveResult` to be executed
     either upon the completion of the top most context's save operation or the first encountered save error.
     */
    public func saveContextToStore(_ completion: DataStackSaveCompletion? = nil) {
        func saveFlow() {
            do {
                try sharedSaveFlow()
                if let parentContext = parent {
                    parentContext.saveContextToStore(completion)
                } else {
                    completion?(.success)
                }
            } catch let saveError {
                completion?(.failure(saveError))
            }
        }

        switch concurrencyType {
        case .confinementConcurrencyType:
            saveFlow()
        case .privateQueueConcurrencyType,
             .mainQueueConcurrencyType:
            perform(saveFlow)
        }
    }

    private func sharedSaveFlow() throws {
        guard hasChanges else {
            return
        }

        try save()
    }

    /**
     Synchronously executes a given function on the receiver’s queue.

     You use this method to safely address managed objects on a concurrent
     queue.

     - attention: This method may safely be called reentrantly.
     - parameter body: The method body to perform on the reciever.
     - returns: The value returned from the inner function.
     - throws: Any error thrown by the inner function. This method should be
     technically `rethrows`, but cannot be due to Swift limitations.
     **/
    public func performAndWaitOrThrow<Return>(_ body: () throws -> Return) rethrows -> Return {
        return try withoutActuallyEscaping(body) { (work) in
            var result: Return!
            var error: Error?

            performAndWait {
                do {
                    result = try work()
                } catch let e {
                    error = e
                }
            }

            if let error = error {
                throw error
            } else {
                return result
            }
        }
    }
}

