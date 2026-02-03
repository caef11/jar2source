# jar2source 自动化脚本

用于批量反编译 JAR、提取 MyBatis Mapper XML、静态提取 Java Web API 路由，并输出到统一目录与文档，适合审计与离线分析。

## 目录结构要求

- 需要在同一目录下放置：
  - `cfr-0.152.jar`
  - 业务 JAR（多个）
  - 本仓库脚本
- 输出目录：`sources/`

## 脚本说明

### 1) `decompile_all.sh`
- 作用：
  - 使用 CFR 反编译所有业务 JAR 到 `sources/`，包目录融合在一起
  - 提取带有 `<mapper namespace="...">` 的 XML 到 `sources/mapper/`，并保留原路径结构
- 重名规则：
  - 若目标 XML 已存在，保留文件体积更大的那个；大小相同则忽略
- 参数：
  - `--decompile-only`：仅反编译
  - `--mapper-only`：仅提取 Mapper XML
  - `--all`：默认行为（两者都执行）
- 日志：
  - 反编译日志输出到 `sources/_logs/*.log`
  - 失败清单 `sources/_logs/failed.txt`

### 2) `extract_mapper_xml.sh`
- 作用：仅提取 Mapper XML
- 实际调用 `decompile_all.sh --mapper-only`

### 3) `extract_api_routes.sh`
- 作用：静态扫描 `sources/` 下的 Java 文件，提取 Spring 注解 API 路由
- 输出：`api_routes.csv`
- 字段：`method,path,class,handler,source`
- 顺序：保持扫描顺序，便于审计时按 Controller 顺序查看，可在表格工具中自行排序

## 使用方法

1. 确保 `cfr-0.152.jar` 与业务 JAR 位于同一目录
2. 运行反编译与 XML 提取：
   - `./decompile_all.sh`
3. 仅提取 Mapper XML：
   - `./extract_mapper_xml.sh`
4. 提取 API 路由：
   - `./extract_api_routes.sh`

## 注意事项

- 脚本不会修改 `sources/` 中已有 Java 源码内容，仅会新增或覆盖反编译输出与 XML 文件
- 若需要重跑，建议保留现有 `sources/` 或手动清理后再执行

## 许可证

GNU GPL v2
