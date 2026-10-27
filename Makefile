APP_NAME    := YiKey
APP         := build/$(APP_NAME).app
INSTALL_DIR := $(HOME)/Library/Input Methods
RIME_USER   := $(HOME)/Library/Application Support/YiKey/rime
RIME_DEPLOY := $(shell brew --prefix librime)/bin/rime_deployer
# 雾凇拼音固定版本，升级时改这里后执行 make clean-vendor build
RIME_ICE_REV := da1fbe602e38f26db846fa10120ee64c2b0324c0
RIME_ICE     := vendor/rime-ice
CLT_DEV     := /Library/Developer/CommandLineTools/Library/Developer
# 只装了 Command Line Tools 时，Swift Testing 不在默认搜索路径
TEST_FLAGS  := -Xswiftc -F$(CLT_DEV)/Frameworks -Xlinker -F$(CLT_DEV)/Frameworks \
               -Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks -Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib

.PHONY: build install uninstall log test clean clean-vendor

$(RIME_ICE):
	mkdir -p vendor
	curl -sfL https://codeload.github.com/iDvel/rime-ice/tar.gz/$(RIME_ICE_REV) | tar xz -C vendor
	mv vendor/rime-ice-$(RIME_ICE_REV) $(RIME_ICE)

build: $(RIME_ICE)
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/$(APP_NAME) $(APP)/Contents/MacOS/
	cp Resources/Info.plist $(APP)/Contents/
	cp Resources/icon.tiff Resources/rime/default.custom.yaml $(APP)/Contents/Resources/
	cp -R Resources/en.lproj Resources/zh-Hans.lproj $(APP)/Contents/Resources/
	rsync -a --exclude others --exclude build --exclude '*.md' --exclude '.*' \
		--exclude squirrel.yaml --exclude weasel.yaml --exclude t9.schema.yaml --exclude recipe.yaml \
		$(RIME_ICE)/ $(APP)/Contents/Resources/rime-data/
	codesign --force --sign - $(APP)

install: build
	-killall $(APP_NAME) 2>/dev/null
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	mkdir -p "$(INSTALL_DIR)"
	cp -R $(APP) "$(INSTALL_DIR)/"
	swift Scripts/register.swift "$(INSTALL_DIR)/$(APP_NAME).app"
	@# 预先编译词库，首次切换到输入法时无需等待部署
	mkdir -p "$(RIME_USER)"
	cp Resources/rime/default.custom.yaml "$(RIME_USER)/"
	$(RIME_DEPLOY) --build "$(RIME_USER)" "$(INSTALL_DIR)/$(APP_NAME).app/Contents/Resources/rime-data" "$(RIME_USER)/build" 2>/dev/null

uninstall:
	-killall $(APP_NAME) 2>/dev/null
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"

log:
	log stream --level debug --predicate 'subsystem == "com.owen.inputmethod.YiKey"'

test:
	swift test $(TEST_FLAGS)

clean:
	rm -rf .build build

clean-vendor:
	rm -rf vendor
