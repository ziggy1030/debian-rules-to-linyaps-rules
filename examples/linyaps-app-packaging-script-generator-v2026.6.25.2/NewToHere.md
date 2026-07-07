# 新人必看
这是一个开箱即用的agent, 目前已支持通过deb、含二进制的tar压缩包转换为玲珑应用. 你在安装`Release`页面专用`linglong-bin`和`linglong-builder`后即可根据此文档开始使用

## 需要安装的依赖包
```bash
python3-yaml
```

## 工作流程
1. 使用者切换agent至`linyaps-app-packaging-script-generator`
2. 使用者通过json任务列表等方式注入需要生成玲珑应用打包脚本的提示词
3. 等待初始化完成
4. 玲珑应用打包脚本初始化完成，可以根据参数说明执行应用打包工程的`pak_linyaps.sh`来进行打包

## 参考资料/提示词

提供给用户的参考资料设置在目录`examples`中, 用户可以根据示例的json文件创建玲珑应用打包脚本初始化任务

\* json为非必要文件，理论上可以通过宽泛提示词对deb、binary-tar的linux应用进行玲珑适配. 提供格式统一、信息完整的json任务列表可一定程度上提高打包率、降低token消耗

### 可供参考的提示词
```md
根据json任务列表开始玲珑应用打包脚本适配，禁用自动清理, 每个应用依次处理，不得并行
```

### 任务列表示例
 - `examples/batch_init_example.csv`: csv形式的初始化任务清单
 - `examples/batch_init_example.json`: json形式的初始化任务清单
 - `examples/build_config.test.json`: tar-linyaps转换模块的额外可选信息， 用于精确声明应用名、描述、图标下载地址等， 可以提高适配成功率

## 输出资源
支持手动修改、重复使用的应用打包脚本工程`CI_${ll_id}`, `${ll_id}`是实际项目对应的应用包名

```bash
CI_ll_app.netlify.ytdn
├── config
│   └── base_runtime_whitelist.conf
├── pak_linyaps.sh
├── reports
│   ├── structure_validation.json
│   └── yaml_validation.json
├── scripts
│   ├── dedup_desktop_files.sh
│   ├── handle_special_paths.sh
│   └── validate_bin_nesting.sh
└── templates
    ├── files_res
    │   └── share
    └── linglong.yaml
```

## 打包工程使用示例
```bash
./pak_linyaps.sh \
  --linyaps_arch=x86_64 \
  --origin_version="3.6.5" \
  --src_path="/media/deepin/Data/top100-CI/260602-init/src/siyuan-3.6.5-linux.deb" \
  --output_dir="/media/deepin/Data/top100-CI/260602-init/output" \
  --build_tmp_dir="/home/deepin/.cache/siyuan"
```

### 参数解释
 - --linyaps_arch: 玲珑构建工程架构，架构定义参考`x86_64` `arm64` `loong64`
 - --origin_version: 源码上游版本
 - --src_path: 源码本地绝对路径
 - --output_dir: layer包输出地址
 - --build_tmp_dir: 构建工程临时目录
\* 部分LLM生成脚本时可能会自行去除参数，使用参数前需要先确认当前`pak_linyaps`支持你导入的参数