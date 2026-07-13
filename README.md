# S3 Browser

Flutter 跨端 S3/MinIO 文件浏览器 (iOS / Android / macOS / Windows / Linux / Web)。

## 功能

- **多服务器管理** — 每个服务器独立的 endpoint / region / access key / secret key, 首页选一个进入
- 列表 / 网格双视图浏览 bucket
- 上传 (单文件 / 多文件 / 文件夹) — 桌面端支持拖拽
- 下载 (保存到 `Documents/s3browser/<bucket>/<name>`)
- 重命名 (复制 + 删除源)
- 移动 (复制 + 删除源)
- 批量操作 (多选 + 批量删除/移动/下载)
- 删除 (单文件 / 批量 / 文件夹)
- 切换 bucket / 切换服务器
- 配置保存 (SharedPreferences)

## 架构

```
lib/
├── main.dart                            # App 根 + 主题 + 路由
├── core/
│   └── config/
│       ├── s3_config.dart               # S3Config 数据类 (endpoint / region / keys)
│       └── server_store.dart            # 多 Server 持久化 (SharedPreferences, 含 v1 迁移)
├── data/
│   ├── models/
│   │   ├── s3_object.dart               # S3Object 统一模型
│   │   └── server.dart                  # Server = {id, name, S3Config}
│   ├── s3_signer.dart                   # AWS SigV4 签名 (手写)
│   └── s3_client.dart                   # S3 REST 客户端 (dio)
├── providers/
│   ├── server_list_provider.dart        # 所有 server + 增删改
│   ├── active_server_provider.dart      # 当前激活 server + 派生 s3Client
│   └── bucket_provider.dart             # bucket / prefix / list / selection
└── features/
    ├── servers/                         # 新架构: 服务器管理 (替代旧 auth/)
    │   ├── server_list_page.dart        # 首页: server 列表 + FAB 添加
    │   └── server_form_page.dart        # 新增 / 编辑 server (含测试连接)
    └── browser/
        ├── browser_page.dart            # 主浏览器 (AppBar 菜单含"切换服务器…")
        ├── widgets/
        │   ├── file_tile.dart
        │   ├── batch_action_bar.dart
        │   └── drop_target.dart
        └── dialogs/
            ├── upload_dialog.dart
            ├── move_dialog.dart
            └── rename_dialog.dart
```

### 关键决策

- **不依赖 `aws_s3_api` SDK**：2.0 是 smithy-dart 重写 (API 不稳定)，改用 dio + 手写 SigV4 签名
- **State 管理用 Riverpod 2.5.1**：`StateProvider` 管 bucket/prefix，`StateNotifierProvider` 管 list/selection
- **多服务器**：`Server` 含 uuid + name + S3Config，列表存 SharedPreferences 一把 key；进入某 server 后 `s3ClientProvider` 自动派生
- **激活态不持久化**：每次启动从服务器列表开始，避免 stale credential
- **v1 迁移**：旧版单 S3Config 存在 `s3browser.config.v1`，启动时检测并自动包装为 Server，删除旧 key
- **path-style addressing 默认开启** (MinIO 友好)，通过 `S3Config.pathStyle` 切换
- **multipart threshold = 5MB**, part size = 5MB
- **S3 "文件夹"**：用 0 字节 object + trailing `/` 作为 marker (AWS 推荐做法)
- **桌面端拖拽**：`desktop_drop` 包，包裹一层 `DropTarget` 跨平台兼容
- **移动端文件选择**：`file_picker` 包
- **macOS App Sandbox**：DebugProfile / Release entitlements 都启用了 `com.apple.security.network.client` (出站 HTTPS)

## 运行

```bash
# 安装依赖
flutter pub get

# 运行 (macOS)
flutter run -d macos

# 运行 (iOS Simulator)
flutter run -d ios

# 运行 (Android)
flutter run -d android

# Build
flutter build macos      # macOS app
flutter build apk        # Android
flutter build ios        # iOS
```

## 使用流程

1. **首次启动** → 看到空状态 + "添加第一个服务器" 按钮
2. **点添加** → 填表: 服务器名字 (默认用 endpoint host, 可改) / endpoint / region / access key / secret key / 默认 bucket / path-style / https
3. **测试连接** 按钮 → 实际连一下, 显示 bucket 数量预览
4. **保存并进入** → 自动设为激活 server, 跳到浏览器
5. **浏览器顶部** `Server名 · bucket名`，右上角菜单含:
   - 切换 bucket
   - 刷新
   - 切换服务器… (回首页, 可选别的 server)
6. **回到首页** → 点别的 server 卡片进入, 卡片右上角 popup menu 含: 测试连接 / 编辑 / 删除

## 配置

每个 server 单独配置:

