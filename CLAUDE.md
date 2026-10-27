# YiKey 译键 — 实时翻译输入法（macOS）

## 目标

一个 macOS 系统级输入法：用户输入时，候选窗**实时显示两行**：

```
输入中：当前xr v▌
┌────────────────────────────────────────────────────┐
│ [1 选中]  2 旋转  3 选址  4 宣战  5 …  6 …      ⌄  │  ← 第 1 行：拼音候选（横排，同系统输入法）
│ Currently selected                                 │  ← 第 2 行：只翻译「当前高亮」的那个候选
└────────────────────────────────────────────────────┘
```

- 第 1 行显示多个拼音候选；第 2 行**只翻译当前高亮的候选**，高亮切换时译文随之更新，不对其他候选做翻译
- 用户可通过**键盘或鼠标**选择候选或译文，选中内容插入到当前光标位置
- 语言对：**中文 ⇄ 外语**，外语在设置中选择（默认英语，见「翻译语言」）
- 在任意 App（浏览器、微信、终端、编辑器）中可用
- **最低支持 macOS 26**，翻译只用 **Apple 离线翻译**

---

## 技术选型

| 部分 | 方案 | 说明 |
|------|------|------|
| 语言 | **Swift 6** | macOS 输入法必须是原生 App，Python 无法实现 |
| 输入法框架 | **InputMethodKit (IMKit)** | `IMKInputController` 接收按键、管理 marked text、提交文本 |
| 拼音转汉字 | **librime 1.17**（Homebrew，含 lua 插件）+ 雾凇拼音词库 | 开发版动态链接 `/opt/homebrew/opt/librime`；`make dist` 把 librime、插件和依赖打包进 App，给没装 Homebrew 的人用 |
| 全拼 / 双拼 | librime 输入方案（schema） | 全拼与各双拼方案共用同一套词库，只是切换 schema，无需自己写键位映射 |
| 翻译 | **Apple Translation 框架**（仅离线） | 免费、低延迟、内容不出本机；macOS 26+ 支持无界面 `TranslationSession(installedSource:target:)`。不接在线翻译 |
| 候选窗 | 自定义 `NSPanel`（non-activating） | 系统 `IMKCandidates` 不支持「候选行 + 译文行」布局和点击回调 |
| 构建 | SwiftPM + `Makefile` 打包成 `.app` | 不依赖 Xcode，只需 Command Line Tools |
| 测试 | Swift Testing | CLT 环境需额外 `-F`/`-rpath`，已封装在 `make test` |

---

## 交互设计

### 输入流程

1. 用户敲拼音（中→外模式）或外语（外→中模式），内容作为 **marked text**（带下划线）显示在光标处
2. 中→外模式下，每次按键后：
   - librime 给出候选列表 → 第 1 行（每页 6 个，默认高亮第 1 个）
   - 防抖 **250ms** 后翻译 **待提交文本** → 第 2 行（翻译中保留旧译文并置灰，避免闪烁）
3. 外→中模式下：第 1 行只有一个"候选"，即原始外语输入；第 2 行是它的中文译文
4. 用户选择候选或译文 → `insertText` 提交到光标

**待提交文本** = 本次输入中已确认的分段 + 当前高亮候选。
例：已确认"当前"，高亮"选中" → 翻译"当前选中"。若候选覆盖了全部拼音，就是高亮候选本身。
这样译文就是"如果现在提交，会上屏的那句话"的翻译。

**外→中模式的按键差异**：第 1 行只有一个候选（原始输入），所以 `Space` 在候选行时输入空格（外语句子需要），数字和标点也直接追加到输入里；`Enter` 上屏原文，`↓`/`Tab` 后 `Space`/`Enter` 上屏译文。

**部分候选**：高亮候选只覆盖部分拼音时（如 `xr v` 只匹配了 `xr`），选中它只确认这一段，剩余拼音继续输入，与系统输入法行为一致；只有选择译文才会整句上屏。

### 全拼与双拼

