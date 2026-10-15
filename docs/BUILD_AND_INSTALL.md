# 构建与免费安装路线

核查日期：2026-10-15。Windows 本机没有 Swift、Xcode 或 Apple SDK；云端macOS已完成设备编译和测试，IPA已下载并复核。签名和安装尚未执行，详见CI_RESULTS.md。

## 当前推进路线与真实阻塞

按用户目标推进 **私有 GitHub 仓库 → 免费额度内的云端 macOS 无签名构建 → 下载 IPA 到 Windows → 用户本机免费签名与安装候选验证**。不要求购买Mac，不启用付费服务。前三步已完成，当前具体状态如下：

| 阶段 | 已核查 | 尚缺的最低操作 / 授权 |
| --- | --- | --- |
| GitHub 连接 | 已在连接与浏览器双重核验账号 `sanqianup`，已创建 [私有 FrameGuide 仓库](https://github.com/sanqianup/FrameGuide)，API确认 private 和写入权限 | 创建及源码上传已获准；源码按审查后的提交清单上传。没有提供或读取登录令牌 |
| 免费云编译 | 已核验免费分钟/存储与零额外Actions支出阻断，保留预算不变；两次标准macos-15运行，第二次成功 | 本轮构建完成；后续运行仍需重新核对配额，不放开预算限制 |
| 获取 IPA | 已下载并核验artifact/IPA哈希，检查arm64与iOS设备平台及18.5最低版本，无签名资料 | 可作为后续本地签名候选输入；本轮未安装，见CI_RESULTS.md |
| Windows 安装 | 只读查阅 AltStore Classic 官方 Windows 文档；没有下载安装 | 独立授权选定第三方签名工具及必要依赖安装，由用户本人完成 Apple 登录、设备信任/开发者模式。当前这些操作未授权也未执行；对18.5/27兼容仍需实际验证 |

云端构建出的 IPA **未签名，不能直接安装**。第三方本地签名是候选路线，不能把“CI能编译”当作“Windows已能安装”。若用户不授权第三方签名，则当前无法凭空完成无本地 Mac 的安装；可另行选择已可免费使用的 Mac，但它不是当前云端路线的前置购买要求。

Apple 官方允许 Apple Account 在 Xcode 中使用 Personal Team 进行个人设备测试；无需购买开发者会员。其配置文件有效期为 7 天，过期需重新构建和安装；最多 10 个 App ID、3 台设备、每台最多安装 3 个此类 App。以 [Apple 官方账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account) 为准。

免费签名不等于永久安装，也不会自动续签。未部署后台续签工具。未购买 Mac、云 Mac、开发者会员、API 额度或任何其他服务。

## 云端 macOS 先验证源码（授权后）

1. 获得私有仓库和源码上传授权后，仅上传工程源码，不传输用户照片、Apple资料或 API 密钥。
2. 选标准 GitHub macOS runner，确认其实际 Xcode 支持 iOS 18.5 构建。实际组合查 [Apple Xcode 系统要求表](https://developer.apple.com/xcode/system-requirements)。iOS 27 验证需另有相应 SDK/模拟器/设备，不能由 Deployment Target 自动证明。
3. 免费额度和硬性费用阻断核实后，明确授权一次手动运行 `ci/macos-build.yml.disabled` 所示验证流程。它执行 plist、纯 Swift 测试、无签名模拟器和 iPhone 构建，不调用 Apple 账号或安装。该模板当前仍未激活。
4. 保存实际 `xcodebuild -version`、SDK、测试日志与失败信息。若有编译错误先修复，完成前不得将工程标记为“构建成功”。
5. 如需运行 App-host XCTest，先执行 `xcodebuild -showdestinations -project FrameGuide.xcodeproj -scheme FrameGuide`，再选真实列出的模拟器 ID，执行下面命令；不要照抄不存在的设备名：

```sh
xcodebuild -project FrameGuide.xcodeproj -scheme FrameGuide \
  -destination 'platform=iOS Simulator,id=替换为实际模拟器UUID' \
  CODE_SIGNING_ALLOWED=NO test
```

模拟器不提供真实 iPhone 相机，App 应显示“没有可用的相机输入”，相机测试必须真机完成。纯 Swift 算法测试不需要 Apple 账号。

## Windows 免费签名候选（尚未授权安装）

已只读核对 [AltStore Classic 官方 Windows 安装说明](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows) 和 [使用/续签说明](https://faq.altstore.io/altstore-classic/your-altstore)。官方文档列出 Windows 的 AltServer、Apple来源的 iTunes/iCloud 依赖及用户自身账号/设备步骤；免费 App 约7天需刷新。这里是可验证的候选，不代表本任务推荐或安装已获授权，也不保证 iOS 27 已支持。

若用户明确选择并授权此路线，最低顺序是：先获得成功编译的 unsigned IPA，核验下载文件 SHA-256；再由用户按该工具官方说明自行处理 Apple 账号、设备信任及开发者模式，确认工具及系统兼容后尝试签名安装。Apple 密码、证书、描述文件和设备操作不交给本代理或 CI。不要把官方 App Store 发布、付费会员或第三方付费代签当作默认选项。

目前没有安装 AltServer/AltStore、iTunes/iCloud 或其他签名软件，也没有改动防火墙、系统设备服务、Apple账户或手机设置。用户若选择此路线，需单独授权安装选定官方工具及必要依赖，并自行完成账号和设备操作。重要照片应先导出，避免通过卸载丢失 App 内文件。

## 若另有免费可用的 Mac：用户本人处理官方签名

源码构建通过后，由用户本人在 Xcode 中打开 `FrameGuide.xcodeproj`，选择 `FrameGuide` scheme 和自己的 iPhone，在 Signing & Capabilities 中选 Personal Team 并使用个人唯一 Bundle Identifier。用户自行完成 Apple 账号登录、系统要求的设备信任/开发者模式等操作，再由用户点击 Run。

本任务不操作 Apple 登录、密码、证书、描述文件或开发者模式，也不要求把这些资料发到聊天或 CI。若签名失败，提供去除账号敏感字段的错误文字即可排查。先将重要照片存到系统相册；不要通过卸载 App 来解决续签问题，以免丢失 App 内原图。

## 模板与本次实际 CI

`ci/macos-build.yml.disabled` 不在 GitHub Actions 目录，不会触发。它包含手动事件、无签名编译和纯 Swift 测试；不含远程上传产物、账号或签名凭据。`macos-15` 仅是候选 runner；激活前应检查其可用 Xcode 和目标 SDK。

`tools/prepare-unsigned-ipa.sh` 已在第二次云端运行成功，构建 `.app` 并打包 `Payload/FrameGuide.app`，输出 IPA 及 SHA-256；校验 iPhoneOS/arm64/LC_BUILD_VERSION iOS设备平台，artifact上限50MiB。脚本没有签名或删除旧输出。

`ci/windows-install-artifact.yml.disabled` 是需要产物时的另一个最小模板：纯 Swift 测试、一次 unsigned iPhone build/package、1天 artifact。它同样未激活；`free_budget_checked` 默认 false，只表达用户已完成配额/费用核验的声明，不能替代真实账单核验。产物存储也可能消耗额度，必须一并确认后才可使用。

使用它之前必须取得明确授权并落实以下条件：

- 用户选择远程仓库、代码可见性及是否授权上传源码；当前没有创建仓库或上传授权。
- 用户核对 GitHub 账号免费额度、标准 runner 可用性、预算/付费阻断条件，并明确授权启动一次工作流。
- 公共仓库的标准 GitHub-hosted runner 按官方规则可免费；私有仓库消耗套餐额度，超额可能收费，不能预先保证免费。参见 [GitHub Actions 计费](https://docs.github.com/en/billing/concepts/product-billing/github-actions)。

`.github/workflows/unsigned-device.yml` 是本次实际使用的手动工作流；run38710533910在commit4661d946成功，详见CI_RESULTS.md。没有自动push/PR触发、用户签名凭据或API密钥。

无签名CI成功不能证明Windows免费签名、Personal Team或设备安装可用。私有仓库、源码上传、两次CI及下载核验已完成，没有配置云端用户凭据、安装第三方签名工具或启用Xcode Cloud。

## 继续工作的授权边界

本轮私有仓库上传与有费用前提的云端构建已按批准执行并完成。下一步需要单独授权选择和安装Windows签名工具及必要依赖，账号和手机由用户自行操作；不重复请求已完成的上传许可。API使用独立于免费构建/签名；没有密钥和明确照片确认就不调用，不启用收费模型。
