# debian-rules-to-linyaps-rules 新人必看
## 简介
  分析项目源代码对应的 Debian 构建规则和构建资源，为玲珑（Linyaps）构建项目生成构建、编译规则。
  产出的 `linglong.yaml` 包含完整的构建规则段（build section），可用于辅助玲珑构建。

## 需要安装的依赖包
```bash
python3-yaml python3-ruamel.yaml
linglong-bin=1.13.7-ziggy2 linglong-builder=1.13.7-ziggy2
```

## skills能力介绍
 - `src2linyaps.debian.analyze-control`: 解析 debian/control 文件，提取源码包名、构建依赖列表、描述信息等结构化数据。处理多个 Package 条目的全量合并去重。基于 apt 仓库解析构建依赖的运行时依赖。
 - `src2linyaps.debian.analyze-rules`: 分析 debian 构建规则和资源文件，输出包含构建工具类型、编译参数及默认值、baseline 版本、源码包名、合并后资源列表、build_section 的最终 YAML。
 - `src2linyaps.debian.build-res-generate`: 基于 analyze-control 输出的依赖信息和 analyze-rules 输出的 build 段，结合模板和默认值配置，生成完整的 linglong.yaml 玲珑构建规则。
 - `src2linyaps.debian.test-deps`: 读取 `debian/control` 中的 `Build-Depends` 字段，通过 `apt-get build-dep --dry-run` 模拟安装检测依赖可用性。输出依赖包的状态：可用、部分缺失或完全不可用。
 - `src2linyaps.source.analyze-args`: 根据构建工具类型读取对应的构建配置文件，解析可修改的编译参数（如 prefix、DESTDIR、CMAKE_INSTALL_PREFIX 等），输出构建工具类型和编译参数列表。
 - `src2linyaps.source.detect-tool`: 扫描项目源码根目录，按优先级匹配特征文件，检测项目使用的构建工具类型。

## 建议提示词
 - `https://linux.apps.demo.com/download/demo.orig.tar.xz`是一个开源项目源码包, `/path/to/your/sourceDebianRules`是此项目的debian构建目录, 帮我转换为玲珑构建配置文件linglong.yaml
 - `https://linux.apps.demo.com/download/demo.orig.tar.xz`是一个开源项目源码包, 帮我转换为玲珑构建配置文件linglong.yaml