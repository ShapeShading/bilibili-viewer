# Bilibili Viewer for visionOS

> ⚠️ **AI 生成说明**: 本文档由 AI 助手生成，旨在帮助新手快速上手。如有疑问，请参考官方文档或社区资源。

一个专为 Apple Vision Pro 设计的 Bilibili 观看应用，提供沉浸式的视频观看体验。

## 📋 系统要求

- **硬件**: Apple Vision Pro 或 visionOS 模拟器
- **操作系统**: macOS 14.0+ (用于开发)
- **开发环境**: Xcode 15.0+
- **目标系统**: visionOS 1.0+

## 🚀 快速开始

### 1. 环境准备

确保你的 Mac 已安装：

- Xcode 15.0 或更高版本
- visionOS SDK
- Git (用于克隆代码)

### 2. 获取代码

```bash
# 克隆项目到本地
git clone <repository-url>
cd bilibili-viewer
```

### 3. 打开项目

```bash
# 使用 Xcode 打开项目
open bilibili-viewer.xcodeproj
```

或者直接在 Xcode 中打开 `bilibili-viewer.xcodeproj` 文件。

### 4. 配置开发者账号

1. 在 Xcode 中选择项目根目录
2. 在 "Signing & Capabilities" 选项卡中
3. 选择你的开发者团队 (Team)
4. 确保 Bundle Identifier 是唯一的

### 5. 选择运行目标

在 Xcode 顶部工具栏中：

- **真机运行**: 选择你的 Apple Vision Pro 设备
- **模拟器运行**: 选择 "Apple Vision Pro (Simulator)"

### 6. 构建和运行

```bash
# 命令行构建 (可选)
xcodebuild -project bilibili-viewer.xcodeproj -scheme bilibili-viewer -destination 'platform=visionOS Simulator,name=Apple Vision Pro' build

# 或者直接在 Xcode 中按 Cmd+R 运行
```

## 🎮 使用说明

### 基本功能

- **🔍 搜索**: 点击搜索按钮输入关键词
- **🔄 刷新**: 刷新当前页面
- **📚 历史记录**: 查看观看历史
- **⏯️ 播放控制**: 播放/暂停视频
- **⏪⏩ 进度控制**: 快退/快进 15 秒
- **💬 弹幕切换**: 开启/关闭弹幕显示
- **🔍 全屏模式**: 切换全屏观看

### 导航说明

1. **主页浏览**: 应用启动后自动加载 Bilibili 主页
2. **视频搜索**: 使用搜索功能查找感兴趣的内容
3. **视频播放**: 点击视频进入播放页面
4. **控制面板**: 在视频页面使用底部控制按钮

### 手势操作

- **点击**: 选择和播放
- **滑动**: 页面滚动
- **捏合**: 缩放页面 (0.5x - 3.0x)

## 🛠️ 开发说明

### 项目结构

```
bilibili-viewer/
├── bilibili-viewer/
│   ├── ContentView.swift      # 主界面视图
│   ├── WebView.swift          # WebKit 封装
│   ├── AppModel.swift         # 应用数据模型
│   ├── ImmersiveView.swift    # 沉浸式视图
│   └── ...
├── Packages/
│   └── RealityKitContent/     # 3D 内容包
└── bilibili-viewer.xcodeproj  # Xcode 项目文件
```

### 核心技术

- **SwiftUI**: 用户界面框架
- **WebKit**: 网页渲染引擎
- **RealityKit**: 3D 内容渲染
- **visionOS SDK**: 平台特定功能

## 🔧 故障排除

### 常见问题

**Q: 构建失败，提示找不到 visionOS SDK**
A: 确保安装了最新版本的 Xcode 和 visionOS SDK

**Q: 模拟器无法启动**
A: 检查系统资源，确保有足够的内存和存储空间

**Q: 视频无法播放**
A: 检查网络连接，确保可以访问 Bilibili 服务

**Q: 应用在真机上无法安装**
A: 检查开发者证书配置和设备信任设置

### 调试技巧

1. 查看 Xcode 控制台输出
2. 使用 Safari 开发者工具调试 WebView
3. 检查网络请求状态
4. 验证用户代理字符串设置

## 📚 参考文档

### 官方文档

- [Apple visionOS 开发指南](https://developer.apple.com/visionos/)
- [SwiftUI 官方文档](https://developer.apple.com/documentation/swiftui/)
- [WebKit 开发文档](https://developer.apple.com/documentation/webkit/)
- [RealityKit 文档](https://developer.apple.com/documentation/realitykit/)

### 社区资源

- [Apple 开发者论坛 - visionOS](https://developer.apple.com/forums/tags/visionos)
- [Swift.org 社区](https://swift.org/community/)
- [Stack Overflow - visionOS 标签](https://stackoverflow.com/questions/tagged/visionos)

### 相关教程

- [visionOS 应用开发入门](https://developer.apple.com/tutorials/app-dev-training)
- [SwiftUI 教程](https://developer.apple.com/tutorials/swiftui)
- [WebKit 集成指南](https://developer.apple.com/documentation/webkit/wkwebview)

## 📄 许可证

本项目遵循相应的开源许可证。使用前请确保遵守相关法律法规和平台服务条款。

## 🤝 贡献

欢迎提交 Issue 和 Pull Request 来改进这个项目。

---

**免责声明**: 本应用仅供学习和研究使用，请遵守 Bilibili 的服务条款和相关法律法规。
