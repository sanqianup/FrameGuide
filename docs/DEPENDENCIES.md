# 候选与授权审查

核查日期：2026-10-15。首版独立编写，只使用 Apple 系统框架；没有加入第三方代码、模型权重、训练数据、素材或 npm/Swift 外部依赖。

| 候选 | 已核对证据 | 本工程处理 |
| --- | --- | --- |
| [Day1Labs/YOYO-Camera](https://github.com/Day1Labs/YOYO-Camera) | [LICENSE 正文](https://raw.githubusercontent.com/Day1Labs/YOYO-Camera/main/LICENSE) 为 MIT，版权 Day1 Labs 2026 | 仅审查架构候选，无直接复制模块或素材；未引入其账户、StoreKit、Firebase、Cloudflare 后端或生成式服务。未来若借用代码需保留对应许可及版权 |
| [LiveCompose/LiveCapture](https://github.com/LiveCompose/LiveCapture) | README 有 MIT 徽章，但已检查的根目录 LICENSE URL 返回 404，未取得足以明确应用代码授权的正文 | 不复制 App 代码、UI 或素材；徽章本身不作为可复制依据 |
| [Adacrop-CoreML.mlpackage](https://huggingface.co/LiveCompose/Adacrop-CoreML.mlpackage) | 模型页显示 license: mit，模型卡正文为空；尚未取得完整上游/训练数据权利链，也未本机加载二进制 | 不下载、不打包、不启用权重；本机 Vision 基线不依赖它 |
| [LiveCompose-outpainted-17k](https://huggingface.co/datasets/LiveCompose/LiveCompose-outpainted-17k) | 委托方补充审查指出许可有 Current placeholder 提示；本任务未独立取得完整证据 | 作为未解决阻塞记录；未分发训练数据，不宣称许可链已审清 |

候选审查不等于对所有历史提交、依赖或资产完成审计。本工程无复制内容，因此无需把其他项目整套许可和资源打包进来。

## Adacrop 后续启用门槛

当前未实现实际模型加载器。以下由委托方补充，作为**待独立二进制核验的线索**，不是当前已通过的集成结论：

- student 权重合计约 5.07MB，不默认带约 107MB teacher/student 全套。
- 导出侧 BBox 输入 `full_img [1,3,224,224]`；Actor 输入 `crop_img` 同形状和 `state [1,4]`；输出 `action_probs`。
- 训练侧预处理为 RGB、0–1、CHW、直接缩放；框为归一化 `cx,cy,w,h`。
- 导出/训练侧动作序列 `left,right,up,down,zoom_in,zoom_out,stop`；公开 App 解释存在索引差异，输入字段还有 `state` / `state_workaround` 差异。
- 动作语义是图像裁剪操作，不能直接当作精确物理移动指导。

必须先核清模型及上游许可，固定模型版本/哈希，在 Mac 实际检查 `MLModel.modelDescription`、输入输出名/尺寸/类型、预处理和归一化，使用合成图片与固定基准样例测试每个动作索引，再测性能/热状态/退化路径，全部通过后才能在明确标识的可选开关启用。模型不能阻塞基础相机、替代未测性能数据或假装已接入。

Apple 系统框架：SwiftUI、AVFoundation、Vision、CoreMotion、CoreImage、ImageIO、Photos、Security、CryptoKit、UniformTypeIdentifiers。Node 只用于离线工程工具，不进入 iOS App。
