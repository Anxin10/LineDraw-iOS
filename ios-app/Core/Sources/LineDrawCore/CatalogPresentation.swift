import Foundation

/// Immutable view data. Selection changes reuse this instead of rebuilding
/// the scoped record dictionary once for every row and every view accessor.
public struct CatalogPresentation {
    public let records:[String:ParticipationRecord]
    public let all:[Draw]
    public let visible:[Draw]
    public let runnable:[Draw]
    public let cities:[String]
    public let readyCount:Int
    public init(snapshot:DatabaseSnapshot,area:DrawArea,filter:CatalogFilter,now:Date,source:CatalogSource = .funbox) {
        let prefix=LocalDatabase.scope(profile:snapshot.settings.profile,area:area)+"\n"
        let records=Dictionary(uniqueKeysWithValues:snapshot.records.filter{$0.key.hasPrefix(prefix)}.map{(String($0.key.dropFirst(prefix.count)),$0.value)})
        self.records=records
        let all=snapshot.draws.filter{$0.area==area && (area != .website || source.owns($0))}.sorted{$0.ordinal<$1.ordinal}
        self.all=all
        let visible=all.filter{filter.matches($0,recorded:records[$0.activityKey]?.blocksRepeat==true,now:now)}
        self.visible=visible
        self.runnable=visible.filter{$0.runnable(at:now) && records[$0.activityKey]?.blocksRepeat != true}
        self.cities=Array(Set(all.filter{!$0.archived}.map(\.city))).sorted()
        self.readyCount=all.filter{$0.runnable(at:now) && records[$0.activityKey]?.blocksRepeat != true}.count
    }
}
