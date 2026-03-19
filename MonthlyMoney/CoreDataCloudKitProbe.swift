import CloudKit
import CoreData
import Foundation

enum CoreDataCloudKitProbeScope {
    case privateDatabase
    case sharedDatabase
}

enum CoreDataCloudKitProbe {
    static func makeStoreDescription(
        url: URL,
        scope: CoreDataCloudKitProbeScope,
        containerIdentifier: String
    ) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)

        switch scope {
        case .privateDatabase:
            options.databaseScope = .private
        case .sharedDatabase:
            options.databaseScope = .shared
        }

        description.cloudKitContainerOptions = options
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        return description
    }
}
