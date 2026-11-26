import Foundation
import MapKit
import CoreLocation

public struct TravelEstimate: Equatable, Sendable {
    public let eventID: String
    public let eventTitle: String
    public let expectedTravelSeconds: TimeInterval
    public let leaveBy: Date
}

@MainActor
public final class TimeToLeaveService: ObservableObject {
    public static let shared = TimeToLeaveService()

    @Published public var isEnabled: Bool = false
    @Published public private(set) var nextEstimate: TravelEstimate?

    private let geocoder = CLGeocoder()

    public init() {}

    public func estimateLeaveTime(for event: CalendarTimeBlock) async -> TravelEstimate? {
        guard isEnabled,
              let address = event.location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !address.isEmpty,
              !address.hasPrefix("http") else {
            return nil
        }

        do {
            let placemarks = try await geocoder.geocodeAddressString(address)
            guard let destinationLoc = placemarks.first?.location else { return nil }

            let request = MKDirections.Request()
            request.source = MKMapItem.forCurrentLocation()
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destinationLoc.coordinate))
            request.transportType = .automobile

            let directions = MKDirections(request: request)
            let response = try await directions.calculateETA()
            let travelSeconds = response.expectedTravelTime
            let leaveBy = event.start.addingTimeInterval(-travelSeconds - 300) // 5-min buffer
            let estimate = TravelEstimate(
                eventID: event.id,
                eventTitle: event.title,
                expectedTravelSeconds: travelSeconds,
                leaveBy: leaveBy
            )
            self.nextEstimate = estimate
            return estimate
        } catch {
            return nil
        }
    }
}
