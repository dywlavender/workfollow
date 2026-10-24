import XCTest
@testable import WorkFollow

final class ReminderSourcePresentationTests: XCTestCase {
    func testAppleSourceExplainsLocalWriteWithoutClaimingPhoneDelivery() {
        let value = TaskReminderDeliveryPresentation.make(usesApple: true, appleEnabled: true,
            syncStatus: "已写入提醒事项", nativeEnabled: true, nativeAuthorized: true)
        XCTAssertEqual(value.title, "Apple 提醒事项")
        XCTAssertTrue(value.detail.contains("iPhone 接收由 iCloud 完成"))
        XCTAssertFalse(value.needsAttention)
    }
    func testPendingAppleWriteShowsCurrentNativeFallbackAndRetryStatus() {
        let value = TaskReminderDeliveryPresentation.make(usesApple: false, appleEnabled: true,
            syncStatus: "等待写入提醒事项", nativeEnabled: true, nativeAuthorized: true)
        XCTAssertEqual(value.title, "本机通知")
        XCTAssertTrue(value.detail.contains("等待写入提醒事项"))
        XCTAssertFalse(value.needsAttention, "正常等待同步期间仍可由本机提醒，不显示故障状态")
    }
    func testDisabledNativeNotificationsDoNotPromiseAReminder() {
        let value = TaskReminderDeliveryPresentation.make(usesApple: false, appleEnabled: false,
            syncStatus: "未同步", nativeEnabled: false, nativeAuthorized: true)
        XCTAssertEqual(value.title, "提醒待处理")
        XCTAssertTrue(value.needsAttention)
    }
}
