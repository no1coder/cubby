# 发布指南（维护者）

本文说明 Cubby 的签名、公证、GitHub Release 与 Homebrew tap 发布流程。所有凭据都只保存在维护者本机钥匙串和 GitHub Environment secrets 中，**不要写进仓库、Issue 或日志**。

## 概览

| 阶段 | 触发 | 做什么 | 文件 |
| --- | --- | --- | --- |
| CI | push 到 `main`、PR | 并行两个任务：① 脚本语法 → swift-format lint → 国际化守卫；② 通用二进制构建 → 测试 + 覆盖率门槛（CubbyCore ≥ 95%）→ ad-hoc 打包冒烟（.app + DMG） | `.github/workflows/ci.yml` |
| Release | 推送 `v*` tag | 校验 tag 与 `VERSION` 一致 → 测试 → 导入证书 → 构建并签名 → 公证 .app 与 DMG 并 staple → 构建来源证明 → 创建 **draft** release | `.github/workflows/release.yml` |
| Publish | 维护者 Publish 正式版 release | 校验 DMG 的 sha256 → 更新 `no1coder/homebrew-tap` 的 `Casks/cubby.rb` | `.github/workflows/publish.yml` |

发布产物（`dist/`）：`Cubby-X.Y.Z.dmg`（主推）、`Cubby-X.Y.Z.zip`、`SHA256SUMS.txt`，以及用作 release 说明的 `NOTES.md`（不上传为附件）。

### 脚本速查

| 命令 | 作用 |
| --- | --- |
| `./scripts/build-app.sh`（`make app`） | 构建通用二进制并组装、签名 `build/Cubby.app`；版本取自 `VERSION` |
| `./scripts/make-dmg.sh [App]`（`make dmg`） | 用现有 `build/Cubby.app` 生成带安装窗口的 `dist/Cubby-<版本>.dmg`（不重新构建；dmgbuild，见第五节），Developer ID 身份时同时签名 DMG |
| `swift scripts/make-dmg-background.swift` | 重新生成 DMG 窗口背景 `packaging/dmg/background.png` 与 `background@2x.png` |
| `./scripts/notarize.sh <App/DMG/PKG>` | 提交公证、等待结果；失败时打印 `notarytool log`；成功后 staple 并用 `spctl` 校验 |
| `./scripts/release.sh [--skip-notarize]`（`make release`） | 端到端发布，产物输出到 `dist/` |
| `./scripts/changelog-notes.sh <版本>` | 从 `CHANGELOG.md` 提取对应版本段落 |
| `./scripts/update-tap.sh <版本> <sha256> [--output 文件 \| --push]` | 由 `packaging/homebrew/cubby.rb` 模板生成 cask；`--push` 时提交到 tap 仓库 |
| `./scripts/check-no-cjk.sh`（`make check-cjk`） | 源码字符串字面量中不得出现汉字 |
| `./scripts/check-coverage.sh`（`make coverage`） | 测试并检查 CubbyCore 行覆盖率（`COVERAGE_MIN`，默认 95） |
| `make lint` / `make format` | swift-format 检查 / 就地格式化（配置见 `.swift-format`） |

### 环境变量

