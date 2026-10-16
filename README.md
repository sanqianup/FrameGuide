# 取景 FrameGuide

独立、个人自用的原生 iPhone 相机工程。目标设备 iPhone 16 Pro / iOS 18.5，Deployment Target 18.5，后续兼容验证覆盖到 iOS 27。项目仅在当前新任务目录内创建，未改动 GeekListing 或其他工程。

**2026-10-16新增点选区域追踪与目标构图引导源码，Windows 21项结构检查通过；本轮46项Swift测试及设备编译尚待macOS执行。** 浏览器连接关闭，暂不能核验免费额度或手动启动CI。先前 `ec96955842f9a76cec1f6c09b93435d0fc827c23` 的35项测试和设备构建成功，不能替代本轮结果；旧Release保持可用但不包含新功能。详见 [本轮说明](docs/GUIDED_COMPOSITION.md)、[CI结果](docs/CI_RESULTS.md) 与 [验收记录](docs/VERIFICATION.md)。

## 已实现的源码范围

- AVFoundation 原生预览，系统会话独立串行队列；30fps 配置偏好，实际流畅度待真机验收。
- 按设备实际发现的主摄、超广角、长焦和前置镜头切换；轻点对焦；物理镜头切换允许短暂重配置。
- 拍摄保留 AVCapturePhoto 输出的完整 HEIC/JPEG 字节；独立本机文件、SHA-256 校验；用户手动添加原图或副本到系统相册。
- Core Motion 水平读数、按屏幕方向校准、移动稳定度判断；手机朝正上/下时不显示不可信水平角度。
- Apple Vision 人脸/人体/显著区域与独立构图规则；平滑、固定三分线目标、提示防抖、失效过期、镜像方向修正。
- 用户点选区域后使用本地Vision追踪，追踪与低频构图决策分开；固定目标框、二维位置提示、持续稳定到位反馈、退出引导、明确确认的数字放大及还原。运动/丢失/过期时重新点选；没有自动移机、自动变焦或自动拍照。
- 自然、柔和人像、清透景物三种本地有限参数滤镜，取景仅推荐，拍后手动应用并可撤销；不是胶片或生成式模型。
- 本地自然调色、原图对比、最多 20 步撤销；全分辨率副本导出；原图不被覆盖。撤销历史只保留在本次照片页面。
- 摄像头权限拒绝、会话中断、媒体服务重置、旋转、后台停机及恢复、低电量/热状态/内存警告降级路径。
- 可编辑的小米官方 MiMo V2.6 Pro 模板；独立看图建议与可选图像编辑端点、模型、鉴权头、超时及连接测试；本机 Keychain 保存密钥。
- 默认关闭云端和照片上传；取景时可点“分析当前画面”，先冻结最长边 1024px、无 EXIF 的缩略图供确认，再异步请求建议。每次请求至少间隔 8 秒；全局单请求，无自动重试，移动、换镜头、旋转、拍摄、页面退出或后台后取消并拒绝旧结果。拍后照片也可独立请求。
- 性能读数页面：视频回调帧率、Vision 耗时、引导间隔、云端端到端延迟、旧响应丢弃数和热状态。实际显示帧率必须用 Instruments 测量。

## 功能边界

本地构图提示是 Vision 检测加规则，不是摄影师审美模型，也不推断精确三维移机距离。显著区域不代表识别出了某种物体。自然调色是像素布局不变的 Core Image 颜色处理，不是生成式精修。原图指系统相机编码输出，**不是 RAW/ProRAW，也不承诺 48MP**；首版偏好约 12MP 以降低延迟和内存。

取景中的手动云端建议绑定冻结帧、镜头、方向和场景代次；静态照片建议绑定 PhotoRecord。没有实现连续自动上传。确认超过 15 秒或响应对应帧超过 30 秒即失效。粗粒度场景变化来自姿态及 8×8 亮度差异检测，不能保证识别所有语义变化。MiMo 模板未启用、没有密钥、没有服务调用。取景建议不自动改变相机参数；拍后受限调色参数可本机渲染；生成式编辑使用另一服务，默认不可用。模型质量、响应时间和费用不作虚假承诺。

没有集成 Adacrop 权重，没有复制 LiveCapture 源码，没有引入 YOYO 账号、订阅、分析 SDK 或后端；未使用 Doka 名称、图标或素材。开发安装暂使用系统默认 App 图标。

## 文件与使用

- [Xcode 工程](FrameGuide.xcodeproj/project.pbxproj) 与共享 FrameGuide scheme 可直接打开；不需要 CocoaPods、XcodeGen 或第三方包。
- `App/`：原生相机、UI、存储、调色、云端服务。
- `Core/`：纯 Swift 构图、限频、热策略、水平数学、云端响应契约与请求身份门闩，可单独 `swift test`。
- `tools/`：零 npm 依赖的工程生成器、结构测试和平台检查脚本。
- `ci/macos-build.yml.disabled`：未激活的手动无签名构建模板，不在 `.github/workflows`。
- `.github/workflows/unsigned-device.yml`：已按授权准备的手动、预算前提门闩、20分钟上限的标准 macOS 设备构建；提交不会自动运行。IPA 上限50MiB，artifact保留1天；实际执行及结果以 Actions 记录为准。
- [完整文件清单](docs/FILE_MANIFEST.json)、[架构](docs/ARCHITECTURE.md)、[构建及免费安装路线](docs/BUILD_AND_INSTALL.md)、[云端协议](docs/CLOUD.md)、[授权审查](docs/DEPENDENCIES.md)。

Windows / PowerShell：

```powershell
cd path\to\FrameGuide
.\tools\verify-windows.ps1
```

Mac（由用户提供可用环境后执行）：

```sh
cd FrameGuide
sh tools/verify-macos.sh
```

增加/移动 Swift 文件时执行 `node tools/generate-project.mjs`；这会重建工程，已有签名和 Bundle ID 调整应在 Xcode 中重新设置。日常编辑源文件无需重新生成。

已完成私有仓库上传、费用前提核验、云端无签名构建和设备 IPA 下载复核。[私有源码仓库](https://github.com/sanqianup/FrameGuide) 保持 private。下一步是 Windows 本地免费签名候选验证；Sideloadly安装已获授权，依赖与原生安装界面仍待处理，Apple 账号和设备操作由用户本人处理。当前尚未安装，不承诺 iOS 真机功能或 iOS 27 兼容已验证。
