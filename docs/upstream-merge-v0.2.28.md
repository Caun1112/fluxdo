# v0.2.28 上游合并记录

## 初始状态与方案

- fork：Caun1112/fluxdo；当前开发分支 codex/share-image-export-options，提交 6bfe673a，比远程同名分支领先 227 个提交。
- main 停在 c835d572；不能以它代替实际开发分支。
- 上次共同基点：98bcf551（v0.2.27）；本次上游：e1bd839e（v0.2.28），新增 33 个提交、166 个文件变化。
- 未跟踪 AGENTS.md、patch-retry.py 保持原样，不纳入提交。
- 已建立备份 codex/backup-before-upstream-v0.2.28-20260907，合并在 codex/merge-upstream-v0.2.28-20260907 完成。采用普通双亲 merge，不改写历史。

## 修改归属

上游：私信成员管理、站点插件和字数校验、保存到文件与导出流程、图片缓存和转场、下载路径安全、表情市场、崩溃上下文与渲染 UAF 修复。

fork：分享图片显示选项与主题、底部分享/保存/复制顺序、已读加速、首页悬浮筛选与常用分类、返回按钮位置、macOS 默认窗口尺寸、TrollStore 依赖锁定和原生库归一化。全部保留。

双方重叠文件：

- `lib/l10n/modules/shareExport/shareExport_en.arb`
- `lib/l10n/modules/shareExport/shareExport_zh.arb`
- `lib/l10n/modules/shareExport/shareExport_zh_HK.arb`
- `lib/l10n/modules/shareExport/shareExport_zh_TW.arb`
- `lib/l10n/modules/topic/topic_en.arb`
- `lib/l10n/modules/topic/topic_zh.arb`
- `lib/l10n/modules/topic/topic_zh_HK.arb`
- `lib/l10n/modules/topic/topic_zh_TW.arb`
- `lib/pages/topic_detail_page/topic_detail_page.dart`
- `lib/pages/topics_page.dart`
- `lib/providers/preferences_provider.dart`
- `lib/widgets/share/share_image_preview.dart`
- `pubspec.yaml`

## 唯一文本冲突

lib/pages/topic_detail_page/topic_detail_page.dart：双方在同一位置新增 import。fork 引入已读加速面板，上游引入私信邀请面板，功能独立，必须同时保留：

```dart
import 'widgets/read_boost_sheet.dart';
import 'widgets/invite_private_message_dialog.dart';
```

自动合并审查：翻译保留双方键；偏好设置增加上游 showFilterHint 和崩溃采集开关，同时保留 fork 字段；分享预览保留自定义选项和按钮顺序，使用上游 ImageSaveUtils 保存语义；pubspec.yaml 仅接收版本号，三个 TrollStore override 与锁文件不变。渲染子模块更新到 f8d834b10fa280b4213ffa8ba9ed3e1032572c6d。

## 验证

已完成：

- dart tool/project_prep.dart test：依赖解析、翻译生成通过，锁文件无变化。
- 工作流列出的回归测试：104 项全部通过，包含 fork 已读加速、常用分类、悬浮筛选、分享按钮、话题返回按钮，以及上游私信、插件和下载安全功能。
- dart analyze lib/pages/topic_detail_page lib/pages/topics_page.dart lib/providers/preferences_provider.dart lib/widgets/share/share_image_preview.dart：无 error/warning；一条合并前已有的 info（_filter_actions.dart:18 缺少大括号），未做无关修改。
- YAML 解析、IPA 校验脚本语法检查、Git diff 空白检查通过。

云端已完成：104 项回归测试通过，Release 编译、IPA 实际解包与原生库检查、最终 Artifact 上传均成功。构建提交 bda6a3289239389b8884a2172ee8a3157f071e19。

待真机运行回归：TrollStore 安装后冷启动，确认不白屏；登录及网络请求；首页筛选和常用分类；话题返回及已读加速；分享图片的主题、显示选项、分享/保存/复制；iOS 保存到文件面板；私信成员管理；图片浏览和视频播放。

## IPA 构建配置

