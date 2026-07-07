#!/bin/bash
#==============================================================================
# 测试脚本: pak_linyaps.sh 功能测试
# 功能: 验证 pak_linyaps.sh 模板中的核心函数
#==============================================================================

# 不使用 set -e，因为测试用例的失败不应该立即退出整个脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 测试计数器
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# 测试目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_FILE="${PROJECT_ROOT}/templates/pak_linyaps.sh"

# 测试用临时目录
TEST_TMP_DIR=""
TEST_DESKTOP_DIR=""

#------------------------------------------------------------------------------
# 测试辅助函数
#------------------------------------------------------------------------------
log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

run_test() {
    local msg="$1"
    local cmd="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    if eval "$cmd" > /dev/null 2>&1; then
        log_success "$msg"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "$msg"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

run_test_output() {
    local msg="$1"
    local expected="$2"
    local cmd="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    local actual
    actual=$(eval "$cmd" 2>/dev/null)
    if [[ "$expected" == "$actual" ]]; then
        log_success "$msg"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "$msg"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

setup() {
    log_info "创建测试环境..."
    TEST_TMP_DIR=$(mktemp -d)
    TEST_DESKTOP_DIR="${TEST_TMP_DIR}/share/applications"
    mkdir -p "${TEST_DESKTOP_DIR}"
}

teardown() {
    log_info "清理测试环境..."
    rm -rf "${TEST_TMP_DIR}"
}

#------------------------------------------------------------------------------
# 测试用例: validate_version_format
#------------------------------------------------------------------------------
test_validate_version_format() {
    log_info "测试 validate_version_format 函数..."
    
    local test_cases=(
        "1.2.3.4:0"
        "10.20.30.40:0"
        "1.2.3:1"
        "1.2.3.4.5:1"
        "abc:1"
        "1.2.3.a:1"
        ":1"
    )
    
    for case in "${test_cases[@]}"; do
        local version="${case%:*}"
        local expected="${case##*:}"
        
        local actual
        actual=$(bash -c "
            source <(grep -A20 'validate_version_format()' '${TEMPLATE_FILE}' | head -n21)
            validate_version_format '${version}'
            echo \$?
        " 2>/dev/null)
        
        if [[ "$expected" == "$actual" ]]; then
            log_success "validate_version_format '${version}' -> $actual"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            log_error "validate_version_format '${version}' -> expected $expected, got $actual"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        TESTS_RUN=$((TESTS_RUN + 1))
    done
}

#------------------------------------------------------------------------------
# 测试用例: extract_binary_name_from_desktop
#------------------------------------------------------------------------------
test_extract_binary_name_from_desktop() {
    log_info "测试 extract_binary_name_from_desktop 函数..."
    
    # 创建测试用 .desktop 文件
    cat > "${TEST_DESKTOP_DIR}/test1.desktop" << 'EOF'
[Desktop Entry]
Name=TestApp
Exec=/usr/lib/testapp/testapp --args
Icon=/usr/share/icons/testapp.png
EOF

    cat > "${TEST_DESKTOP_DIR}/test2.desktop" << 'EOF'
[Desktop Entry]
Name=TestApp2
Exec=/usr/bin/testapp2
Icon=/usr/share/icons/testapp2.png
EOF

    # 测试提取功能
    local result
    result=$(bash -c "
        source <(grep -A30 'extract_binary_name_from_desktop()' '${TEMPLATE_FILE}' | head -n31)
        extract_binary_name_from_desktop '${TEST_DESKTOP_DIR}'
    " 2>/dev/null)
    
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$result" == "testapp" ]] || [[ "$result" == "testapp2" ]]; then
        log_success "extract_binary_name_from_desktop 提取到: $result"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "extract_binary_name_from_desktop 期望 testapp 或 testapp2，实际: $result"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例: extract_binary_name_from_desktop 目录不存在
#------------------------------------------------------------------------------
test_extract_binary_name_from_desktop_not_exist() {
    log_info "测试 extract_binary_name_from_desktop 目录不存在情况..."
    
    local result
    result=$(bash -c "
        source <(grep -A30 'extract_binary_name_from_desktop()' '${TEMPLATE_FILE}' | head -n31)
        extract_binary_name_from_desktop '/nonexistent/path'
    " 2>/dev/null)
    
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$result" == "" ]]; then
        log_success "不存在的目录返回空字符串"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "不存在的目录应返回空，实际: '$result'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例: generate_version_from_origin
#------------------------------------------------------------------------------
test_generate_version_from_origin() {
    log_info "测试 generate_version_from_origin 函数..."
    
    local test_cases=(
        "1.2.3.4:1.2.3.4"
        "1.2.3~rc1:1.2.3.0"
        "1.2.3:1.2.3.0"
    )
    
    for case in "${test_cases[@]}"; do
        local input="${case%:*}"
        local expected="${case##*:}"
        
        local result
        result=$(bash -c "
            source <(grep -A35 'generate_version_from_origin()' '${TEMPLATE_FILE}' | head -n36)
            generate_version_from_origin '${input}'
        " 2>/dev/null)
        
        TESTS_RUN=$((TESTS_RUN + 1))
        if [[ "$expected" == "$result" ]]; then
            log_success "generate_version_from_origin '${input}' -> $result"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            log_error "generate_version_from_origin '${input}' -> expected ${expected}, got ${result}"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    done
}

#------------------------------------------------------------------------------
# 测试用例: init_global_data 参数解析
#------------------------------------------------------------------------------
test_init_global_data_args_parsing() {
    log_info "测试 init_global_data 命令行参数解析..."
    
    local output
    output=$(bash -c "
        source '${TEMPLATE_FILE}' 2>/dev/null
        init_global_data --linyaps_arch=x86_64 --origin_version=1.2.3 --ll_version=1.2.3.4 --src_path=/tmp/test.deb --output_dir=/tmp/out
        echo \"linyaps_arch=\${linyaps_arch}\"
        echo \"binary_arch=\${binary_arch}\"
    " 2>&1)
    
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$output" | grep -q "linyaps_arch=x86_64"; then
        log_success "init_global_data 解析 --linyaps_arch=x86_64"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "init_global_data 解析 --linyaps_arch 失败"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$output" | grep -q "binary_arch=amd64"; then
        log_success "x86_64 转换为 amd64"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "x86_64 -> amd64 转换失败"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例: init_global_data ARM64 架构
#------------------------------------------------------------------------------
test_init_global_data_arm64() {
    log_info "测试 init_global_data ARM64 架构转换..."
    
    local output
    output=$(bash -c "
        source '${TEMPLATE_FILE}' 2>/dev/null
        init_global_data --linyaps_arch=arm64
        echo \"binary_arch=\${binary_arch}\"
    " 2>&1)
    
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$output" | grep -q "binary_arch=arm64"; then
        log_success "arm64 架构转换正确"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "arm64 架构转换失败"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例: init_global_data 不支持架构
#------------------------------------------------------------------------------
test_init_global_data_unsupported_arch() {
    log_info "测试 init_global_data 不支持架构..."
    
    TESTS_RUN=$((TESTS_RUN + 1))
    if bash -c "
        source '${TEMPLATE_FILE}' 2>/dev/null
        init_global_data --linyaps_arch=s390x
    " 2>&1 | grep -q "Unsupported architecture"; then
        log_success "不支持的架构应报错"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "不支持的架构未报错"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 主函数
#------------------------------------------------------------------------------
main() {
    echo "========================================"
    echo "  pak_linyaps.sh 功能测试"
    echo "========================================"
    echo ""
    
    setup
    
    # 执行测试
    test_validate_version_format
    test_extract_binary_name_from_desktop
    test_extract_binary_name_from_desktop_not_exist
    test_generate_version_from_origin
    test_init_global_data_args_parsing
    test_init_global_data_arm64
    test_init_global_data_unsupported_arch
    
    teardown
    
    # 输出测试结果
    echo ""
    echo "========================================"
    echo "  测试结果汇总"
    echo "========================================"
    echo "  总计: ${TESTS_RUN}"
    echo -e "  通过: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "  失败: ${RED}${TESTS_FAILED}${NC}"
    echo "========================================"
    
    if [[ ${TESTS_FAILED} -gt 0 ]]; then
        exit 1
    fi
    
    exit 0
}

main "$@"
