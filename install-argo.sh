#!/usr/bin/env bash
set -euo pipefail

# ======================================================
# install-argo.sh
# Cloudflare Tunnel 多域名自动安装脚本 (支持 WS/gRPC/TCP)
# ======================================================

die(){ echo "✖ $*" >&2; exit 1; }
info(){ echo "→ $*"; }

# 是否 root
IS_ROOT=false
if [ "$(id -u)" -eq 0 ]; then
  IS_ROOT=true
fi

# 定义颜色
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[1;34m'
cyan='\033[1;36m'
bold='\033[1m'
re='\033[0m'

clear
echo -e "${cyan}"
echo "╔══════════════════════════════════════════╗"
echo "                                            "
echo "       🚀 Cloudflare Argo 安装器             "
echo "                                            "
echo "╚══════════════════════════════════════════╝"
echo -e "${re}"


# 菜单主体
echo -e "${bold}${green}1) 安装 Argo Tunnel${re}"
echo -e "${bold}${red}2) 卸载 Argo Tunnel${re}"
echo -e "${bold}${yellow}3) 退出脚本${re}"
echo
# 动效输入箭头
for i in {1..1}; do
  echo -ne "${yellow}→ 请选择操作 (1/2/3): ${re}"
  sleep 0.2
  echo -ne "\r"
  sleep 0.2
done

# ===============================================================
# 菜单逻辑
# ===============================================================
while true; do
  read -r -p "$(echo -e "${yellow}→ 请选择操作 (1/2/3): ${re}")" ACTION
  echo
  case "$ACTION" in
    1)
      echo "🟢 进入安装流程..."
      break
      ;;
    2)
      echo "🔴 进入卸载流程..."
      break
      ;;
    3)
      echo -e "${cyan}👋 已退出脚本。${re}"
      exit 0
      ;;
    *)
      echo -e "${red}✖ 无效选择，请输入 1、2 或 3。${re}"
      ;;
  esac
done

# ===============================================================
# 卸载逻辑
# ===============================================================
if [ "$ACTION" = "2" ]; then
  echo "⚠️ 开始卸载 Cloudflare Argo Tunnel..."

  if $IS_ROOT; then
    CRED_DIR="/root/.cloudflared"

    # 优先使用官方卸载命令（Token 方式安装时适用）
    if command -v cloudflared >/dev/null 2>&1; then
      cloudflared service uninstall 2>/dev/null \
        && echo "✅ 官方 service uninstall 执行成功" \
        || echo "⚠️ 官方 uninstall 未执行或已跳过，继续清理残留..."
    fi

    # 补充清理 service 文件（含 update service）
    rm -f /etc/systemd/system/cloudflared.service
    rm -f /etc/systemd/system/cloudflared-update.service
    systemctl daemon-reload || true

  else
    CRED_DIR="${HOME}/.cloudflared"
    SERVICE_FILE="${HOME}/.config/systemd/user/cloudflared.service"

    # 非 root 沿用手动方式
    systemctl --user disable --now cloudflared 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    systemctl --user daemon-reload || true
  fi

  # 清理凭证目录（Token/JSON 文件、config.yml 等）
  rm -rf "$CRED_DIR"

  # 卸载 cloudflared 程序本身
  if command -v cloudflared >/dev/null 2>&1; then
    info "正在移除 cloudflared 程序..."
    apt-get remove -y cloudflared 2>/dev/null || true
  fi

  # 清理 apt 仓库配置及 GPG 公钥
  rm -f /etc/apt/sources.list.d/cloudflared.list
  rm -f /usr/share/keyrings/cloudflare-public-v2.gpg
  apt-get update -qq 2>/dev/null || true

  echo
  info "✅ 已完整卸载 Cloudflare Argo Tunnel"
  echo "删除内容："
  echo "  - cloudflared systemd service"
  echo "  - $CRED_DIR"
  echo "  - cloudflared 程序（apt remove）"
  echo "  - apt 仓库配置及 GPG 公钥"
  echo
  exit 0
fi

# ===============================================================
# 安装逻辑
# ===============================================================
# 检测系统类型（官方安装方式仅支持 apt/debian）
if [ -f /etc/alpine-release ]; then
  PKG_MGR="apk"
elif [ -f /etc/debian_version ]; then
  PKG_MGR="apt"
elif [ -f /etc/redhat-release ]; then
  PKG_MGR="yum"
else
  die "不支持的系统类型。"
fi

