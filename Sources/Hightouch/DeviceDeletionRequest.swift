import Foundation

/// The one event `Analytics` still sends while data collection is off: the push module's request
/// to delete this device's record. The push module builds the event from these values, so the
/// check here and the event it sends cannot drift apart.
@_spi(HightouchInternal)
public enum DeviceDeletionRequest {
    public static let eventName = "CEP Push Token Events"
    public static let eventTypeProperty = "provider_event_type"
    public static let eventType = "deleted"

    static func matches(_ event: RawEvent) -> Bool {
        guard let track = event as? TrackEvent, track.event == eventName else { return false }
        return track.properties?.dictionaryValue?[eventTypeProperty] as? String == eventType
    }
}
