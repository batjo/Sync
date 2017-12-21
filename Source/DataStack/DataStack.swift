import Foundation
import CoreData

@objc public enum DataStackStoreType: Int {
    case inMemory, sqLite

    var type: String {
        switch self {
        case .inMemory:
            return NSInMemoryStoreType
        case .sqLite:
            return NSSQLiteStoreType
        }
    }
}

@objc public class DataStack: NSObject {
    private var storeType = DataStackStoreType.sqLite

    private var storeName: String?

    private var modelName = ""

    private var modelBundle = Bundle.main

    private var model: NSManagedObjectModel

    private var containerURL = URL.directoryURL()

    fileprivate let saveBubbleDispatchGroup = DispatchGroup()

    /**
     Primary persisting background managed object context. This is the top level context that possess an
     `NSPersistentStoreCoordinator` and saves changes to disk on a background queue.

     Fetching, Inserting, Deleting or Updating managed objects should occur on a child of this context rather than directly.

     note: `NSBatchUpdateRequest` and `NSAsynchronousFetchRequest` require a context with a persistent store connected directly.
     */
    public private(set) lazy var privateQueueContext: NSManagedObjectContext = {
        return self.constructPersistingContext()
    }()
    private func constructPersistingContext() -> NSManagedObjectContext {
        let managedObjectContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        managedObjectContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyStoreTrumpMergePolicyType)
        managedObjectContext.name = "Primary Private Queue Context (Persisting Context)"
        managedObjectContext.persistentStoreCoordinator = self.persistentStoreCoordinator
        return managedObjectContext
    }

    /**
     The main queue context for any work that will be performed on the main queue.
     Its parent context is the primary private queue context that persist the data to disk.
     Making a `save()` call on this context will automatically trigger a save on its parent via `NSNotification`.
     */
    @objc public private(set) lazy var mainContext: NSManagedObjectContext = {
        return self.constructMainContext()
    }()
    private func constructMainContext() -> NSManagedObjectContext {
        var managedObjectContext: NSManagedObjectContext!
        let setup: () -> Void = {
            managedObjectContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            managedObjectContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyStoreTrumpMergePolicyType)
            managedObjectContext.parent = self.privateQueueContext
            managedObjectContext.automaticallyMergesChangesFromParent = true

            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(DataStack.contextDidSaveNotification(_:)),
                                                   name: NSNotification.Name.NSManagedObjectContextDidSave,
                                                   object: managedObjectContext)
        }
        // Always create the main-queue ManagedObjectContext on the main queue.
        if !Thread.isMainThread {
            DispatchQueue.main.sync {
                setup()
            }
        } else {
            setup()
        }
        return managedObjectContext
    }

    /**
     The context for the main queue. Please do not use this to mutate data, use `performBackgroundTask`
     instead.
     */
    @objc public var viewContext: NSManagedObjectContext {
        return self.mainContext
    }

    @objc public private(set) lazy var persistentStoreCoordinator: NSPersistentStoreCoordinator = {
        let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: self.model)
        try! persistentStoreCoordinator.addPersistentStore(storeType: self.storeType, bundle: self.modelBundle, modelName: self.modelName, storeName: self.storeName, containerURL: self.containerURL)

        return persistentStoreCoordinator
    }()

    /**
     Initializes a DataStack using the bundle name as the model name, so if your target is called ModernApp,
     it will look for a ModernApp.xcdatamodeld.
     */
    @objc public override init() {
        let bundle = Bundle.main
        if let bundleName = bundle.infoDictionary?["CFBundleName"] as? String {
            self.modelName = bundleName
        }
        self.model = NSManagedObjectModel(bundle: self.modelBundle, name: self.modelName)

        super.init()
    }

    /**
     Initializes a DataStack using the provided model name.
     - parameter modelName: The name of your Core Data model (xcdatamodeld).
     */
    @objc public init(modelName: String) {
        self.modelName = modelName
        self.model = NSManagedObjectModel(bundle: self.modelBundle, name: self.modelName)

        super.init()
    }

    /**
     Initializes a DataStack using the provided model name, bundle and storeType.
     - parameter modelName: The name of your Core Data model (xcdatamodeld).
     - parameter storeType: The store type to be used, you have .InMemory and .SQLite, the first one is memory
     based and doesn't save to disk, while the second one creates a .sqlite file and stores things there.
     */
    @objc public init(modelName: String, storeType: DataStackStoreType) {
        self.modelName = modelName
        self.storeType = storeType
        self.model = NSManagedObjectModel(bundle: self.modelBundle, name: self.modelName)

        super.init()
    }

    /**
     Initializes a DataStack using the provided model name, bundle and storeType.
     - parameter modelName: The name of your Core Data model (xcdatamodeld).
     - parameter bundle: The bundle where your Core Data model is located, normally your Core Data model is in
     the main bundle but when using unit tests sometimes your Core Data model could be located where your tests
     are located.
     - parameter storeType: The store type to be used, you have .InMemory and .SQLite, the first one is memory
     based and doesn't save to disk, while the second one creates a .sqlite file and stores things there.
     */
    @objc public init(modelName: String, bundle: Bundle, storeType: DataStackStoreType) {
        self.modelName = modelName
        self.modelBundle = bundle
        self.storeType = storeType
        self.model = NSManagedObjectModel(bundle: self.modelBundle, name: self.modelName)

        super.init()
    }

    /**
     Initializes a DataStack using the provided model name, bundle, storeType and store name.
     - parameter modelName: The name of your Core Data model (xcdatamodeld).
     - parameter bundle: The bundle where your Core Data model is located, normally your Core Data model is in
     the main bundle but when using unit tests sometimes your Core Data model could be located where your tests
     are located.
     - parameter storeType: The store type to be used, you have .InMemory and .SQLite, the first one is memory
     based and doesn't save to disk, while the second one creates a .sqlite file and stores things there.
     - parameter storeName: Normally your file would be named as your model name is named, so if your model
     name is AwesomeApp then the .sqlite file will be named AwesomeApp.sqlite, this attribute allows your to
     change that.
     */
    @objc public init(modelName: String, bundle: Bundle, storeType: DataStackStoreType, storeName: String) {
        self.modelName = modelName
        self.modelBundle = bundle
        self.storeType = storeType
        self.storeName = storeName
        self.model = NSManagedObjectModel(bundle: self.modelBundle, name: self.modelName)

        super.init()
    }

    /**
     Initializes a DataStack using the provided model name, bundle, storeType and store name.
     - parameter modelName: The name of your Core Data model (xcdatamodeld).
     - parameter bundle: The bundle where your Core Data model is located, normally your Core Data model is in
     the main bundle but when using unit tests sometimes your Core Data model could be located where your tests
     are located.
     - parameter storeType: The store type to be used, you have .InMemory and .SQLite, the first one is memory
     based and doesn't save to disk, while the second one creates a .sqlite file and stores things there.
     - parameter storeName: Normally your file would be named as your model name is named, so if your model
     name is AwesomeApp then the .sqlite file will be named AwesomeApp.sqlite, this attribute allows your to
     change that.
     - parameter containerURL: The container URL for the sqlite file when a store type of SQLite is used.
     */
    @objc public init(modelName: String, bundle: Bundle, storeType: DataStackStoreType, storeName: String, containerURL: URL) {
        self.modelName = modelName
        self.modelBundle = bundle
        self.storeType = storeType
        self.storeName = storeName
        self.containerURL = containerURL
        self.model = NSManagedObjectModel(bundle: self.modelBundle, name: self.modelName)

        super.init()
    }

    /**
     Initializes a DataStack using the provided model name, bundle and storeType.
     - parameter model: The model that we'll use to set up your DataStack.
     - parameter storeType: The store type to be used, you have .InMemory and .SQLite, the first one is memory
     based and doesn't save to disk, while the second one creates a .sqlite file and stores things there.
     */
    @objc public init(model: NSManagedObjectModel, storeType: DataStackStoreType) {
        self.model = model
        self.storeType = storeType

        let bundle = Bundle.main
        if let bundleName = bundle.infoDictionary?["CFBundleName"] as? String {
            self.storeName = bundleName
        }

        super.init()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /**
     Returns a new `NSManagedObjectContext` as a child of the main queue context.

     Calling `save()` on this managed object context will automatically trigger a save on its parent context via `NSNotification` observing.

     - parameter type: The NSManagedObjectContextConcurrencyType of the new context.
     **Note** this function will trap on a preconditionFailure if you attempt to create a MainQueueConcurrencyType context from a background thread.
     Default value is .PrivateQueueConcurrencyType
     - parameter name: A name for the new context for debugging purposes. Defaults to *Main Queue Context Child*

     - returns: `NSManagedObjectContext` The new worker context.
     */
    public func newChildContext(type: NSManagedObjectContextConcurrencyType = .privateQueueConcurrencyType,
                                name: String? = "Main Queue Context Child") -> NSManagedObjectContext {
        if type == .mainQueueConcurrencyType && !Thread.isMainThread {
            preconditionFailure("Main thread MOCs must be created on the main thread")
        }

        let moc = NSManagedObjectContext(concurrencyType: type)
        moc.mergePolicy = NSMergePolicy(merge: .mergeByPropertyStoreTrumpMergePolicyType)
        moc.parent = mainContext
        moc.automaticallyMergesChangesFromParent = true
        moc.name = name

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(contextDidSaveNotification(_:)),
                                               name: NSNotification.Name.NSManagedObjectContextDidSave,
                                               object: moc)
        return moc
    }

    /**
     Returns a background context perfect for data mutability operations.
     - parameter operation: The block that contains the created background context.
     */
    @objc public func performInNewBackgroundContext(_ operation: @escaping (_ backgroundContext: NSManagedObjectContext) -> Void) {
        let context = self.mainContext
        let contextBlock: @convention(block) () -> Void = {
            operation(context)
        }
        let blockObject: AnyObject = unsafeBitCast(contextBlock, to: AnyObject.self)
        context.perform(DataStack.performSelectorForBackgroundContext(), with: blockObject)
    }

    private static func performSelectorForBackgroundContext() -> Selector {
        return TestCheck.isTesting ? NSSelectorFromString("performBlockAndWait:") : NSSelectorFromString("performBlock:")
    }

    // Drops the database.
    @objc public func drop(completion: ((_ error: NSError?) -> Void)? = nil) {
        self.mainContext.performAndWait {
            self.mainContext.reset()

            self.persistentStoreCoordinator.performAndWait {
                for store in self.persistentStoreCoordinator.persistentStores {
                    guard let storeURL = store.url else { continue }
                    try! self.oldDrop(storeURL: storeURL)
                }

                DispatchQueue.main.async {
                    completion?(nil)
                }
            }
        }
    }

    // Required for iOS 8 Compatibility.
    func oldDrop(storeURL: URL) throws {
        let storePath = storeURL.path
        let sqliteFile = (storePath as NSString).deletingPathExtension
        let fileManager = FileManager.default

        self.mainContext.reset()

        let shm = sqliteFile + ".sqlite-shm"
        if fileManager.fileExists(atPath: shm) {
            do {
                try fileManager.removeItem(at: NSURL.fileURL(withPath: shm))
            } catch let error as NSError {
                throw NSError(info: "Could not delete persistent store shm", previousError: error)
            }
        }

        let wal = sqliteFile + ".sqlite-wal"
        if fileManager.fileExists(atPath: wal) {
            do {
                try fileManager.removeItem(at: NSURL.fileURL(withPath: wal))
            } catch let error as NSError {
                throw NSError(info: "Could not delete persistent store wal", previousError: error)
            }
        }

        if fileManager.fileExists(atPath: storePath) {
            do {
                try fileManager.removeItem(at: storeURL)
            } catch let error as NSError {
                throw NSError(info: "Could not delete sqlite file", previousError: error)
            }
        }
    }

    /// Sends a request to all the persistent stores associated with the receiver.
    ///
    /// - Parameters:
    ///   - request: A fetch, save or delete request.
    ///   - context: The context against which request should be executed.
    /// - Returns: An array containing managed objects, managed object IDs, or dictionaries as appropriate for a fetch request; an empty array if request is a save request, or nil if an error occurred.
    /// - Throws: If an error occurs, upon return contains an NSError object that describes the problem.
    @objc public func execute(_ request: NSPersistentStoreRequest, with context: NSManagedObjectContext) throws -> Any {
        return try self.persistentStoreCoordinator.execute(request, with: context)
    }

}

