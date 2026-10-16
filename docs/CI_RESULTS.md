# 云端构建与设备 IPA 记录

2026-10-16：当前点选区域追踪版本已通过21项结构检查、46项Swift测试及设备构建，见文末CI #4。初期浏览器连接中断已恢复；核实免费额度后执行，没有修改预算。下文运行#1-#3及IPA为历史版本，旧Release保留。没有重新打包旧二进制冒充新版本。

新私有发布：[v0.2.0 未签名测试版](https://github.com/sanqianup/FrameGuide/releases/tag/v0.2.0-unsigned-test.1)。资产为本轮核验IPA、SHA256SUMS.txt与中文安装说明；用户自行签名安装。

仓库：[sanqianup/FrameGuide](https://github.com/sanqianup/FrameGuide)，已核验保持 private。检查日期2026-10-15。

| 运行 | Commit | 结果 |
| --- | --- | --- |
| [#1 / 38710002766](https://github.com/sanqianup/FrameGuide/actions/runs/38710002766) | `fb587a306f68640198e56d96d488b55c200c14a9` | 30项Swift测试通过、设备原生编译成功；打包校验的lipo参数顺序错误导致整体失败，无IPA artifact |
| [#2 / 38710533910](https://github.com/sanqianup/FrameGuide/actions/runs/38710533910) | `4661d946b534eeefea8ae9f4bf562a2d95dafb3c` | **success**；修正lipo参数顺序，采用当前相机会话通知名称；17项结构检查、30项Swift测试、plist校验、设备编译、IPA设备验证及artifact上传全部通过 |

实际工具链：标准 `macos-15` runner，Xcode16.4(16F6)，Swift6.1.2，iPhoneOS18.5 SDK，Deployment Target18.5。第二次总时长47秒，job40秒；这不是App取景帧率或模型响应速度。

运行前已只读核验免费分钟/存储和账户级零额外Actions支出阻断，未修改预算、购买额度或启用large runner。工作流仅手动运行、全局单组并发、20分钟超时，IPA上限50MiB，artifact保留1天。没有无限重试。账单数据不打包进源码。

## 历史产物（已被修复版替代，请勿作为签名输入）

- artifact：`FrameGuide-unsigned-device-not-installed`，ID `11960655483`，400792字节。
- [GitHub产物页](https://github.com/sanqianup/FrameGuide/actions/runs/38710533910/artifacts/11960655483)，保留至2026-10-16约09:07 UTC；本机已保存，远程过期不影响本机副本。
- artifact ZIP SHA-256：`d75a4d3570e8dc0e50b9b38306ff7dfd70b7b83811a67ace7c579d7c40fe0e9b`。
- 内部 `FrameGuide-unsigned.ipa`：400390字节，SHA-256：`7bcf65550265e3b87a9c81560cdb36292ea5f4c1fab353083befb1d0b3b001ba`。

Windows复核：ZIP和IPA哈希均匹配；内部为 `Payload/FrameGuide.app`。读取真实Mach-O header/load commands确认arm64可执行文件、平台iOS设备(2)，不是iOS Simulator(7)，minimumOS18.5.0、SDK18.5.0；没有代码签名load command、`_CodeSignature`或`embedded.mobileprovision`。

二进制SHA-256：`d295e7a38e23e74f0e6648ba2a106359c62947fdfc7ab20976f327e6e49209dc`。

此历史IPA已被下面的修复版替代。两版均未签名、未安装、未做iPhone实测。没有Apple登录、证书操作、MiMo密钥配置或照片上传。iOS27兼容仍未验证。

## 当前修复版（唯一后续签名候选）

- [运行 #3 / 38714062223](https://github.com/sanqianup/FrameGuide/actions/runs/38714062223)：**success**，总55秒，job47秒。
- 构建 commit：`ec96955842f9a76cec1f6c09b93435d0fc827c23`。修复移动立即清除提示，并用 AnalysisEpoch 拒绝正在分析或排队显示的旧结果；未改变系统备份行为，仅澄清界面文案。
- **18/18 Node检查、35/35 Swift测试、Apple plist验证和iPhoneOS arm64编译/打包全部通过**。新增5项回归测试覆盖运动、重新稳定、主队列晚到结果和配置失效。工具链仍为Xcode16.4 / Swift6.1.2 / iOS18.5 SDK。
- artifact ID `11961424548`，402343字节，2026-10-16 09:36:19 UTC过期；本机副本已保存。
- artifact ZIP SHA-256：`2f7e223185d08511b55f941f3e372fb3dec1b433a4d99863f3b7736e528bce83`。
- IPA `FrameGuide-unsigned.ipa`：401941字节，SHA-256：`4308bf80f67f8b76cb1da95dee71ed6f8086b31298e9e21ae9eeac97539eacbc`。
- Mach-O二进制SHA-256：`5963029d7df595a01b9299822cb62123935e1d2a0db63b25befde791eed24a0e`。
- Windows复核真实Mach-O：arm64、iOS设备平台2、最低18.5.0、SDK18.5.0、无签名命令、描述文件或签名目录。
- 已替换同一份资料库文件到版本1，未新建重复文件。上传成功；Windows上的官方元数据辅助脚本缺少os.setxattr，身份与版本已记录本机sidecar，未虚报本机扩展属性成功。

签名/安装、iPhone16 Pro实际相机、性能/热状态及iOS27兼容仍全部待验证。签名工具准备见WINDOWS_INSTALL_STATUS.md。

非阻塞日志提示：GitHub对v4 actions的旧Node运行时声明给出提示并强制Node24执行；AppIntents元数据提取因没有相关依赖而跳过。没有为此增加不需要的App能力或再次运行已成功的构建。

## 当前点选追踪版本（2026-10-16）

[CI #4 / 38832067025](https://github.com/sanqianup/FrameGuide/actions/runs/38832067025) success：构建提交`282815e0592fbd78c9bad0fa926a48c28d161114`，21项结构检查、46项纯Swift测试、Apple plist与iPhoneOS arm64设备编译/打包均通过。总51秒、job42秒；不是相机性能数据。工具链Xcode16.4 / Swift6.1.2 / iOS18.5 SDK。

artifact ID12017387673，ZIP SHA-256：`7951b7d5647313c83ae1b13ddbe07f0f56b65a2f69cdcd4927378200f3d92f4e`，保留至2026-10-17 00:54 UTC。IPA 435332字节，SHA-256：`25ac5e0e0249ebb9dc22e62f9cabf810ecfa6fff2e534e8327a627a639ade4c6`。Windows复核平台iOS设备2、arm64、最低18.5.0、SDK18.5.0，无代码签名/描述文件，包内仅可执行文件和系统元数据，无照片或密钥。

新版本仍为未签名测试包；未真机安装、未验证性能/27或真实模型。旧Release保留。运行前核实免费分钟、存储及账户零额外Actions费用阻断，没有修改预算或配置签名/模型凭据。
