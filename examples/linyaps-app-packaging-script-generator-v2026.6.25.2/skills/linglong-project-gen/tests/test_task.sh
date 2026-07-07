#!/bin/bash
#==============================================================================
# 测试任务: 运行 pak_linyaps.sh 完整测试套件
# 用法: ./test_task.sh
#==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_SCRIPT="${SCRIPT_DIR}/test_pak_linyaps.sh"

echo "=========================================="
echo "  linglong-project-gen 测试任务"
echo "=========================================="
echo ""

# 检查测试脚本是否存在
if [[ ! -f "${TEST_SCRIPT}" ]]; then
    echo "错误: 测试脚本不存在: ${TEST_SCRIPT}"
    exit 1
fi

# 检查模板文件是否存在
TEMPLATE_FILE="${PROJECT_ROOT}/templates/pak_linyaps.sh"
if [[ ! -f "${TEMPLATE_FILE}" ]]; then
    echo "错误: 模板文件不存在: ${TEMPLATE_FILE}"
    exit 1
fi

echo "项目根目录: ${PROJECT_ROOT}"
echo "模板文件: ${TEMPLATE_FILE}"
echo "测试脚本: ${TEST_SCRIPT}"
echo ""

# 设置执行权限
chmod +x "${TEST_SCRIPT}"

# 运行测试
echo "开始运行测试..."
echo ""
"${TEST_SCRIPT}"
TEST_RESULT=$?

echo ""
if [[ ${TEST_RESULT} -eq 0 ]]; then
    echo "✅ 测试任务执行成功"
else
    echo "❌ 测试任务执行失败 (退出码: ${TEST_RESULT})"
fi

exit ${TEST_RESULT}