- Flutter + CocoaPods + Rust 原生库；Flutter 3.44.3（与本地验证一致）。
- macos-15，显式 Xcode 16.4，iphoneos 18.5，Release；最低 iOS 14.0。
- ios/Runner.xcworkspace（内含 Runner.xcodeproj 与 Pods），Scheme/Target 均为 Runner。
- 复用 dart tool/build_ipa_nosign.dart --yes，实际内部执行 flutter build ios --release --no-codesign。
- .app：build/ios/iphoneos/Runner.app。
- IPA：build/ios/ipa/fluxdo-0.2.28-nosign.ipa；Artifact：fluxdo-ios-unsigned，保留 7 天，只上传 IPA。
- workflow_dispatch；推送指定合并分支且工作流或 IPA 构建/验证脚本变化时自动构建，避免依赖默认分支预先存在工作流。
- 无 Apple Developer 证书或 Provisioning Profile；不使用 exportArchive。Flutter native-assets 可能自带 adhoc 签名，保留 fork 归一化步骤移除该类签名。
- Runner.entitlements 包含 com.apple.developer.web-browser；包内 Frameworks 与原生库需由 TrollStore 安装流程处理。当前工程没有额外应用扩展 Target。
- 项目已有 Rust 预处理同时生成 device/simulator 静态库，但最终应用和 IPA 使用 iphoneos；不要求本地 Simulator 或 Xcode。
- 本地无 iOS Release/Archive/DerivedData 生成，仅使用已有 Flutter 进行测试与生成代码；最终按需下载单个 IPA。
- CI 构建及 IPA 实际结构均已验证；主程序和插件原生库未签名，App.framework 与 Flutter.framework 保留 Flutter 自带的 adhoc 签名，无 Apple 证书。未发现需要归一化的 native-assets；TrollStore 真机安装和启动尚未验证。

## 审查与回滚

```sh
git log --graph --oneline codex/backup-before-upstream-v0.2.28-20260907..HEAD
git diff codex/backup-before-upstream-v0.2.28-20260907 HEAD
git diff upstream/main HEAD
```

返回原开发状态无需破坏历史：

```sh
git switch codex/share-image-export-options
git submodule update --init --recursive
```

原开发分支与备份都仍指向 6bfe673a。若以后需要撤销已发布的合并，应在目标分支使用 git revert -m 1 <合并提交>，审查并解决可能的反向冲突；不要 reset --hard 或强制推送。

用户已授权，以下推送已完成：

```sh
git push -u origin codex/merge-upstream-v0.2.28-20260907
```

此次推送会触发仅 iOS 构建工作流，不更新远程 main、不发布 Release。


## 云端构建结果（2026-09-07）

- 合并提交：43c01173d3776a03053f670e7deb8d398221f295。
- 构建修复提交：bda6a3289239389b8884a2172ee8a3157f071e19。首次 CI 发现 --yes 仍询问版本号；修复为无参数时直接读取 pubspec.yaml，静态分析通过。
- 成功运行：https://github.com/Caun1112/fluxdo/actions/runs/34091118943
- Artifact：https://github.com/Caun1112/fluxdo/actions/runs/34091118943/artifacts/10007531360
- IPA 大小：54,895,109 字节；Runner.app 构建输出约 124.3 MB，未下载该中间产物。
- Xcode 编译耗时 667.5 秒；整个构建另包含 Rust 原生库编译、依赖准备与测试。
- Runner Bundle ID：com.github.lingyan000.fluxdo；最低 iOS 14.0；arm64，iphoneos 18.5。
- DOH 原生入口符号检查通过。
- 远程 main 与原开发分支保持原样；更新发布在 codex/merge-upstream-v0.2.28-20260907。
- 本地最终 IPA：/Users/caun/Downloads/fluxdo-v0.2.28-bda6a328/fluxdo-0.2.28-nosign.ipa；下载后 CRC、版本号、平台和主程序验证通过。
- IPA SHA256：dce83b1b7640136b6c51e25564e17a53bec592d526f25ab826468eec2c519713。