fileprivate extension DataStack {
    @objc fileprivate func contextDidSaveNotification(_ notification: Notification) {
        guard let notificationMOC = notification.object as? NSManagedObjectContext else {
            assertionFailure("Notification posted from an object other than an NSManagedObjectContext")
            return
        }
        guard let parentContext = notificationMOC.parent else {
            return
        }

        saveBubbleDispatchGroup.enter()
        parentContext.saveContext() { _ in
            self.saveBubbleDispatchGroup.leave()
        }
    }
}

extension NSPersistentStoreCoordinator {
    func addPersistentStore(storeType: DataStackStoreType, bundle: Bundle, modelName: String, storeName: String?, containerURL: URL) throws {
        let filePath = (storeName ?? modelName) + ".sqlite"
        switch storeType {
        case .inMemory:
            do {
                try self.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil)
            } catch let error as NSError {
                throw NSError(info: "There was an error creating the persistentStoreCoordinator for in memory store", previousError: error)
            }

            break
        case .sqLite:
            let storeURL = containerURL.appendingPathComponent(filePath)
            let storePath = storeURL.path

            let shouldPreloadDatabase = !FileManager.default.fileExists(atPath: storePath)
            if shouldPreloadDatabase {
                if let preloadedPath = bundle.path(forResource: modelName, ofType: "sqlite") {
                    let preloadURL = URL(fileURLWithPath: preloadedPath)

                    do {
                        try FileManager.default.copyItem(at: preloadURL, to: storeURL)
                    } catch let error as NSError {
                        throw NSError(info: "Oops, could not copy preloaded data", previousError: error)
                    }
                }
            }

            let options = [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true]
            do {
                try self.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: options)
            } catch {
                do {
                    try FileManager.default.removeItem(atPath: storePath)
                    do {
                        try self.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: options)
                    } catch let addPersistentError as NSError {
                        throw NSError(info: "There was an error creating the persistentStoreCoordinator", previousError: addPersistentError)
                    }
                } catch let removingError as NSError {
                    throw NSError(info: "There was an error removing the persistentStoreCoordinator", previousError: removingError)
                }
            }

            let shouldExcludeSQLiteFromBackup = storeType == .sqLite && TestCheck.isTesting == false
            if shouldExcludeSQLiteFromBackup {
                do {
                    try (storeURL as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
                } catch let excludingError as NSError {
                    throw NSError(info: "Excluding SQLite file from backup caused an error", previousError: excludingError)
                }
            }

            break
        }
    }
}