中→外模式支持以下输入方案，只在设置窗口中切换（输入法菜单不列方案），选择保存在 UserDefaults `pinyinScheme`；未设置时用 `Preferences.schemes` 第一项。
schema 名称已对照 [rime-ice 仓库](https://github.com/iDvel/rime-ice) 根目录的 `*.schema.yaml` 核实（2026-10-27）：

| 方案 | rime schema | 说明 |
|------|-------------|------|
| **全拼（默认）** | `rime_ice` | 新安装默认方案 |
| 小鹤双拼 | `double_pinyin_flypy` | 作者常用，开发和测试优先保证 |
| 微软双拼 | `double_pinyin_mspy` | |
| 自然码双拼 | `double_pinyin` | 注意文件名无后缀 |
| 搜狗双拼 | `double_pinyin_sogou` | |
| 智能 ABC 双拼 | `double_pinyin_abc` | |
| 紫光双拼 | `double_pinyin_ziguang` | |
| 拼音加加双拼 | `double_pinyin_jiajia` | |

雾凇拼音版本固定在 `Makefile` 的 `RIME_ICE_REV`，`make build` 时下载到 `vendor/rime-ice`（不提交），再拷进 App 的 `Contents/Resources/rime-data`。雾凇自带 emoji 候选、lua 扩展（如输入 `date` 出日期），目前全部保留。

- 双拼时，marked text 显示 rime 转写后的**全拼**（如键入 `xrvs` 显示 `xuan zhong`），方便核对；由 schema 的 `preedit_format` 实现
- 切换方案只影响按键到拼音的解析，候选、翻译、焦点模型完全不变；切换时调用 `select_schema`，不重启进程
- `Resources/rime/default.custom.yaml` 补丁：只部署上表 8 个方案、每页 6 个候选。启动时同步到用户目录
- 用户目录 `~/Library/Application Support/YiKey/rime`（用户词频、编译产物），rime 日志在 `~/Library/Logs/YiKey`
- `make install` 会用 `rime_deployer` 预编译词库；之后输入法启动时仍会做一次维护检查（安装后首次约 4s，之后约 1s），期间打字会提示"词库部署中"

**待提交文本的计算**：不能用 rime 的 `commit_text_preview`，高亮非首选候选时它会变成"高亮候选 + 剩余字母"（如 `灯qmxrvs`）。实际用 `preedit` 前 `sel_start` 字节（已确认分段）+ 高亮候选文本。

### 焦点模型

候选窗有两个焦点区：**候选行**（默认）和**译文行**。

| 按键 | 焦点在候选行 | 焦点在译文行 |
|------|-------------|-------------|
| `1`–`6` | 选中对应候选 | 回到候选行并选中对应候选 |
| `←` / `→` | 移动高亮（触发重新翻译） | 无 |
| `-` / `=` | 翻页（雾凇绑定） | 回到候选行并翻页 |
| `[` / `]` | 以词定字（雾凇绑定） | 回到候选行并以词定字 |
| `↓` / `Tab` | 焦点移到译文行 | 无 |
| `↑` / `Shift+Tab` | 无 | 焦点回到候选行 |
| `Space` | 选中高亮候选 | 提交译文 |
| `Enter` | 原始按键原样上屏（雾凇行为，双拼时上屏的是双拼字母） | 提交译文 |
| `Esc` | 取消输入 | 焦点回到候选行 |
| `Backspace` | 删除一个字符，重新转换 + 翻译 | 同左，焦点回到候选行 |

全局：**Caps Lock 切换方向**，方向直接跟随 Caps Lock 灯：灯灭 = 中文→外语（拼音输入），灯亮 = 外语→中文（键盘直接打外语）。切换时如果正在输入，先把当前内容上屏；切换后候选窗短暂显示当前方向。方向不单独存储，激活输入法时按当前灯的状态同步。输入法菜单（菜单栏「译」图标）只显示当前方向和「设置…」入口。

- Caps Lock 灯亮时字母大小写只由 Shift 决定（不会因为 Caps Lock 变成大写）

**直接英文模式**：**单按 Shift**（按下后 0.5s 内松开、中间没按其他键）进入 / 退出。
- 字母、标点直接上屏，不出候选窗、不翻译（按键全部交还给 App）
- 此模式下 **Caps Lock 是普通大写锁定**，不切方向；退出时方向按当前 Caps Lock 灯同步（灯还亮着就会回到外→中，候选窗会提示）
- 正在输入时按 Shift：把**原样按键**上屏后进入直接英文（拼音模式误打的英文单词可以这样直接出；双拼时上屏的是双拼字母）
- 状态在所有 App 间共享，不持久化，输入法进程重启后回到翻译模式
- 已知限制：按住 Shift 点鼠标（如 Shift+点击选区）且很快松开，也可能被识别为单按 Shift
- 需要在 **系统设置 → 键盘 → 输入法 → 编辑** 中关闭「使用大写锁定键切换"ABC"输入法」，否则系统会拦截 Caps Lock，直接切走输入法

中→外模式空闲时（没有在输入），按键全部交给 rime：字母开始输入，标点转成中文标点直接上屏。`Tab` 在雾凇里原本是"跳到下一个拼音"，这里被改成进入译文行。

`←` / `→` 到本页边界时自动翻页。

### 鼠标

- 点击候选 → 选中该候选（同按数字键）
- 点击译文行 → 提交译文
- 悬停只做视觉反馈，**不改变高亮、不触发翻译**（防止鼠标划过时频繁翻译）

### 翻译语言

设置窗口「翻译语言 › 外语」选择，存于 UserDefaults `foreignLanguage`，默认 `en`。列表取自 macOS 27 `LanguageAvailability().supportedLanguages`（2026-10-27 核对）：

| 类别 | 语言 | 灯灭 | 灯亮 |
|------|------|------|------|
| 拉丁字母（`Preferences.latinLanguages`） | 英、德、法、西、意、葡、荷、波兰、土耳其、印尼、越南 | 中文→外语 | 外语→中文 |
| 非拉丁字母（`Preferences.nonLatinLanguages`） | 日、韩、俄、乌克兰、阿拉伯、泰、印地 | 中文→外语 | **英语→中文**（键盘打不出原文，回退） |

- 非拉丁字母语言在下拉框中标注「仅 中文→外语」，回退规则集中在 `Preferences.inputLanguage(for:)`
- 苹果按语言组打包翻译模型（如 `mt.bi-en-zh-ja-ko`），已下载的中文只属于某一组；换到其他组的外语（如法语）时，系统会要求中文和外语都再下载一次，属正常现象
- 切换提示和菜单显示具体语言，如「中文 → 法语」
- 每种外语的语言包单独下载；设置窗口显示所选语言的下载状态，换语言后自动重新检查
- `TranslationSession` 和译文缓存都以语言对（如 `zh-Hans>fr`）为 key，换语言不会命中旧译文
- 限制：外→中方向只能打 ASCII 字母，带重音的字符（é、ü、ñ）和越南语声调无法在输入中打出，翻译质量会受影响
- 「直接英文」（单按 Shift）名字不变，实际就是键盘直通，与所选外语无关

### 翻译时机

- 只翻译待提交文本，**不预翻译其他候选**
- 高亮变化 / 输入变化 → 取消在途请求 → **先查缓存，命中立即显示** → 未命中则防抖 250ms 后调用 Apple Translation
- 缓存：`TranslationCache`（LRU，500 条，key = 语言对 + 去首尾空格的原文），进程内共享，不持久化；翻译失败不缓存
- 语言包未下载时译文行显示「未下载离线翻译语言包 · 点击这里下载」，点击或 `↓` 后回车会打开设置窗口
- 译文未就绪时按 `↓` 或点击译文行：等待当前请求完成后再提交（超时 1s 则不提交并提示）

### 候选窗定位

- 通过 `client.attributes(forCharacterIndex:lineHeightRectangle:)` 获取光标矩形，候选窗显示在光标下方；超出屏幕底部时翻到上方
- 窗口宽度随内容自适应，最大宽度限制后折行

---

## 架构

```
YiKey/
├── CLAUDE.md
├── Package.swift
├── Makefile                      # build / install / uninstall / log / test
├── Resources/
│   ├── Info.plist                # IMKit 必需配置（见下）
│   ├── icon.tiff                 # 由 Scripts/make_icon.swift 生成
│   └── rime/default.custom.yaml  # 雾凇 default.yaml 的补丁
├── vendor/rime-ice/              # make build 时按固定版本下载，不提交
├── Scripts/
│   ├── make_icon.swift           # 生成菜单栏模板图标
│   ├── register.swift            # TISRegisterInputSource，make install 时调用；make dist 时编译成二进制
│   ├── bundle_dylibs.sh          # make dist：Homebrew dylib 拷进 Contents/Frameworks 并改为 @rpath
│   └── install.sh                # 随分发包附带的安装脚本
├── Sources/CRime/                # librime 头文件的 Swift 模块（pkg-config: rime）
├── Sources/YiKeyCore/         # 纯逻辑库，Swift 6 严格并发，可单测
│   ├── Composer.swift            # 输入状态机 + ConversionEngine 协议：候选 → 待提交文本 → 译文，持有焦点
│   └── TranslationCache.swift    # 译文 LRU 缓存
├── Sources/YiKey/             # 可执行 target（Swift 5 语言模式，见注意事项）
│   ├── main.swift                # 启动 IMKServer
│   ├── Log.swift                 # os.Logger
│   ├── InputController.swift     # IMKInputController 子类：按键分发、marked text、提交、翻译调度
│   ├── Pinyin/
│   │   └── RimeEngine.swift      # RimeRuntime（进程级初始化/部署）+ RimeEngine（每个会话一个 rime session）
│   ├── Translate/
│   │   └── AppleTranslator.swift # 按方向缓存 TranslationSession + 译文 LRU 缓存
│   ├── UI/
│   │   └── CandidatePanel.swift  # 候选行 + 译文行，NSPanel + 点击/悬停处理
│   └── Settings/
│       ├── Preferences.swift     # 输入方案（UserDefaults）
│       └── SettingsWindow.swift  # SwiftUI 设置窗口：输入方案、语言包状态/下载、快捷键说明
└── Tests/YiKeyCoreTests/
    ├── ComposerTests.swift       # 外→中
    ├── PinyinComposerTests.swift # 中→外，用 FakeEngine 模拟 rime
    └── TranslationCacheTests.swift
```

### 关键模块职责

- **InputController**：只做事件分发，不写业务逻辑。`handle(_:client:)` 把按键交给 `Composer`，根据返回的状态更新 marked text 和候选窗
- **Composer**：纯逻辑、可单测。中→外模式（`Direction.chineseToForeign`）持有 `ConversionEngine`（rime），候选/高亮/preedit 都从引擎读取；外→中模式（`.foreignToChinese`）自己维护键盘输入。两种模式共用焦点和翻译状态
- **翻译调度**：`pendingText` 变化时取消上一个 `Task`，防抖后再请求；结果回来时校验 `pendingText` 是否仍相同，过期结果丢弃
- **CandidatePanel**：`styleMask: [.nonactivatingPanel, .borderless]`，`level = .popUpMenu`，不抢焦点；点击回调通过闭包交回 `InputController` 执行 `insertText`

### Info.plist 必需键

- `InputMethodConnectionName`：`YiKey_Connection`
- `InputMethodServerControllerClass`：`YiKeyInputController`（Swift 类用 `@objc(YiKeyInputController)` 固定 ObjC 名，避免模块名修饰）
- `TISIntendedLanguage`：`zh-Hans`（出现在「简体中文」分类下）
- 只设 `LSUIElement`，**不设 `LSBackgroundOnly`**：后者会让设置窗口无法正常激活
- `tsInputMethodCharacterRepertoireKey`：`["Hans", "Latn"]`
- `tsInputMethodIconFileKey`
- Bundle ID 必须包含 `.inputmethod.`，如 `com.owen.inputmethod.YiKey`
- 输入法菜单里的名字取自 `Resources/{en,zh-Hans}.lproj/InfoPlist.strings` 的 `CFBundleName`（英文系统显示 YiKey，中文系统显示 译键）；只改 Info.plist 的 `CFBundleDisplayName` 不生效
- 2026-10-27 由 TransIME 改名为 YiKey：Bundle ID、ObjC 类名、用户目录、UserDefaults 域都随之变化，系统会视为新输入法

---

## 开发阶段

### Phase 0 — 骨架（先跑通）
- [x] SwiftPM 项目 + Makefile 打包 `.app`，ad-hoc 签名
- [x] 安装到 `~/Library/Input Methods/` 并通过 `TISRegisterInputSource` 注册
- [x] 按键原样作为 marked text 显示，`Enter` 上屏

### Phase 1 — 两行候选窗（英→中，先绕开拼音）✅ 2026-10-27 实机验证通过
- [x] CandidatePanel：候选行 + 译文行，跟随光标
- [x] AppleTranslator 接入，防抖 + 取消 + 过期丢弃
- [x] 焦点模型：`↓/Tab` 进入译文行，`Space/Enter` 提交，`Esc` 取消
- [x] 鼠标点击提交、悬停反馈

### Phase 2 — 拼音（中→英）✅ 2026-10-27 实机验证通过
- [x] 接入 librime（Homebrew 动态链接），打包雾凇词库
- [x] RimeEngine 封装：拼音 → 候选列表、选择候选、翻页、取已确认分段
- [x] 打包全拼 + 各双拼 schema，`RimeEngine.selectScheme(_:)` 切换；方案选择在设置窗口（2026-10-27 从输入法菜单移除）
- [x] 双拼 preedit 显示为全拼
- [x] 小鹤双拼端到端验证：键入 `xrvs` → 候选含「选中」→ 译文行显示英文
- [x] 候选行横排显示 6 个，`1–6` / `←→` / 翻页
- [x] 翻译待提交文本（已确认分段 + 高亮候选），高亮变化时重新翻译
- [x] Caps Lock 切换方向（跟随灯的状态），菜单显示当前方向

### Phase 3 — 完善
- [x] 翻译 LRU 缓存（命中时跳过防抖）
- [x] 离线语言包未安装时的引导：译文行提示 → 点击打开设置窗口 → 「下载」按钮调用 `prepareTranslation()` 弹出系统下载确认
- [x] 设置窗口（输入法菜单 → 设置…）：输入方案、语言包状态与下载、快捷键说明
  - 窗口在屏幕正中（手动计算，`center()` 会偏上）；出现在当前桌面空间，全屏应用之上也能显示（`.moveToActiveSpace` + `.fullScreenAuxiliary`）。后台应用激活时系统不会切换空间，也没有公开 API 能主动切回主桌面，所以采用"就地显示"
  - 从输入法菜单打开时前台是别的 App，`NSApp.activate()` 常被系统拒绝，所以额外调用 `orderFrontRegardless()` 强制置前。**不要设 `hidesOnDeactivate`**：菜单关闭后焦点回到原 App，窗口会被立刻隐藏（曾因此导致点「设置…」无反应）
- [x] 暗色/亮色主题：候选窗全部使用系统动态颜色，已离屏渲染两种外观核对，无需改动
- [ ] 实机验证：设置窗口弹出与焦点、语言包下载流程

### 暂不做（避免过度设计）
- 在线翻译后端
- 预翻译非高亮候选
- 候选窗展开多页网格（截图右侧 `⌄`）——先只做翻页
- 非拉丁字母外语的 外→中 方向（需要接入假名/韩文/西里尔等输入）
- 同时翻译成多种语言（多行译文）
- 云同步、用户词库管理

---

## 常用命令

```bash
make build        # swift build -c release 并组装 YiKey.app
make install      # 拷贝到 ~/Library/Input Methods/ 并重启进程
make log          # log stream，subsystem = com.owen.inputmethod.YiKey
make uninstall
make dist         # 打包分发版 build/YiKey-<版本>.zip（自带 librime 等依赖），对方解压后 bash install.sh
make test         # Swift Testing 单元测试（不要直接 swift test，CLT 环境找不到 Testing 模块）
```

首次安装后需：
1. **系统设置 → 键盘 → 输入法 → + → 简体中文 → 译键**
2. **系统设置 → 通用 → 语言与地区 → 翻译语言**：下载「英语」和「简体中文」离线语言包（未下载时译文行显示提示）

`make install` 会先 `killall YiKey`，下次切换到该输入法时自动加载新版本，一般无需注销。

### 分发（make dist）

- 只支持 Apple Silicon、**macOS 27+**：Homebrew 的 dylib 都是 `minos 27.0`，`install.sh` 会检查
- librime 按自身 dylib 所在目录查找 `rime-plugins/`，所以插件放 `Contents/Frameworks/rime-plugins/`；Homebrew 插件自带 `@loader_path/..` rpath，正好指向 `Frameworks`
- 只有 ad-hoc 签名、未公证，`install.sh` 会去掉隔离标记；未预编译词库，首次使用时部署几秒
- 已验证（2026-10-27）：本机用分发包安装后，`lsof` 确认 librime、全部依赖和 4 个插件都从 App 内加载，无 `/opt/homebrew` 引用

---

## 开发注意事项

- 输入法进程崩溃会导致当前 App 无法输入：开发时保留系统自带输入法，用 `Ctrl+Space` 切回
- IMKit 回调在主线程，翻译、librime 调用不能阻塞主线程；UI 更新回到 `@MainActor`
- IMKit / Translation 的 SDK 类型没有 Sendable 标注，Swift 6 严格模式会误报 data race，所以 `YiKey` target 用 Swift 5 语言模式；`InputController` 标 `@MainActor`，IMKit 覆写方法标 `nonisolated` 后用 `MainActor.assumeIsolated` 进入主线程。业务逻辑放 `YiKeyCore`，保持 Swift 6 严格检查
- `client` 对象只在当前输入会话内有效，异步回调里提交文本前要确认会话未切换
- 密码输入框（Secure Input）中系统会禁用第三方输入法，属正常行为
- 日志用 `os.Logger`（subsystem = bundle ID），不要 `print`
- 系统会缓存输入法图标：改 `icon.tiff` 后要把 `Info.plist` 的 `CFBundleVersion` 加 1 再 `make install`，必要时 `killall TextInputMenuAgent`，否则菜单栏仍显示旧图标

---

## 已确认决策

- 最低支持 **macOS 26**
- 翻译只用 **Apple 离线翻译**，不接在线 API
- 第 1 行显示**多个拼音候选**，第 2 行**只翻译当前高亮候选**（待提交文本）
- 支持**全拼和双拼**，**默认全拼**（2026-10-27 由小鹤双拼改为全拼），其他方案在设置窗口中切换
