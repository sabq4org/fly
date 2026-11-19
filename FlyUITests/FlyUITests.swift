import XCTest

final class FlyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testEmptyStateOpensFlightForm() {
        launch(with: "-test-empty")

        let addFlight = element(withIdentifier: "addFlight")
        XCTAssertTrue(addFlight.waitForExistence(timeout: 3), "The empty state should offer an add-flight action")
        addFlight.tap()

        XCTAssertTrue(element(withIdentifier: "flightForm").waitForExistence(timeout: 3))
    }

    func testActiveFlightShowsSampleTicket() {
        launch(with: "-test-active")

        XCTAssertTrue(element(withIdentifier: "ticket").waitForExistence(timeout: 3))
        XCTAssertTrue(element(withIdentifier: "booking").exists)
        XCTAssertTrue(element(withIdentifier: "seat").exists)
    }

    func testActiveFlightCanEditSeatLocally() {
        launch(with: "-test-active")

        let editTrip = element(withIdentifier: "editTrip")
        XCTAssertTrue(editTrip.waitForExistence(timeout: 3))
        editTrip.tap()

        XCTAssertTrue(element(withIdentifier: "flightForm").waitForExistence(timeout: 3))
        let seat = app.textFields["seat"]
        XCTAssertTrue(seat.waitForExistence(timeout: 3))
        XCTAssertEqual(seat.elementType, .textField, "The seat control should be editable in the flight form")

        seat.tap()
        seat.clearAndType("12A")
        element(withIdentifier: "saveTrip").tap()

        XCTAssertTrue(element(withIdentifier: "ticket").waitForExistence(timeout: 3))
        XCTAssertTrue(element(withIdentifier: "seat").waitForExistence(timeout: 3))
        let savedSeat = element(withIdentifier: "seat")
        XCTAssertTrue(
            savedSeat.valueAsString.contains("12A") || savedSeat.label.contains("12A"),
            "The saved seat should be visible in either the control value or its accessibility label"
        )
    }

    func testUpcomingFlightShowsSummary() {
        launch(with: "-test-upcoming")

        XCTAssertTrue(element(withIdentifier: "summary").waitForExistence(timeout: 3))
        XCTAssertFalse(element(withIdentifier: "ticket").exists)
    }

    func testDelayedFlightKeepsTicketAndShowsDelay() {
        launch(with: "-test-delayed")

        XCTAssertTrue(element(withIdentifier: "ticket").exists)
        XCTAssertTrue(element(withIdentifier: "delayMessage").waitForExistence(timeout: 3))
        XCTAssertFalse(element(withIdentifier: "summary").exists)
    }

    func testManualFlightPersistsAfterRelaunch() {
        launch(with: "-test-empty")

        let addFlight = element(withIdentifier: "addFlight")
        XCTAssertTrue(addFlight.waitForExistence(timeout: 3))
        addFlight.tap()
        XCTAssertTrue(element(withIdentifier: "flightForm").waitForExistence(timeout: 3))

        fill(identifier: "originCode", with: "RUH")
        fill(identifier: "destinationCode", with: "JED")
        fill(identifier: "flightNumber", with: "SV101")
        element(withIdentifier: "saveTrip").tap()
        XCTAssertTrue(element(withIdentifier: "ticket").waitForExistence(timeout: 3))

        // Resume the same test store. This intentionally does not pass -test-empty,
        // so a successful assertion proves the manually entered flight was persisted.
        app.terminate()
        launch(with: "-test-resume")
        XCTAssertTrue(element(withIdentifier: "ticket").waitForExistence(timeout: 3))
    }

    // Keep this lookup independent of whether the app uses a button, text field,
    // or a container as the accessibility element for a field.
    private func element(withIdentifier identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func launch(with argument: String) {
        app.launchArguments = [argument]
        app.launch()
    }

    private func fill(identifier: String, with text: String) {
        let field = element(withIdentifier: identifier)
        XCTAssertTrue(field.waitForExistence(timeout: 3), "Missing form field: \(identifier)")
        field.tap()
        field.clearAndType(text)
    }
}

private extension XCUIElement {
    var valueAsString: String {
        (value as? String) ?? ""
    }

    func clearAndType(_ text: String) {
        if let currentValue = value as? String, !currentValue.isEmpty, currentValue != placeholderValue {
            for _ in currentValue {
                typeText(XCUIKeyboardKey.delete.rawValue)
            }
        }
        typeText(text)
    }
}