| 变量 | 使用者 | 含义 |
| --- | --- | --- |
| `SIGN_IDENTITY` | build-app / make-dmg / release | 签名身份（证书名或 SHA-1）。`build-app.sh` 默认第一个 Apple Development 证书，`release.sh` 默认第一个 Developer ID Application 证书；`-` 为 ad-hoc |
| `TIMESTAMP` | build-app | `auto`（默认：Developer ID 用安全时间戳，其余 `--timestamp=none`）/ `secure` / `none` |
| `BUNDLE_ID` | build-app | 覆盖 bundle ID，如 `io.github.no1coder.Cubby.dev` 让开发版与正式版共存 |
| `BUILD_NUMBER` | build-app | 覆盖 `CFBundleVersion`，默认 `git rev-list --count HEAD`，非 git 仓库为 1 |
| `DMGBUILD_PYTHON` | make-dmg | 创建 dmgbuild 虚拟环境所用的 Python（需 ≥ 3.10），默认 `python3` |
| `NOTARY_PROFILE` | notarize | 本机 notarytool 钥匙串配置名，默认 `cubby-notary` |
| `NOTARY_KEY_PATH` / `NOTARY_KEY_ID` / `NOTARY_ISSUER_ID` | notarize | 使用 App Store Connect API Key 公证（CI 方式）；设置了 `NOTARY_KEY_PATH` 即优先使用 |
| `NOTARY_TIMEOUT` | notarize | 等待公证的超时，默认 `1h` |
| `COVERAGE_MIN` | check-coverage | 覆盖率门槛，默认 95 |
| `TAP_GITHUB_TOKEN` / `TAP_REPO` / `TAP_BRANCH` / `TAP_DRY_RUN` | update-tap | tap 推送凭据与目标，默认 `no1coder/homebrew-tap` 的 `main` |

## 一、一次性准备（维护者本人执行）

### 1. Developer ID 证书

钥匙串中已有 `Developer ID Application: jiankui sun (69A75B6U2B)`，确认：

```bash
security find-identity -v -p codesigning
```

为 CI 导出 .p12（证书 + 私钥）：

1. 打开「钥匙串访问」→「登录」→「我的证书」，找到 `Developer ID Application: jiankui sun (69A75B6U2B)`，确认可展开看到私钥。
2. 右键 →「导出」→ 格式选「个人信息交换（.p12）」，设置一个强密码（即 secret `DEVELOPER_ID_P12_PASSWORD`）。
3. 转成 base64 写入 GitHub（见第 4 步），随后删除本地 .p12 文件。

> 如果 CI 签名时报 `unable to build chain to self-signed root`，说明 runner 缺少中间证书：从 <https://www.apple.com/certificateauthority/> 下载 `Developer ID - G2` 中间证书，与 .p12 一并导入临时钥匙串（在 `scripts/ci/signing-keychain.sh` 中追加一行 `security import`）。

### 2. App Store Connect API Key（公证用）

1. App Store Connect →「用户和访问」→「集成」→「App Store Connect API」→「团队密钥」→ 生成，角色选 **Developer**。
2. 下载 `AuthKey_<KEYID>.p8`（只能下载一次，妥善保存到密码管理器），记录 **Key ID** 与页面顶部的 **Issuer ID**。

### 3. 本机公证凭据

把 API Key 存入本机钥匙串，配置名固定为 `cubby-notary`（脚本默认值）：

```bash
xcrun notarytool store-credentials cubby-notary \
  --key /path/to/AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUER_ID>

# 验证凭据可用（会列出历史提交，首次为空）
xcrun notarytool history --keychain-profile cubby-notary
```

也可以改用 Apple ID + App 专用密码：`xcrun notarytool store-credentials cubby-notary --apple-id <APPLE_ID> --team-id 69A75B6U2B`（按提示输入 App 专用密码）。

### 4. GitHub 仓库设置（`no1coder/cubby`）

1. **Environment `release`**：Settings → Environments → New environment → `release`
   - Required reviewers：勾选自己（每次发版需手动批准）。
   - Deployment branches and tags：Selected → 添加 tag 规则 `v*`。
   - 添加下表中的 secrets。
2. **Environment `homebrew-tap`**：同上新建，不需要审批；Deployment branches and tags 选择 tag `v*` 与分支 `main`（后者用于手动重试）；添加 `TAP_GITHUB_TOKEN`。
3. **Variables（可选）**：`release` 环境中新建 variable `SIGN_IDENTITY`，值为 `Developer ID Application: jiankui sun (69A75B6U2B)`；不设置时自动选用导入的 Developer ID 证书。
4. **Tag 保护**：Settings → Rules → Rulesets → New tag ruleset，目标 `v*`，限制创建 / 更新 / 删除（只有管理员可以绕过）。
5. **Actions 权限**：Settings → Actions → General → Workflow permissions 选「Read repository contents」（各工作流按需声明写权限）。

