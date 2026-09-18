# Windows 免费账号安装拾光

此包已经配好 GitHub 云端 Mac 编译。无需自己的 Mac，也无需把 Apple 账号或密码交给 GitHub。仍需先完成云端编译，得到 IPA；本 ZIP 本身不能安装到 iPhone。

## 1. 上传工程

登录 https://github.com ，右上角“+” → New repository，名称可填 shiguang-ios。

可选择 Public 或 Private：Public 的代码任何人可以看到，标准 GitHub 托管 runner 免费；Private 使用账户包含的 Actions 额度，额度用完后可能产生费用或停止运行，取决于账户计费设置。只想完全免费、且接受公开这份源码，可以选 Public。此工程不含你的照片或签名私钥。不要上传安卓维护包或个人文件。

下载并解压本包，在新仓库选择 uploading an existing file（或 Add file → Upload files），把解压后的全部文件和文件夹拖入，再 Commit changes。

上传后仓库根目录应直接出现：

- .github/workflows/build-ios.yml
- Shiguang.xcodeproj/
- Shiguang/
- scripts/build-unsigned.sh
- README.md

不要只上传 ZIP，不要在外面再套一层 Shiguang-iOS 文件夹。Windows 上如果没看到 .github 文件夹，请确认解压完整；GitHub 不会从 ZIP 里自动识别 workflow。

## 2. 云端生成 IPA

仓库 → Actions → Build iPhone IPA → Run workflow → Run workflow。

本配置仅手动启动；上传工程不会自动触发。首次可能需要允许 Actions 运行。

等任务变为绿色勾，打开该次任务，在 Artifacts 下载 Shiguang-iPhone-unsigned。解压后得到 Shiguang-unsigned.ipa。

如果红色失败，下载 build-log 或打开 Build unsigned iPhone app 步骤，把第一个 error 及其附近内容发回即可继续修复。这个工程尚未在云端跑过；不能提前保证首次编译成功。

## 3. Windows 签名安装

1. 从 https://sideloadly.io/ 下载 Windows 版 Sideloadly。
2. 按其官网安装要求准备 Apple 的 iTunes / iCloud 驱动；不要把已有软件随意卸载，先核对官网对版本的要求。
3. 数据线连接 iPhone，解锁并点“信任此电脑”。
4. 打开 Sideloadly，选择 iPhone，将 Shiguang-unsigned.ipa 拖进去。
5. 使用自己的免费 Apple Account 登录并开始安装，验证操作只在自己的电脑和苹果设备上完成，不需要给我密码。
6. 按手机提示信任开发者、启用“设置 → 隐私与安全性 → 开发者模式”，重启后确认。选项名称随系统版本可能不同。
7. 打开拾光并授权照片访问。

免费签名通常 7 天到期，需要重新签名刷新；可以按 Sideloadly 文档启用自动刷新，电脑及网络条件要满足要求。保持 Bundle Identifier 和账号一致以便更新；不要先卸载应用，否则整理进度会丢失。免费账号最多同时安装 3 个此类测试应用。

Sideloadly 官网当前标注 iOS 26+，没有单独承诺 iOS 27。此工程也未在 iPhone Air / iOS 27 上验证；若工具不支持你的系统版本，需要等待工具适配，不能通过改后缀解决。

## 当前验证范围

本地通过项目引用、权限 plist、共享 scheme、资源和图标检查，以及 shell 语法检查。
当前对话环境没有 Xcode 或 GitHub 账号连接，因此没有运行云端编译，没有生成 IPA，没有签名、发布或做真机测试。

官方参考：

- https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow
- https://developer.apple.com/help/account/basics/about-your-developer-account
- https://sideloadly.io/
