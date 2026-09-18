# 拾光 iOS 1.0 — 原生工程预览版

只有 Windows：请先看 WINDOWS-START-HERE.md。已加入 GitHub Actions 云端 Mac 编译配置，可生成供本地签名用的未签名 IPA；尚未实际执行云端构建。

Swift + UIKit + Photos，最低 iOS 15，支持 iPhone 和 iPad。工程无第三方依赖，无需 CocoaPods、Swift Package 或生成服务。直接打开 Shiguang.xcodeproj。

## 本次交付状态

本包是源代码和 Xcode 工程，不是可点击安装的 IPA。交付环境没有 macOS、Xcode、iOS SDK 或苹果签名证书；尚未进行 Swift/iOS 编译、模拟器验证或 iPhone 真机验证。工程结构、资源及权限配置已做静态检查。必须在 Mac 的 Xcode 中先构建并验证，再安装到手机；不应将本包描述为已通过实机测试的正式版。

## 安装到自己的 iPhone

1. 在支持相应 Xcode 版本的 Mac 上安装 Xcode；建议 Xcode 16 或更新版本。旧 Mac 是否可用取决于其 macOS 和所需 Xcode，不取决于 iPhone 的最低系统版本。
2. 解压，打开 Shiguang.xcodeproj。选择 Shiguang target → Signing & Capabilities，勾选 Automatically manage signing，选择自己的 Team。
3. 如果包标识被占用，将 cn.shiguang.photos.ios 改为自己唯一的 Bundle Identifier，例如 com.yourname.shiguang。以后更新要保持相同标识和签名团队。
4. 连接并信任 iPhone，在 Xcode 选择该设备，按 Run。按系统提示启用 Developer Mode、信任开发者；权限必须由机主在设备上同意。
5. 首次允许照片访问。全部照片权限才能整理整个图库；有限访问只显示已选择的照片。菜单可调整有限访问或打开系统设置。

免费 Apple Account 的 Personal Team 可用于自己的设备测试，但描述文件 7 天到期，需要重新构建安装。TestFlight / App Store 分发需要 Apple Developer Program、签名和 App Store Connect 流程。本次没有上传、发布或提供 TestFlight 链接，也没有使用你的账号或证书。

苹果官方说明：https://developer.apple.com/help/account/basics/about-your-developer-account

## 使用

- 默认全屏照片；轻点显示或隐藏工具栏。无权限和无照片时显示说明。
- 左划下一张，右划上一张，上划加入待删除；达到 25 张集中调用系统删除确认。
- 右下角垃圾桶里的数字是待删除数量；左下角撤回。上划只是标记，系统确认前不会删除。
- 双指撑开可放大到 8 倍，放大后单指拖动查看；图片载入分辨率有限，不保证原图像素级细节。
- 双指捏小到原尺寸以下，展开拍摄当天照片。继续捏小为三排，撑开为两排，再撑开返回原来的随机照片。无拍摄日期时无法展开。
- 当天模式左右惯性滚动，上划手指下的照片标记删除，轻点显示或隐藏工具。工具位置保持不变。
- 进入当天模式仅把入口照片记为 1 张；当天内部浏览或标记不额外计数，同一批次重复进入同一入口不重复计数。到 25 张后退出当天模式再集中处理，也可随时点击垃圾桶。
- 进出当天模式提供轻触反馈，是否实际震动取决于设备与系统设置。
- Baby blue 图标和按钮，底部两个 58pt 圆形按钮使用安全区域定位。
- 随机顺序、待删除标记和本轮计数保存在本机 UserDefaults，不与安卓版本同步。

## 删除与隐私

使用 Photos 官方接口请求删除，保留 iOS 系统确认，不增加重复的应用删除确认。取消或失败保留待删除标记。照片恢复遵循系统“最近删除”的规则。

应用没有账户、广告、统计和自建服务器，也不向开发者上传照片。对于尚未下载到本机的 iCloud 照片，允许系统 Photos 下载以便浏览，会使用网络。仅处理图片，Live Photo 和动图以静态图预览；不处理视频。不要用珍贵照片作为首次测试对象。

## 构建验证（需 Mac）

```sh
xcodebuild -project Shiguang.xcodeproj -scheme Shiguang -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

先在模拟器导入测试照片，验证授权、随机左右浏览、放大、当天两/三排、惯性、单次计数、25 张边界、取消删除和确认删除。再在 iPhone 检查手势、底部按钮安全区、横屏、切后台、有限照片权限、iCloud 下载和震动。模拟器不能替代真机签名与触感验证。

维护：make_project.py 使用 Python 3 标准库重新生成 project.pbxproj 和 Info.plist；常规使用无需运行。不要把签名私钥或 Apple Account 密码放进工程。