extension NSManagedObjectModel {
    convenience init(bundle: Bundle, name: String) {
        if let momdModelURL = bundle.url(forResource: name, withExtension: "momd") {
            self.init(contentsOf: momdModelURL)!
        } else if let momModelURL = bundle.url(forResource: name, withExtension: "mom") {
            self.init(contentsOf: momModelURL)!
        } else {
            self.init()
        }
    }
}

extension NSError {
    convenience init(info: String, previousError: NSError?) {
        if let previousError = previousError {
            var userInfo = previousError.userInfo
            if let _ = userInfo[NSLocalizedFailureReasonErrorKey] {
                userInfo["Additional reason"] = info
            } else {
                userInfo[NSLocalizedFailureReasonErrorKey] = info
            }

            self.init(domain: previousError.domain, code: previousError.code, userInfo: userInfo)
        } else {
            var userInfo = [String: String]()
            userInfo[NSLocalizedDescriptionKey] = info
            self.init(domain: "com.SyncDB.DataStack", code: 9999, userInfo: userInfo)
        }
    }
}

extension URL {
    fileprivate static func directoryURL() -> URL {
        #if os(tvOS)
            return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).last!
        #else
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last!
        #endif
    }
}

extension DataStack {

    // MARK: - Operation Result Types

    /// Result containing either an instance of `NSPersistentStoreCoordinator` or `ErrorType`
    public enum CoordinatorResult {
        /// A success case with associated `NSPersistentStoreCoordinator` instance
        case success(NSPersistentStoreCoordinator)
        /// A failure case with associated `ErrorType` instance
        case failure(Swift.Error)
    }
    /// Result containing either an instance of `NSManagedObjectContext` or `ErrorType`
    public enum BatchContextResult {
        /// A success case with associated `NSManagedObjectContext` instance
        case success(NSManagedObjectContext)
        /// A failure case with associated `ErrorType` instance
        case failure(Swift.Error)
    }
    /// Result containing either an instance of `CoreDataStack` or `ErrorType`
    public enum SetupResult {
        /// A success case with associated `CoreDataStack` instance
        case success(DataStack)
        /// A failure case with associated `ErrorType` instance
        case failure(Swift.Error)
    }
    /// Result of void representing `success` or an instance of `ErrorType`
    public enum SuccessResult {
        /// A success case
        case success
        /// A failure case with associated ErrorType instance
        case failure(Swift.Error)
    }
    public typealias SaveResult = SuccessResult
    public typealias ResetResult = SuccessResult
}

