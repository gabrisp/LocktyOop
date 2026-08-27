import CoreData
import Foundation

enum ChildDiffSync {
    /// Upserts `domainItems` against `existing` child managed objects, matching by UUID.
    /// Any existing child not present in `domainItems` is deleted from `context`.
    static func apply<Entity: NSManagedObject, Domain>(
        context: NSManagedObjectContext,
        domainItems: [Domain],
        domainID: (Domain) -> UUID,
        existing: Set<Entity>,
        entityID: (Entity) -> UUID,
        makeNew: (NSManagedObjectContext) -> Entity,
        apply: (Entity, Domain) throws -> Void
    ) rethrows {
        var existingByID = Dictionary(uniqueKeysWithValues: existing.map { (entityID($0), $0) })
        for domainItem in domainItems {
            let id = domainID(domainItem)
            if let match = existingByID.removeValue(forKey: id) {
                try apply(match, domainItem)
            } else {
                let created = makeNew(context)
                try apply(created, domainItem)
            }
        }
        for leftover in existingByID.values {
            context.delete(leftover)
        }
    }
}
