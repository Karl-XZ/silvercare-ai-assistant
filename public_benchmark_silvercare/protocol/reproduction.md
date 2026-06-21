# 复现文档

## 环境

- Node.js 18 或更高版本。
- 不需要安装第三方 npm 包。

## 一键运行

```powershell
cd public_benchmark_silvercare
npm run benchmark
```

## 单步运行

```powershell
npm run benchmark:baseline
npm run benchmark:evaluate
npm run benchmark:report
npm run benchmark:check
```

## 替换为自己的系统输出

1. 读取 `dataset/tasks.jsonl`。
2. 对每条任务调用自己的系统。
3. 按 `protocol/interface_contract.md` 写出 JSONL。
4. 运行：

```powershell
node scripts/evaluate_outputs.mjs your_outputs.jsonl
node scripts/build_report.mjs
```

## 可复用部署包建议

公开仓库中建议保留：

- `public_benchmark_silvercare/`
- 应用接口文档
- 模型下载说明
- 本地和云端运行说明
- 最小可运行 demo
- 自动化测试命令

