APP := build/Cubby.app
# 传给 scripts/release.sh 的参数，例如：make release RELEASE_FLAGS=--skip-notarize
RELEASE_FLAGS ?=
FORMAT_PATHS := Sources Tests

.PHONY: build test e2e e2e-panel app run install clean lint format check-cjk strings check-strings coverage dmg release

# 调试构建
build:
	swift build

test:
	swift test

# 截图端到端测试（仅调试构建）：合成输入驱动覆盖层，fixture 采集、独立剪贴板、/tmp 数据目录，不需要任何权限。
# 运行期间覆盖层会全屏出现，请勿操作鼠标键盘；指定脚本：make e2e E2E=window-click,annotate
E2E ?= all
e2e:
	swift build
	.build/debug/Cubby --e2e $(E2E)

# 面板端到端测试（仅调试构建）：翻译卡、⌥↩、按住 ⌥ 等交互，桩翻译服务、演示条目、独立剪贴板、/tmp 数据目录，
# 不联网、不读系统剪贴板。运行期间面板会出现，请勿操作鼠标键盘；指定脚本：make e2e-panel E2E=card-toggle,image
e2e-panel:
	swift build
	.build/debug/Cubby --panel-e2e $(E2E)

# 打包 Release 版 .app（版本号取自 VERSION；签名见 scripts/build-app.sh 注释）
app:
	./scripts/build-app.sh

# 打包并启动（先结束旧进程）
run: app
	-pkill -x Cubby
	open $(APP)

# 安装到 /Applications
install: app
	-pkill -x Cubby
	rm -rf /Applications/Cubby.app
	cp -R $(APP) /Applications/
	open /Applications/Cubby.app

# 代码风格检查（swift-format 随 Xcode 工具链提供，配置见 .swift-format）
lint:
	swift format lint --strict --recursive --parallel $(FORMAT_PATHS)

# 就地格式化
format:
	swift format format --in-place --recursive --parallel $(FORMAT_PATHS)

# 国际化守卫：源码字符串字面量中不得出现汉字
check-cjk:
	./scripts/check-no-cjk.sh

# 从源码提取本地化字符串并合并进 Resources/Localizable.xcstrings（新增文案后运行，再补齐 zh-Hans 翻译）
strings:
	./scripts/sync-strings.sh

# 只检查不写回：catalog 与源码不一致或缺少翻译时失败（CI 使用）
check-strings:
	./scripts/sync-strings.sh --check

# 运行测试并检查 CubbyCore 行覆盖率（门槛 COVERAGE_MIN，默认 95）
coverage:
	./scripts/check-coverage.sh

# 用现有 build/Cubby.app 生成 dist/Cubby-<版本>.dmg（不会重新构建，避免破坏已 staple 的票据；需要时先 make app）
dmg:
	./scripts/make-dmg.sh

# 端到端发布（构建、签名、公证、DMG、zip、校验和、发布说明），详见 docs/RELEASING.md
release: test
	./scripts/release.sh $(RELEASE_FLAGS)

clean:
	rm -rf .build build dist
