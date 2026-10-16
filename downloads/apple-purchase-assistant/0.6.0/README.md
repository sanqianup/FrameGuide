# Apple 购买助手 0.6.0 · 简化候选实测版

- [下载插件 ZIP](./Apple-Purchase-Workflow-0.6.0-user-test.zip)
- [中文安装说明](./README.zh-CN.txt)（与安装包内 README.zh-CN.txt 相同）

登录 GitHub 后打开 ZIP 页面，点击 Download raw file（下载原始文件）。完整解压，在 Chrome/Edge 扩展管理页开启开发者模式，加载直接包含 manifest.json 的 extension 文件夹。测试新版前先停止并停用旧版，避免两个版本同时执行。

## 本版变化

主面板简化为商品规格、收货预设、预算时间、授权及开始/停止。未知页面可通过点选向导校准，不必手写 selector 或 JSON；高级设置和模拟商城默认折叠。

## 验证状态

404/404 项 Node 模拟 DOM/API 回归通过。尚未实际加载扩展验收，也未完成 Apple 完整结账和订单提交实页验收。未知环节仍需点选校准，缺失证据会停止。本版是候选实测包，不能保证抢购成功。

包内仅含代码、文档和虚构测试资料，不含用户地址、电话或登录凭据。

ZIP 大小：277873 字节。
SHA256：0f5a1e9dbc85a558c6dfd2b2e4e652a0d8480bf292f2b29e6a1db9bf7d6c05ac
