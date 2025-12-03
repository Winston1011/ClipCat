PROJECT=MiniClipboard.xcodeproj
SCHEME=ClipCat
CONFIG=Release
DERIVED=.build
PRODUCT_NAME=ClipCat
APP_PATH=$(DERIVED)/Build/Products/$(CONFIG)/$(PRODUCT_NAME).app
DIST=dist
STAGE=$(DIST)/stage
DEVELOPER_ID?=
TEAM_ID?=
APPLE_ID?=
APP_PASSWORD?=
NOTARY_PROFILE?=
ICON_SRC=public/logo.png
ICONSET=public/logo.iconset
ICON_DST=public/logo.icns
ICON_PAD?=1
PAD_COLOR?=ffffff
RADIUS?=180
INSET?=72

.PHONY: build release app dmg package dist clean

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED) CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

release:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -derivedDataPath $(DERIVED) CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

app: release
	mkdir -p $(DIST)
	rm -rf "$(DIST)/$(PRODUCT_NAME).app"
	cp -R "$(APP_PATH)" "$(DIST)/$(PRODUCT_NAME).app"

dmg-unsigned: app
	rm -rf "$(STAGE)"
	mkdir -p "$(STAGE)"
	cp -R "$(DIST)/$(PRODUCT_NAME).app" "$(STAGE)/$(PRODUCT_NAME).app"
	ln -sf /Applications "$(STAGE)/Applications"
	hdiutil create -volname "$(PRODUCT_NAME)" -srcfolder "$(STAGE)" -ov -format UDZO "$(DIST)/ClipCat.dmg"

dmg: app
	rm -rf "$(STAGE)"
	mkdir -p "$(STAGE)"
	cp -R "$(DIST)/$(PRODUCT_NAME).app" "$(STAGE)/$(PRODUCT_NAME).app"
	ln -sf /Applications "$(STAGE)/Applications"
	hdiutil create -volname "$(PRODUCT_NAME)" -srcfolder "$(STAGE)" -ov -format UDZO "$(DIST)/ClipCat.dmg"

sign-app:
	@if [ -n "$(DEVELOPER_ID)" ]; then \
		codesign --force --deep --timestamp --options runtime \
		--entitlements App/ClipCat.entitlements \
		--sign "$(DEVELOPER_ID)" "$(DIST)/$(PRODUCT_NAME).app"; \
		codesign --verify --deep --strict "$(DIST)/$(PRODUCT_NAME).app"; \
	else \
		echo "Skip signing: DEVELOPER_ID not set"; \
	fi

sign-dmg:
	test -n "$(DEVELOPER_ID)" \
		&& codesign --force --timestamp \
		--sign "$(DEVELOPER_ID)" "$(DIST)/ClipCat.dmg" || true

notarize:
	@if [ -n "$(NOTARY_PROFILE)" ]; then \
		xcrun notarytool submit "$(DIST)/ClipCat.dmg" --keychain-profile "$(NOTARY_PROFILE)" --wait; \
	else \
		test -n "$(APPLE_ID)" && test -n "$(TEAM_ID)" && test -n "$(APP_PASSWORD)"; \
		xcrun notarytool submit "$(DIST)/ClipCat.dmg" --apple-id "$(APPLE_ID)" --team-id "$(TEAM_ID)" --password "$(APP_PASSWORD)" --wait; \
	fi

staple:
	xcrun stapler staple "$(DIST)/ClipCat.dmg"

package: dmg

package-signed: app sign-app dmg sign-dmg notarize staple

icon:
	@test -f "$(ICON_SRC)" || (echo "请先在 public/ 下提供 logo.png" && exit 1)
	rm -rf "$(ICONSET)"
	mkdir -p "$(ICONSET)"
	# 统一源为 PNG
	sips -s format png "$(ICON_SRC)" --out public/logo.src.png >/dev/null
	# 按需填充为正方形画布（默认启用），或直接等比缩放到 1024
	@if [ "$(ICON_PAD)" = "1" ]; then \
		sips --padToHeightWidth 1024 1024 --padColor $(PAD_COLOR) public/logo.src.png --out public/logo.square.png >/dev/null; \
	else \
		sips -z 1024 1024 public/logo.src.png --out public/logo.square.png >/dev/null; \
	fi
	# 生成圆角矩形（优先使用 ImageMagick），否则回退为方形
	@if command -v magick >/dev/null 2>&1; then \
		C=$$((1024-2*$(INSET))); \
		magick public/logo.square.png -alpha set -resize $$Cx$$C -background none -gravity center -extent 1024x1024 \( -size 1024x1024 xc:none -draw "roundrectangle $(INSET),$(INSET) $$((1024-$(INSET))),$$((1024-$(INSET))) $(RADIUS),$(RADIUS)" \) -compose copyopacity -composite public/logo.rounded.png; \
	elif command -v convert >/dev/null 2>&1; then \
		C=$$((1024-2*$(INSET))); \
		convert public/logo.square.png -alpha set -resize $$Cx$$C -background none -gravity center -extent 1024x1024 \( -size 1024x1024 xc:none -draw "roundrectangle $(INSET),$(INSET) $$((1024-$(INSET))),$$((1024-$(INSET))) $(RADIUS),$(RADIUS)" \) -compose copyopacity -composite public/logo.rounded.png; \
	else \
		cp public/logo.square.png public/logo.rounded.png; \
	fi
	# 生成标准 iconset 尺寸
	sips -z 16 16   public/logo.rounded.png --out "$(ICONSET)/icon_16x16.png" >/dev/null
	sips -z 32 32   public/logo.rounded.png --out "$(ICONSET)/icon_16x16@2x.png" >/dev/null
	sips -z 32 32   public/logo.rounded.png --out "$(ICONSET)/icon_32x32.png" >/dev/null
	sips -z 64 64   public/logo.rounded.png --out "$(ICONSET)/icon_32x32@2x.png" >/dev/null
	sips -z 128 128 public/logo.rounded.png --out "$(ICONSET)/icon_128x128.png" >/dev/null
	sips -z 256 256 public/logo.rounded.png --out "$(ICONSET)/icon_128x128@2x.png" >/dev/null
	sips -z 256 256 public/logo.rounded.png --out "$(ICONSET)/icon_256x256.png" >/dev/null
	sips -z 512 512 public/logo.rounded.png --out "$(ICONSET)/icon_256x256@2x.png" >/dev/null
	sips -z 512 512 public/logo.rounded.png --out "$(ICONSET)/icon_512x512.png" >/dev/null
	sips -z 1024 1024 public/logo.rounded.png --out "$(ICONSET)/icon_512x512@2x.png" >/dev/null
	# 转换为 icns 并清理临时文件
	iconutil -c icns -o "$(ICON_DST)" "$(ICONSET)"
	rm -f public/logo.src.png public/logo.square.png public/logo.rounded.png

dist: app

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -derivedDataPath $(DERIVED) clean
	rm -rf "$(DIST)"