# ===============================================================
# 使用官方 apt 源安装 cloudflared
# ===============================================================
install_cloudflared(){
  if command -v cloudflared >/dev/null 2>&1; then
    info "检测到 cloudflared 已安装。"
    return
  fi

  if [ "$PKG_MGR" != "apt" ]; then
    die "官方安装方式仅支持 Debian/Ubuntu（apt）系统。当前系统不支持，请手动安装 cloudflared。"
  fi

  info "正在通过官方 apt 源安装 cloudflared..."

  # 添加 Cloudflare GPG 公钥
  mkdir -p --mode=0755 /usr/share/keyrings
  curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg \
    | tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null

  # 添加官方 apt 仓库
  echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' \
    | tee /etc/apt/sources.list.d/cloudflared.list

  # 安装
  apt-get update && apt-get install -y cloudflared || die "cloudflared 安装失败"

  info "✅ cloudflared 安装完成"
}

install_cloudflared

# ===============================================================
# 配置输入
# ===============================================================
# CLOUD_BIN 确认（优先使用已安装的）
if command -v cloudflared >/dev/null 2>&1; then
  CLOUD_BIN="$(command -v cloudflared)"
else
  CLOUD_BIN="${HOME}/.local/bin/cloudflared"
fi

# 检查版本号
CF_VER="$("$CLOUD_BIN" --version 2>/dev/null | head -n1 | awk '{print $3}' || true)"
if [ -n "$CF_VER" ]; then
  echo "→ 检测到 cloudflared 版本：$CF_VER"
fi
echo

# CRED_DIR 根据是否 root 而定
if $IS_ROOT; then
  CRED_DIR="/root/.cloudflared"
else
  CRED_DIR="${HOME}/.cloudflared"
fi
CONFIG_FILE="$CRED_DIR/config.yml"
TOKEN_FILE="$CRED_DIR/token"
mkdir -p "$CRED_DIR"
chmod 700 "$CRED_DIR"

# 输入域名数量
while true; do
  read -r -p "需要配置多少个域名->端口？(例如 2)： " NUM
  if [[ "$NUM" =~ ^[0-9]+$ ]] && [ "$NUM" -gt 0 ]; then
    break
  else
    echo -e "${red}✖ 请输入有效的数字（必须大于 0）。${re}"
  fi
done

MAPPINGS=""