| Secret | 所在 Environment | 含义 | 来源 |
| --- | --- | --- | --- |
| `DEVELOPER_ID_P12_BASE64` | `release` | Developer ID 证书 + 私钥（.p12）的 base64 | 第 1 步导出的 .p12 |
| `DEVELOPER_ID_P12_PASSWORD` | `release` | 导出 .p12 时设置的密码 | 第 1 步 |
| `KEYCHAIN_PASSWORD` | `release` | CI 临时钥匙串的密码（任意随机串，可不设，脚本会随机生成） | `openssl rand -base64 24` |
| `NOTARY_KEY_P8_BASE64` | `release` | `AuthKey_<KEYID>.p8` 的 base64 | 第 2 步 |
| `NOTARY_KEY_ID` | `release` | API Key ID | 第 2 步 |
| `NOTARY_ISSUER_ID` | `release` | Issuer ID（团队密钥必填） | 第 2 步 |
| `TAP_GITHUB_TOKEN` | `homebrew-tap` | 细粒度 PAT，仅能写 tap 仓库 | 第 5 步 |

用 `gh` 从标准输入写入（值不会出现在命令行历史中）：

```bash
base64 -i cubby-developer-id.p12 | gh secret set DEVELOPER_ID_P12_BASE64 --env release -R no1coder/cubby
gh secret set DEVELOPER_ID_P12_PASSWORD --env release -R no1coder/cubby    # 交互输入
openssl rand -base64 24 | gh secret set KEYCHAIN_PASSWORD --env release -R no1coder/cubby
base64 -i AuthKey_<KEYID>.p8 | gh secret set NOTARY_KEY_P8_BASE64 --env release -R no1coder/cubby
gh secret set NOTARY_KEY_ID --env release -R no1coder/cubby
gh secret set NOTARY_ISSUER_ID --env release -R no1coder/cubby
gh secret set TAP_GITHUB_TOKEN --env homebrew-tap -R no1coder/cubby
rm -P cubby-developer-id.p12
```

### 5. Homebrew tap 仓库（`no1coder/homebrew-tap`）

1. 新建**公开**仓库 `no1coder/homebrew-tap`，勾选「Add a README」（`update-tap.sh` 需要 `main` 分支已有提交），可再建空目录 `Casks/`。
2. 创建细粒度 PAT：GitHub → Settings → Developer settings → Fine-grained tokens → Generate new token
   - Resource owner：`no1coder`；Repository access：Only select repositories → `homebrew-tap`
   - Permissions：Repository permissions → **Contents: Read and write**（Metadata 只读会自动勾选），其余保持 No access
   - 设置过期时间（如 1 年）并在日历中提醒续期；写入 secret `TAP_GITHUB_TOKEN`。
3. cask 模板在本仓库 `packaging/homebrew/cubby.rb`（`{{VERSION}}` / `{{SHA256}}` 为占位符），修改 cask 结构（如以后加 `auto_updates true`）只改模板，下一次发布自动同步到 tap。
4. 用户安装方式：`brew install --cask no1coder/tap/cubby`。

## 二、版本号规则

- **单一来源**：仓库根目录 `VERSION`（如 `0.2.0`）是版本号的唯一来源。`build-app.sh` 把它写入 .app 的 `CFBundleShortVersionString`，覆盖源文件中的值。环境变量 `VERSION`（如 `make release VERSION=x.y.z`）只用于核对，与文件不一致时脚本直接失败。
- **源 `Resources/Info.plist`**：其中的 `CFBundleShortVersionString` 仅供开发构建（不经 `build-app.sh`、直接拷贝源 Info.plist 组装的 .app）在「关于」页显示，发布前与 `VERSION` 一并同步；`build-app.sh` 发现两者不一致时会输出警告（不会中断构建）。
- **构建号**：`CFBundleVersion` = `git rev-list --count HEAD`（单调递增；release.yml 使用 `fetch-depth: 0` 获取完整历史），可用 `BUILD_NUMBER` 覆盖。
- **SemVer**：`X.Y.Z` 为正式版；`X.Y.Z-beta.N` 为预发布，release 自动标记为 prerelease，不更新 tap。
- **tag** 必须是 `v` + `VERSION`，release.yml 会校验。
- 更新前后必须保持同一 Team ID（`69A75B6U2B`）与 bundle ID（`io.github.no1coder.Cubby`），否则用户的辅助功能授权会失效。

