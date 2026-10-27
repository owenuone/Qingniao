#!/bin/bash
# 把 librime 及其 rime 插件、所有 Homebrew 依赖拷进 App 的 Contents/Frameworks，改为 @rpath 引用并重新签名
# 用法：Scripts/bundle_dylibs.sh <App 路径>
set -euo pipefail

app="$1"
exe="$app/Contents/MacOS/YiKey"
frameworks="$app/Contents/Frameworks"
plugins="$frameworks/rime-plugins"
rime_lib="$(brew --prefix librime)/lib"

mkdir -p "$plugins"
cp "$rime_lib"/rime-plugins/*.dylib "$plugins/"
chmod u+w "$plugins"/*.dylib
for plugin in "$plugins"/*.dylib; do
    install_name_tool -id "@rpath/rime-plugins/$(basename "$plugin")" "$plugin" 2>/dev/null
done

# 待处理的 Mach-O 文件；处理时把其中指向 Homebrew 的引用改成 @rpath，并把被引用的库加入队列
queue=("$exe" "$plugins"/*.dylib)
while ((${#queue[@]})); do
    file="${queue[0]}"
    queue=("${queue[@]:1}")
    own_id="$(otool -D "$file" | tail -n +2)"
    while read -r dep; do
        [[ "$dep" == "$own_id" ]] && continue
        case "$dep" in
            /opt/homebrew/*) source="$dep" ;;
            # 插件按 @rpath 引用 librime
            @rpath/librime.*) source="$rime_lib/${dep#@rpath/}" ;;
            *) continue ;;
        esac
        name="$(basename "$dep")"
        if [[ ! -e "$frameworks/$name" ]]; then
            cp -L "$source" "$frameworks/$name"
            chmod u+w "$frameworks/$name"
            install_name_tool -id "@rpath/$name" "$frameworks/$name" 2>/dev/null
            queue+=("$frameworks/$name")
        fi
        [[ "$dep" == "@rpath/$name" ]] || install_name_tool -change "$dep" "@rpath/$name" "$file" 2>/dev/null
    done < <(otool -L "$file" | tail -n +2 | awk '{print $1}')
done

# 插件自带 @loader_path/.. 的 rpath，正好指向 Frameworks，不用再加
install_name_tool -add_rpath "@executable_path/../Frameworks" "$exe" 2>/dev/null

# install_name_tool 会使原签名失效，先签各个 dylib 再签整个 App
find "$frameworks" -name '*.dylib' -exec codesign --force --sign - {} \;
codesign --force --sign - "$app"

if otool -L "$exe" "$frameworks"/*.dylib "$plugins"/*.dylib | grep -q /opt/homebrew; then
    echo "仍有指向 /opt/homebrew 的引用：" >&2
    otool -L "$exe" "$frameworks"/*.dylib "$plugins"/*.dylib | grep -B20 /opt/homebrew >&2
    exit 1
fi
echo "已打包 $(ls "$frameworks"/*.dylib "$plugins"/*.dylib | wc -l | tr -d ' ') 个 dylib"