| 字段 | 说明 | 例 |
|------|------|------|
| 服务器名字 | 显示用, 非空 + 唯一, 默认 = endpoint host | `s3.amazonaws.com` / `家里 MinIO` |
| Endpoint | S3 兼容服务的 URL (不含 bucket) | `http://localhost:9000` (MinIO) / `https://s3.amazonaws.com` (AWS) |
| Region | AWS region | `us-east-1` / `cn-north-1` |
| Access Key / Secret Key | API 凭证 | (IAM 用户) |
| 默认 Bucket | 进入后默认进的 bucket (可空) | `my-bucket` |
| Path-style | true = MinIO 兼容, false = virtual-hosted (AWS 标准) | true |
| HTTPS | false = http (本地 MinIO) | false |

## 限制

- **S3 protocol only**：不支持 S3 Select, 不支持 Glacier 等冷存储类
- **SSE 未实现**：服务端加密 / 客户端加密 / KMS 都没接
- **Presigned URL 未实现**：分享链接功能暂无
- **Web 端拖拽不支持** (浏览器 Drag-and-Drop API 跟 desktop_drop 不一致，需要单独实现)
- **移动端上传**：只能单文件，不能上传整个文件夹
- **大文件分片下载**：未实现，单文件 >100MB 会有 OOM 风险
- **batch delete 上限 1000** (AWS 限制, 超过会抛 ArgumentError)

## 测试

```bash
flutter test
```

当前 43 个测试全过:
- `test/data/s3_signer_test.dart` (11) — SigV4 签名的 determinism / 格式 / query 排序 / payload hash 影响 / header 影响 / service 影响
- `test/data/s3_object_test.dart` (6) — sizeHuman 各档位 (B/KB/MB/GB/folder/0)
- `test/data/server_test.dart` (4) — Server toJson/fromJson/copyWith/toString
- `test/core/s3_config_test.dart` (7) — normalizedEndpoint / copyWith / toJson-fromJson 往返
- `test/core/server_store_test.dart` (13) — load/save 往返 / v1 迁移 / defaultName / uuid
- `test/widget_test.dart` (1) — App 启动 smoke test (空 servers → ServerListPage)

S3Signer 测试用了 AWS 官方 SigV4 spec 的 canonical request 形式 (regression fingerprint) + 校验 64-char hex signature 格式。**不**使用 AWS 文档里的 vanilla golden case 因为本实现强制加 `x-amz-content-sha256` 到 SignedHeaders (真实 S3 调用必需)，跟简化版示例不同。

未覆盖的: S3Client 的网络层 (需要 dio adapter mock，TODO)。

## 已知踩坑 (踩过记下来)

- `desktop_drop` 跟自定义 `DropTarget` 类名冲突，用 `hide DropTarget` 解决
- `package:xml` 6.x 把 `builder.processing` 改成 `(target, text)` 2 positional args，不再支持 `version:` / `encoding:` named params
- `s3_signer.dart` 里不能定义顶层函数 `utf8(...)`，会遮盖 `dart:convert` 的 `utf8` 常量 → 改名 `_toUtf8`
- `package:cross_file/src/interface/io.dart` 是 private API，只用 public `cross_file.dart` 即可
- `dio.Headers.etagHeader` 在 dio 5.x 改成普通 string 头了，'etag' 即可
- **macOS App Sandbox**: 出站 HTTPS 必须显式加 `com.apple.security.network.client` entitlement, 只放 `network.server` (入站) 会让 dio 连任何外部 host 都报 errno=1 "Operation not permitted"
- **macOS 最小窗口尺寸**: 不设的话用户能拖到 100px 触发大量 overflow. AppDelegate.applicationDidFinishLaunching 里 `window.minSize = NSSize(width: 720, height: 500)` 是当前 UI 的下限 (AppBar 5 actions 240px + title 至少 480px 才有空间, 文件列表 320 固定列 + name 至少要 200px, 状态栏 4 段不能 < 100px)
- **shared_preferences 类型**: v1 存所有值 URL-encoded 成 string, 解析时 `pathStyle`/`secure` 必须手动从 `'true'` 转成 bool, 不能直接 `as bool`
- **测试间 SharedPreferences 状态**: `setMockInitialValues` 在 setUp 调用后, 测试 body 里再调一次会重置, 不需要 `resetStatic`

## 后续 TODO

- [x] 单元测试 (S3Signer / S3Config / S3Object)
- [x] 多服务器支持 (Server model + server_store + UI)
- [x] v1 单 config 迁移到 v2 多 server
- [x] macOS App Sandbox entitlement (network.client)
- [ ] S3Client 网络层 mock 测试 (dio adapter + json 解析)
- [ ] 上传进度条 (现在 onProgress 是空 callback)
- [ ] Presigned URL 分享
- [ ] 图片预览 (thumbnail)
- [ ] Web 端 drag-and-drop 适配
- [ ] 搜索 (按 prefix 过滤)
- [ ] 排序 (按 name / size / lastModified)
