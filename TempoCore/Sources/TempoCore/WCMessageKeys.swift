import Foundation

public enum WCMessageKeys {
    public static let heartRate = "heartRate"
    public static let hrv = "hrv"
    public static let stressScore = "stressScore"
    public static let timestamp = "timestamp"
    public static let isMonitoring = "isMonitoring"
    public static let breathingSessionFinished = "breathingSessionFinished"
    /// Phone → Watch 推送的派生指标快照 JSON
    public static let watchSnapshotJSON = "watchSnapshotJSON"
    /// Watch → Phone 主动请求最新缓存快照
    public static let watchRequestSnapshot = "watchRequestSnapshot"
    /// Watch → Phone 通过现有 Tempo 后端回复一条关怀
    public static let watchCareReplyMessage = "watchCareReplyMessage"
    public static let watchCareFriendUserID = "watchCareFriendUserID"
    public static let watchCareEventID = "watchCareEventID"
    /// Phone → Watch sendMessage 回执
    public static let watchCareReplySucceeded = "watchCareReplySucceeded"
    public static let watchCareReplyError = "watchCareReplyError"
}