## 三、日常发版

1. **确认 main 为绿色**：CI 通过；本地可再跑 `make lint check-cjk coverage`。
2. **改版本号与 CHANGELOG**：
   - `echo 0.3.0 > VERSION`
   - 同步 `Resources/Info.plist` 的 `CFBundleShortVersionString`：`/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.3.0" Resources/Info.plist`（预发布版本只写数字部分，如 `0.3.0`）
   - 在 `CHANGELOG.md` 中把 `## [Unreleased]` 的内容移到 `## [0.3.0] - YYYY-MM-DD`，并更新底部的比较链接。该段落会原样成为 release 说明。
   - 提交（如 `chore: release v0.3.0`）并推送到 `main`，等待 CI 通过。
3. **打 tag**：
   ```bash
   git tag -a v0.3.0 -m "Cubby 0.3.0"      # 有 GPG/SSH 签名配置时用 -s
   git push origin v0.3.0
   ```
4. **审批**：Actions → Release 运行页 →「Review deployments」→ 勾选 `release` → Approve。约 10–20 分钟后生成 draft release（公证通常几分钟，偶尔更久）。
5. **冒烟**（建议在干净的用户账户或虚拟机中）：从 draft release 下载 DMG，然后
   ```bash
   shasum -a 256 -c SHA256SUMS.txt
   spctl -a -vvv -t open --context context:primary-signature Cubby-0.3.0.dmg   # source=Notarized Developer ID
   xcrun stapler validate Cubby-0.3.0.dmg
   gh attestation verify Cubby-0.3.0.dmg -R no1coder/cubby                     # 构建来源证明
   ```
   挂载 DMG → 拖入「应用程序」→ 首次打开只应出现一次「从互联网下载」确认 → 授权引导 → 复制 / 呼出面板 / 粘贴 → 关于页版本号与构建号正确。
6. **Publish**：在 draft release 页面按需润色说明后点击「Publish release」。
7. **tap 自动更新**：publish.yml 校验 DMG sha256 后推送 `cubby 0.3.0` 到 tap。验证：
   ```bash
   brew update && brew info --cask no1coder/tap/cubby
   brew upgrade --cask cubby    # 或 brew install --cask no1coder/tap/cubby
   ```

预发布：`VERSION` 写 `0.3.0-beta.1`，流程相同，release 自动标记为 prerelease，Publish 后不会更新 tap。

## 四、本地兜底发版（CI 不可用时）

前提：已完成第一节第 1、3 步（钥匙串中有 Developer ID 证书与 `cubby-notary` 配置）。

```bash
make release                 # = swift test + scripts/release.sh：构建 → 签名 → 公证 .app → DMG → 公证 DMG → zip → 校验和 → NOTES.md
git push origin v0.3.0       # tag 须已推送，--verify-tag 才能通过
gh release create v0.3.0 dist/Cubby-0.3.0.dmg dist/Cubby-0.3.0.zip dist/SHA256SUMS.txt \
  --draft --verify-tag --title "Cubby 0.3.0" --notes-file dist/NOTES.md
```

冒烟后 Publish，publish.yml 照常更新 tap。若 Actions 整体不可用，手动更新 tap：

```bash
./scripts/update-tap.sh 0.3.0 "$(awk '/\.dmg$/ { print $1 }' dist/SHA256SUMS.txt)" \
  --output ../homebrew-tap/Casks/cubby.rb
cd ../homebrew-tap && brew style Casks/cubby.rb && git commit -am "cubby 0.3.0" && git push
```

