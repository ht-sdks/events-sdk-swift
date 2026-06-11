import HightouchPush

/// Hightouch NSE entry point. The base class handles:
///  - downloading rich media attachments from hightouch.attachmentUrl
///  - registering dynamic UNNotificationCategory actions from hightouch.actionButtons
class NotificationService: HightouchNotificationServiceExtension {}