for i in $(seq 1 "$NUM"); do
  echo
  echo "=== 配置第 $i 个域名 ==="
  while true; do
    read -r -p "请输入要绑定的域名（Public Hostname）： " DOMAIN
    if [[ -n "$DOMAIN" ]]; then
      break
    else
      echo -e "${red}✖ 域名不能为空，请重新输入。${re}"
    fi
  done
  read -r -p "请输入本地监听端口（默认 443）： " PORT
  PORT=${PORT:-443}

  echo
  echo "请选择传输方式："
  echo "1) WebSocket（默认）"
  echo "2) gRPC"
  echo "3) TCP"
  read -r -p "选择传输类型 (1/2/3，默认 1)： " STREAM_TYPE
  STREAM_TYPE=${STREAM_TYPE:-1}

  case "$STREAM_TYPE" in
    1)
      STREAM_TYPE="ws"
      read -r -p "请输入 WebSocket 路径（默认 /）： " WS_PATH
      WS_PATH=${WS_PATH:-/}
      [[ "$WS_PATH" != /* ]] && WS_PATH="/$WS_PATH"
      ;;
    2)
      STREAM_TYPE="grpc"
      read -r -p "请输入 gRPC ServiceName（默认 vmess-grpc）： " WS_PATH
      WS_PATH=${WS_PATH:-vmess-grpc}
      ;;
    3)
      STREAM_TYPE="tcp"
      WS_PATH="-"
      ;;
  esac

  read -r -p "请输入协议类型 (http/https/tcp，默认 http)： " PROTO
  PROTO=${PROTO:-http}
  case "$PROTO" in tcp|http|https) ;; *) PROTO="http" ;; esac
  MAPPINGS="${MAPPINGS}${DOMAIN},${PORT},${WS_PATH},${PROTO},${STREAM_TYPE}\n"
done

# ===============================================================
# 凭证输入
# ===============================================================
echo
echo "请选择凭证方式："
echo "1) Cloudflare Token（推荐）"
echo "2) credentials JSON（直接粘贴内容）"
read -r -p "选择 (1/2) 默认 1： " MODE
MODE=${MODE:-1}

TUNNEL_TOKEN=""
CREDENTIAL_FILE=""

if [ "$MODE" = "1" ]; then
  while true; do
    read -r -p "请输入 Cloudflare Tunnel Token（以 eyJ 开头）： " TUNNEL_TOKEN
    if [[ -n "$TUNNEL_TOKEN" ]]; then
      break
    else
      echo -e "${red}✖ 必须输入 Token，请重新输入。${re}"
    fi
  done
  printf "%s" "$TUNNEL_TOKEN" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  info "✅ Token 已保存：$TOKEN_FILE"

else
  while true; do
    echo
    echo "请输入 Cloudflare Tunnel credentials JSON 内容（可多行粘贴，输入完按回车两次结束）"
    echo "---------------------------------------------"
    JSON_CONTENT=""
    while IFS= read -r line; do
      [ -z "$line" ] && break
      JSON_CONTENT="${JSON_CONTENT}${line}\n"
    done
    echo "---------------------------------------------"
    echo "你输入的内容为："
    echo -e "$JSON_CONTENT"
    echo "---------------------------------------------"
    read -r -p "确认保存吗？(1=保存, 2=重新输入)： " CHOICE
    case "$CHOICE" in
      1)
        JSON_FILE_NAME="$(date +%Y%m%d-%H%M%S)-tunnel.json"
        CREDENTIAL_FILE="$CRED_DIR/$JSON_FILE_NAME"
        printf "%b" "$JSON_CONTENT" > "$CREDENTIAL_FILE"
        chmod 600 "$CREDENTIAL_FILE"
        info "✅ 凭证文件已保存：$CREDENTIAL_FILE"
        break
        ;;
      2)
        echo "🔁 重新输入..."
        ;;
      *)
        echo "无效选择，请输入 1 或 2。"
        ;;
    esac
  done
fi

# ===============================================================
# 生成 config.yml
# ===============================================================
info "生成配置文件：$CONFIG_FILE"
{
  echo "# Cloudflare Tunnel Auto Generated"
  echo
  echo "ingress:"
  echo -e "$MAPPINGS" | while IFS=',' read -r HOST PORT PATH PROTO STREAM_TYPE; do
    [ -z "$HOST" ] && continue
    case "$PROTO" in
      tcp)   SERVICE="tcp://localhost:${PORT}" ;;
      http)  SERVICE="http://localhost:${PORT}" ;;
      https) SERVICE="https://localhost:${PORT}" ;;
    esac

    echo "  - hostname: ${HOST}"
    echo "    service: ${SERVICE}"
    echo "    originRequest:"
    echo "      noTLSVerify: true"
    echo "      httpHostHeader: ${HOST}"

    # WebSocket 模式添加 headers
    if [ "$STREAM_TYPE" = "ws" ] && { [ "$PROTO" = "http" ] || [ "$PROTO" = "https" ]; }; then
      echo "      headers:"
      echo "        Connection: Upgrade"
      echo "        Upgrade: websocket"
    fi

    echo
  done
  echo "  - service: http_status:404"
} > "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"
info "✅ 配置文件写入完成。"

# ===============================================================
# systemd 服务安装
# ===============================================================
if [ "$MODE" = "1" ]; then
  # Token 方式：使用官方 cloudflared service install 命令
  TOKEN_CONTENT="$(tr -d '\r\n' < "$TOKEN_FILE")"
  info "使用官方方式安装 systemd 服务..."

  # 检测是否已存在 cloudflared 相关 service，有则先清理，避免冲突
  if systemctl list-unit-files 2>/dev/null | grep -q 'cloudflared'; then
    info "检测到已有 cloudflared 服务，先执行卸载清理..."
    cloudflared service uninstall 2>/dev/null || true
    # 补充清理可能残留的 service 文件（含 update service）
    rm -f /etc/systemd/system/cloudflared.service
    rm -f /etc/systemd/system/cloudflared-update.service
    systemctl daemon-reload || true
    sleep 1
  fi

  cloudflared service install "${TOKEN_CONTENT}" || die "cloudflared service install 失败"
  sleep 2
  if systemctl is-active --quiet cloudflared; then
    info "✅ cloudflared service 启动成功"
  else
    echo -e "\n${red}✖ Cloudflared 启动失败！${re}"
    echo "------------------------------------------------------------"
    echo "可能原因如下："
    echo -e "  ${yellow}[1]${re} 凭证 Token 无效（登录 Cloudflare Zero Trust 检查）"
    echo -e "  ${yellow}[2]${re} 网络被防火墙或代理阻断（cloudflared 无法连接 Cloudflare）"
    echo "------------------------------------------------------------"
    echo "📋 快速排查命令："
    echo "  journalctl -u cloudflared -n 50 --no-pager"
    echo "  systemctl status cloudflared"
    echo "------------------------------------------------------------"
    echo -e "❗ 解决后可执行： ${yellow}systemctl restart cloudflared${re}"
    echo
    echo -e "${red}⚠️ 安装未成功，请先排查上述问题后重试。${re}"
    echo
    exit 1
  fi

else
  # credentials JSON 方式：手动创建 systemd service 文件
  if $IS_ROOT; then
    EXEC_CMD="$CLOUD_BIN tunnel run --credentials-file ${CREDENTIAL_FILE}"
    SERVICE_FILE="/etc/systemd/system/cloudflared.service"
    info "生成 systemd 服务文件（system）: $SERVICE_FILE"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Cloudflare Tunnel Service
After=network-online.target

[Service]
Type=simple
ExecStart=${EXEC_CMD}
Restart=on-failure
RestartSec=5s
User=root
WorkingDirectory=${CRED_DIR}

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now cloudflared || true
    sleep 2
    if systemctl is-active --quiet cloudflared; then
      info "✅ cloudflared system service 启动成功"
    else
      echo -e "\n${red}✖ Cloudflared 启动失败！${re}"
      echo "------------------------------------------------------------"
      echo "可能原因如下："
      echo -e "  ${yellow}[1]${re} credentials JSON 无效（登录 Cloudflare Zero Trust 检查）"
      echo -e "  ${yellow}[2]${re} config.yml 格式错误（缩进或冒号错位）"
      echo -e "  ${yellow}[3]${re} 端口未开放 / 被占用"
      echo -e "  ${yellow}[4]${re} 网络被防火墙或代理阻断"
      echo "------------------------------------------------------------"
      echo "📋 快速排查命令："
      echo "  journalctl -u cloudflared -n 50 --no-pager"
      echo "  systemctl status cloudflared"
      echo "------------------------------------------------------------"
      echo -e "❗ 解决后可执行： ${yellow}systemctl restart cloudflared${re}"
      echo
      echo -e "${red}⚠️ 安装未成功，请先排查上述问题后重试。${re}"
      echo
      exit 1
    fi

  else
    EXEC_CMD="$CLOUD_BIN tunnel run --credentials-file ${CREDENTIAL_FILE}"
    USER_SERVICE_DIR="${HOME}/.config/systemd/user"
    mkdir -p "$USER_SERVICE_DIR"
    SERVICE_FILE="${USER_SERVICE_DIR}/cloudflared.service"
    info "生成 systemd 用户服务文件（user）: $SERVICE_FILE"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Cloudflare Tunnel Service (user)
After=network-online.target

[Service]
Type=simple
ExecStart=${EXEC_CMD}
Restart=on-failure
RestartSec=5s
WorkingDirectory=${CRED_DIR}

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload || true
    systemctl --user enable --now cloudflared || true
    sleep 1
    if systemctl --user is-active --quiet cloudflared; then
      info "✅ cloudflared 用户服务启动成功（systemd --user）"
      echo "注意：要使用户服务在系统重启后无须登录也能运行，请让管理员执行："
      echo "  loginctl enable-linger ${USER}"
    else
      echo -e "\n${red}✖ Cloudflared 启动失败！${re}"
      echo "------------------------------------------------------------"
      echo "📋 快速排查命令："
      echo "  journalctl --user -u cloudflared -n 50 --no-pager"
      echo "  systemctl --user status cloudflared"
      echo "------------------------------------------------------------"
      echo
      exit 1
    fi
  fi
fi

echo
echo -e "${yellow}"
echo "✅ 安装完成"
echo "=========================================="
echo "config: $CONFIG_FILE"
[ -f "$TOKEN_FILE" ] && echo "token:  $TOKEN_FILE"
[ -n "${CREDENTIAL_FILE:-}" ] && [ -f "${CREDENTIAL_FILE}" ] && echo "凭证:   $CREDENTIAL_FILE"
echo
echo "映射列表："
echo -e "$MAPPINGS"
echo
echo "查看日志： journalctl -u cloudflared -f"
echo "重启服务： systemctl restart cloudflared"
echo "重新执行此脚本(选择2)可卸载"
echo "=========================================="
echo -e "${re}"

# ===============================================================
# 客户端提示
# ===============================================================
echo
echo "=== 客户端配置与 Zero Trust 面板设置提示 ==="
echo -e "$MAPPINGS" | while IFS=',' read -r DOMAIN PORT WS_PATH PROTO STREAM_TYPE; do
  [ -z "$DOMAIN" ] && continue
  echo
  echo "💡 域名: ${DOMAIN}"
  echo "  ➤ Cloudflare Zero Trust 面板中添加 Service："
  if [ "$PROTO" = "tcp" ]; then
    echo "      Service type: TCP"
    echo "      URL: tcp://localhost:${PORT}"
  else
    echo "      Service type: HTTP"
    echo "      URL: ${PROTO}://localhost:${PORT}"
  fi
  echo "      Public hostname: ${DOMAIN}"
  echo

  echo "  ➤ v2rayN/v2rayNG 客户端设置示例："
  case "$STREAM_TYPE" in
    ws)
      echo "      传输协议: WebSocket"
      echo "      路径: ${WS_PATH}"
      ;;
    grpc)
      echo "      传输协议: gRPC"
      echo "      ServiceName: ${WS_PATH}"
      ;;
    tcp)
      echo "      传输协议: TCP"
      ;;
  esac
  echo "      地址: ${DOMAIN}"
  echo "      端口: 443 (Cloudflare)"
  echo "      TLS: tls"
  echo
done
echo "=========================================="
echo
