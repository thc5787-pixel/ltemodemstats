import Foundation
@testable import ModemCore
import Testing

@Test func everythingIsDueOnFirstRun() {
    let schedule = ModemSchedule()
    #expect(schedule.due(at: Date(), lastRun: [:]) == Set(ModemReader.Group.allCases))
}

@Test func groupsFollowTheirIntervals() {
    let schedule = ModemSchedule()
    let start = Date(timeIntervalSince1970: 1000)
    let lastRun = Dictionary(uniqueKeysWithValues: ModemReader.Group.allCases.map { ($0, start) })

    #expect(schedule.due(at: start.addingTimeInterval(4), lastRun: lastRun).isEmpty)
    #expect(schedule.due(at: start.addingTimeInterval(5), lastRun: lastRun) == [.radio])
    #expect(schedule.due(at: start.addingTimeInterval(30), lastRun: lastRun) == [.radio, .sim, .data, .temperature])
    // Device info is read once per connection.
    #expect(!schedule.due(at: start.addingTimeInterval(3600), lastRun: lastRun).contains(.device))
}