**无凭据演练**（不公证、ad-hoc 签名，产物不可分发，用于检查脚本与打包）：

```bash
SIGN_IDENTITY=- make release RELEASE_FLAGS=--skip-notarize
```

也可以分步执行（公证并 staple 之后不要再 `make app`，重建会丢掉票据）：

```bash
export SIGN_IDENTITY="Developer ID Application: jiankui sun (69A75B6U2B)"
./scripts/build-app.sh
./scripts/notarize.sh build/Cubby.app          # 公证 .app 并 staple
./scripts/make-dmg.sh                          # 或 make dmg（不会重新构建）；Developer ID 身份时同时签名 DMG
./scripts/notarize.sh dist/Cubby-X.Y.Z.dmg
```

## 五、DMG 安装窗口

用户打开 DMG 后看到的是定制的 Finder 窗口：640×400 pt 内容区（Retina 背景），左侧 Cubby.app、右侧「应用程序」快捷方式（128 pt 图标、固定位置），中间箭头，底部中英双语提示「拖到「应用程序」即可安装 · Drag Cubby to Applications to install」；工具栏、侧边栏、路径栏、状态栏全部隐藏，卷图标为应用图标。

**工具**：[dmgbuild](https://pypi.org/project/dmgbuild/) 1.6.7（Python）直接写入 `.DS_Store` 与背景图别名，不经过 Finder / AppleScript，CI 无界面也能运行；最终格式仍是 hdiutil 的 ULFO（HFS+，LZFSE 压缩），签名、公证与 staple 流程不变。

- 版本与 sha256 固定在 `packaging/dmg/requirements.txt`（含依赖 ds-store、mac-alias），以 `pip install --require-hashes --only-binary :all: --no-deps` 安装，任何一个包被替换都会失败。
- `make-dmg.sh` 首次运行时在 `build/dmgbuild-venv` 创建虚拟环境并从 PyPI 安装（需联网、Python ≥ 3.10；macOS 自带的 `/usr/bin/python3` 为 3.9，请 `brew install python` 或用 `DMGBUILD_PYTHON` 指定）；`requirements.txt` 未变时直接复用，`make clean` 会一并删除。
- CI（ci.yml 的打包冒烟、release.yml 发布）先用 `actions/setup-python`（固定 SHA）装好 Python 3.13，其余由 `make-dmg.sh` 自行完成；release.yml 在导入签名凭据之前单独运行 `./scripts/make-dmg.sh --prepare` 安装 dmgbuild，PyPI 不可用时尽早失败，安装过程也不接触任何 secret。
- 升级 dmgbuild：在 PyPI 的「Download files」页核对新版本 wheel 与 sdist 的 sha256（依赖同理），改写 `requirements.txt`，再跑一遍 `SIGN_IDENTITY=- make release RELEASE_FLAGS=--skip-notarize` 并目测窗口。

**相关文件**：

| 文件 | 作用 |
| --- | --- |
| `packaging/dmg/layout.json` | 内容区尺寸、标题栏高度、背景底部出血、图标尺寸与字号、两个图标的中心坐标（背景生成脚本与 dmgbuild 配置共用） |
| `packaging/dmg/settings.py` | dmgbuild 配置：文件、快捷方式、窗口样式、图标位置、卷图标、ULFO / HFS+ |
| `scripts/make-dmg-background.swift` | 用 CoreGraphics 生成背景 PNG（1x + 2x），并自检图标名称区域的对比度 |
| `packaging/dmg/background.png`、`background@2x.png` | 生成后提交的背景图；打包时 dmgbuild 用 `tiffutil` 合并为多分辨率的 `.background.tiff` |

**改外观**：修改 `layout.json` 或生成脚本 → `swift scripts/make-dmg-background.swift` → `make dmg` → 双击 `dist/Cubby-<版本>.dmg`，在浅色、深色模式下各看一眼 → 提交两张 PNG。卷内的 `.DS_Store`、`.background.tiff`、`.VolumeIcon.icns` 都是点文件，Finder 默认不显示；`make-dmg.sh` 挂载校验时会确认它们存在、卷图标标记已设置。

注意事项：

- **图标名称的颜色**：由 Finder 决定，背景无法控制（macOS 26 实测浅色、深色模式下都是黑字，较早的系统在深色模式下可能是白字）。所以格子底部（名称所在处）取黑白两色都可读的中间亮度，生成脚本要求两者的对比度都 ≥ 4:1，否则报错。
- **窗口尺寸**：Finder 把 `.DS_Store` 里的窗口尺寸当作含标题栏的整个窗口，因此窗口高度 = 内容区 + 32 pt（macOS 26 的标题栏）；标题栏更矮的旧系统多出的几 pt 由背景底部 8 pt 出血填满，不会露出空白。
- **不给 .app 设「隐藏扩展名」**：dmgbuild 的 `hide_extensions` 会在 .app 根目录写入 FinderInfo，导致 `codesign --verify --strict` 失败；Finder 默认就不显示 `.app` 后缀。
- **卷图标**：取自 .app 内的 `AppIcon.icns`，去掉用不到的 1024 px 版本以减小体积；「自定义图标」标记由 dmgbuild 调用 `SetFile`（Xcode 命令行工具）设置。

## 六、故障排查

### 公证失败（status: Invalid）

`notarize.sh` 会自动打印日志；也可手动查看：

```bash
xcrun notarytool history --keychain-profile cubby-notary
xcrun notarytool log <submission-id> --keychain-profile cubby-notary
codesign -dvv --verbose=4 build/Cubby.app      # 检查 Authority、TeamIdentifier、flags=runtime、Timestamp
```

| 日志提示 | 原因与处理 |
| --- | --- |
| `The signature does not include a secure timestamp` | 使用了 `TIMESTAMP=none` 或非 Developer ID 身份；去掉 `TIMESTAMP` 并用 Developer ID 重新构建 |
| `The executable does not have the hardened runtime enabled` | 签名缺少 `--options runtime`；确认使用的是 `scripts/build-app.sh` |
| `The binary is not signed with a valid Developer ID certificate` | 用了 Apple Development 证书；设置 `SIGN_IDENTITY` 为 Developer ID |
| 嵌套二进制未签名 | 以后引入 framework / helper 时须由内到外逐个签名，不要用 `--deep` |
| 401 / `Invalid credentials` | API Key 被撤销、Key ID / Issuer ID 填错；个人密钥不要传 Issuer ID |
| 长时间 `In Progress` | Apple 服务排队；`xcrun notarytool info <id> ...` 查询，必要时调大 `NOTARY_TIMEOUT` 后重跑 |

### stapler

- `Could not find base64 encoded ticket` / `Record not found`（错误 65）：票据还未同步到 CDN，等几分钟再执行 `xcrun stapler staple <文件>`。
- 公证通过后**不能再修改或重新签名**同一文件，否则票据失效，需要重新公证（`release.sh` 已按「签名 → 公证 → staple → 再打包」的顺序处理）。
- 验证：`xcrun stapler validate <文件>`。

### Gatekeeper

```bash
spctl -a -vvv -t exec /Applications/Cubby.app        # 期望 accepted / source=Notarized Developer ID
spctl -a -vvv -t open --context context:primary-signature Cubby-X.Y.Z.dmg
xattr -p com.apple.quarantine /Applications/Cubby.app   # 查看隔离属性
```

- `source=Unnotarized Developer ID` 或 `rejected`：票据没有 staple 或验证的不是发布的那个文件。
- 直接在 DMG 或「下载」目录中运行会触发 App Translocation（路径含 `/AppTranslocation/`），登录启动等功能异常：先拖入「应用程序」。
- CI runner 默认关闭了 Gatekeeper 评估，`spctl` 在 CI 中通过不代表真实环境通过，务必按第三节第 5 步本地冒烟。

### 辅助功能授权失效

TCC 按签名的 designated requirement 记录授权（Developer ID 为 Team ID + bundle ID；ad-hoc 为 cdhash，每次重建都会变）。以下情况会让系统设置里的开关「看起来开着但实际无效」（日志 `Failed to match existing code requirement`）：

- 在 ad-hoc / Apple Development / Developer ID 之间切换签名身份，或 ad-hoc 重新构建；
- 修改了 bundle ID（如 `.dev` 构建与正式版互相覆盖）。

处理：

```bash
codesign -d -r- /Applications/Cubby.app                 # 查看 designated requirement
tccutil reset Accessibility io.github.no1coder.Cubby    # 重置后重新打开 Cubby 授权
```

开发时建议用 `BUNDLE_ID=io.github.no1coder.Cubby.dev make app` 构建开发版，其授权与偏好和正式版互不影响；数据目录仍默认共享，需要隔离时直接运行可执行文件并指定数据目录：`CUBBY_DATA_DIR=/tmp/cubby-dev build/Cubby.app/Contents/MacOS/Cubby`。注意 `make run` / `make install` 会先结束所有名为 Cubby 的进程（包括正式版）。

### CI 相关

- **lint 本地通过、CI 失败**：swift-format 行为随 Xcode 版本变化。把工作流中的 `XCODE_VERSION` 固定为与本地相同的精确版本（如 `"26.6"`），或本地升级 Xcode 后执行 `make format`。
- **`errSecInternalComponent` / 签名卡住**：临时钥匙串被锁或 `set-key-partition-list` 未生效，检查 `DEVELOPER_ID_P12_PASSWORD` 与 .p12 是否包含私钥。
- **`hdiutil: create failed - Resource busy`**：`make-dmg.sh` 会整体重试 dmgbuild 3 次（dmgbuild 自身也会重试卸载）；本地可 `hdiutil info` 查看并 `hdiutil detach` 残留挂载。
- **dmgbuild 安装失败**：`THESE PACKAGES DO NOT MATCH THE HASHES` 表示下载内容与 `requirements.txt` 中的哈希不符，先到 PyPI 核对文件，不要删掉哈希绕过；提示需要 Python ≥ 3.10 时检查 `python3 --version` 或设置 `DMGBUILD_PYTHON`；离线环境需先在联网时运行一次 `make dmg` 生成 `build/dmgbuild-venv`。
- **卷图标未生效**：缺少 Xcode 命令行工具时 `SetFile` 不可用，dmgbuild 不会报错，但 `make-dmg.sh` 的挂载校验会失败并给出提示；用 `xcode-select -p` 确认已选中 Xcode。
- **tag 与 VERSION 不一致**：删除 tag 后重打：`git push --delete origin vX.Y.Z && git tag -d vX.Y.Z`；已生成的 draft release 一并删除。
- **tap 更新失败**：403 多为 PAT 过期或权限不足；`brew style` 报错时修改 `packaging/homebrew/cubby.rb`；修复后在 Actions → Publish →「Run workflow」输入 tag 重试。

## 七、安全须知

- PR 工作流（ci.yml）不引用任何 secret，权限只读；签名与公证凭据只在需要审批的 `release` 环境中可用，并在任务结束时（`if: always()`）删除临时钥匙串与密钥文件。
- 第三方 action 全部固定到 commit SHA（注释标注版本），升级时同时核对 SHA 与版本号。打包用的 Python 包（dmgbuild 及其依赖）同样固定版本与 sha256（`packaging/dmg/requirements.txt`），只装 wheel、不解析额外依赖。
- 凭据泄露时：立即在 App Store Connect 撤销 API Key、在 GitHub 撤销 PAT 并替换 secrets；若 Developer ID 私钥泄露，联系 Apple 开发者支持评估是否吊销证书（吊销会影响已分发的版本）。
