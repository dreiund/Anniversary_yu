import UIKit
import CloudKit

/// SwiftUI 生命周期不暴露 CloudKit 分享接受回调，桥一层 UIKit delegate。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// 热启动：App 在运行/后台时点开邀请链接
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        SharingManager.accept(cloudKitShareMetadata)
    }

    /// 冷启动：点链接把 App 拉起时 metadata 随连接选项进来
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            SharingManager.accept(metadata)
        }
    }
}
