# 云端构建与设备 IPA 记录

仓库：[sanqianup/FrameGuide](https://github.com/sanqianup/FrameGuide)，已核验保持 private。检查日期2026-10-15。

| 运行 | Commit | 结果 |
| --- | --- | --- |
| [#1 / 38710002766](https://github.com/sanqianup/FrameGuide/actions/runs/38710002766) | `fb587a306f68640198e56d96d488b55c200c14a9` | 30项Swift测试通过、设备原生编译成功；打包校验的lipo参数顺序错误导致整体失败，无IPA artifact |
| [#2 / 38710533910](https://github.com/sanqianup/FrameGuide/actions/runs/38710533910) | `4661d946b534eeefea8ae9f4bf562a2d95dafb3c` | **success**；修正lipo参数顺序，采用当前相机会话通知名称；17项结构检查、30项Swift测试、plist校验、设备编译、IPA设备验证及artifact上传全部通过 |

实际工具链：标准 `macos-15` runner，Xcode16.4(16F6)，Swift6.1.2，iPhoneOS18.5 SDK，Deployment Target18.5。第二次总时长47秒，job40秒；这不是App取景帧率或模型响应速度。

运行前已只读核验免费分钟/存储和账户级零额外Actions支出阻断，未修改预算、购买额度或启用large runner。工作流仅手动运行、全局单组并发、20分钟超时，IPA上限50MiB，artifact保留1天。没有无限重试。账单数据不打包进源码。

## 已下载产物

- artifact：`FrameGuide-unsigned-device-not-installed`，ID `11960655483`，400792字节。
- [GitHub产物页](https://github.com/sanqianup/FrameGuide/actions/runs/38710533910/artifacts/11960655483)，保留至2026-10-16约09:07 UTC；本机已保存，远程过期不影响本机副本。
- artifact ZIP SHA-256：`d75a4d3570e8dc0e50b9b38306ff7dfd70b7b83811a67ace7c579d7c40fe0e9b`。
- 内部 `FrameGuide-unsigned.ipa`：400390字节，SHA-256：`7bcf65550265e3b87a9c81560cdb36292ea5f4c1fab353083befb1d0b3b001ba`。

Windows复核：ZIP和IPA哈希均匹配；内部为 `Payload/FrameGuide.app`。读取真实Mach-O header/load commands确认arm64可执行文件、平台iOS设备(2)，不是iOS Simulator(7)，minimumOS18.5.0、SDK18.5.0；没有代码签名load command、`_CodeSignature`或`embedded.mobileprovision`。

二进制SHA-256：`d295e7a38e23e74f0e6648ba2a106359c62947fdfc7ab20976f327e6e49209dc`。

此IPA可作为后续本地签名验证的输入，**未签名、未安装、未做iPhone实测**。没有Apple登录、证书操作、第三方签名工具安装、MiMo密钥配置或照片上传。iOS27兼容仍未验证。

非阻塞日志提示：GitHub对v4 actions的旧Node运行时声明给出提示并强制Node24执行；AppIntents元数据提取因没有相关依赖而跳过。没有为此增加不需要的App能力或再次运行已成功的构建。
