//
//  MonthlyMoneyUITests.swift
//  MonthlyMoneyUITests
//
//  Created by Roger Nolan on 26/02/2026.
//

import XCTest

final class MonthlyMoneyUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testIPadShowsMonthDailyAndWoMValues() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(chipValue(in: app, id: "month-chip-current-balance-value").waitForExistence(timeout: 5))
        XCTAssertTrue(chipValue(in: app, id: "month-chip-current-balance-value").isHittable)
        XCTAssertTrue(chipValue(in: app, id: "month-chip-projected-balance-value").exists)
        XCTAssertTrue(chipValue(in: app, id: "month-chip-outgoings-due-value").exists)
        XCTAssertTrue(chipValue(in: app, id: "month-chip-credits-due-value").exists)

        let dailyTab = tabItem(in: app, label: "Daily")
        XCTAssertTrue(dailyTab.waitForExistence(timeout: 5))
        dailyTab.tap()

        XCTAssertTrue(chipValue(in: app, id: "daily-chip-budget-value").waitForExistence(timeout: 5))
        XCTAssertTrue(chipValue(in: app, id: "daily-chip-budget-value").isHittable)
        XCTAssertTrue(chipValue(in: app, id: "daily-chip-average-budget-value").exists)
        XCTAssertTrue(chipValue(in: app, id: "daily-chip-current-balance-value").exists)
        XCTAssertTrue(chipValue(in: app, id: "daily-chip-ahead-behind-value").exists)
        XCTAssertTrue(chipValue(in: app, id: "daily-chip-current-daily-budget-value").exists)
        XCTAssertTrue(chipValue(in: app, id: "daily-chip-days-until-payday-value").exists)

        let womTab = tabItem(in: app, label: "WoM")
        XCTAssertTrue(womTab.waitForExistence(timeout: 5))
        womTab.tap()

        XCTAssertTrue(chipValue(in: app, id: "wom-chip-annual-total-value").waitForExistence(timeout: 5))
        XCTAssertTrue(chipValue(in: app, id: "wom-chip-monthly-average-value").exists)
        XCTAssertTrue(chipValue(in: app, id: "wom-chip-pending-total-value").exists)
        XCTAssertTrue(chipValue(in: app, id: "wom-chip-remaining-average-value").exists)

        XCTAssertTrue(app.staticTexts["No items"].exists)

        let pendingFilter = app.buttons["Pending"].firstMatch
        XCTAssertTrue(pendingFilter.exists)
        pendingFilter.tap()
    }

    private func chipValue(in app: XCUIApplication, id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func tabItem(in app: XCUIApplication, label: String) -> XCUIElement {
        let candidates = [
            app.tabBars.buttons[label].firstMatch,
            app.tabBars.cells[label].firstMatch,
            app.buttons[label].firstMatch,
            app.cells[label].firstMatch,
            app.otherElements[label].firstMatch
        ]
        for candidate in candidates where candidate.exists {
            return candidate
        }
        return candidates.last!
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
