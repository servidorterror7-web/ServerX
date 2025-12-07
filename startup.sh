#!/bin/bash
set -e

LOG_FILE="/tmp/codespace_startup.log"
DISCORD_USER_ID="793218613783691294"
BOT_WEBHOOK_URL="${BOT_WEBHOOK_URL:-https://doce-bt.onrender.com/webhook/tunnel_notify}"

echo "🚀 [$(date)] Iniciando scripts de startup..." | tee -a "$LOG_FILE"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

WORKSPACE_ROOT="${CODESPACE_VSCODE_FOLDER:-/workspaces/$(basename $(pwd))}"
cd "$WORKSPACE_ROOT" || {
    echo -e "${RED}❌ No se pudo acceder al workspace: $WORKSPACE_ROOT${NC}" | tee -a "$LOG_FILE"
    exit 1
}

echo -e "${BLUE}📂 Workspace: $WORKSPACE_ROOT${NC}" | tee -a "$LOG_FILE"

if ! python3 -c "import requests" 2>/dev/null; then
    echo -e "${YELLOW}📦 Instalando requests...${NC}" | tee -a "$LOG_FILE"
    pip install --quiet requests > /tmp/pip_requests.log 2>&1
fi

if [ -f requirements.txt ]; then
    echo -e "${YELLOW}📦 Instalando dependencias de Python...${NC}" | tee -a "$LOG_FILE"
    pip install --quiet -r requirements.txt > /tmp/pip_install.log 2>&1 && \
        echo -e "${GREEN}✅ Dependencias instaladas${NC}" | tee -a "$LOG_FILE" || \
        echo -e "${YELLOW}⚠️  Algunas dependencias fallaron${NC}" | tee -a "$LOG_FILE"
fi

if [ -f web_server.py ]; then
    echo -e "${YELLOW}🌐 Iniciando Web Server con Cloudflare Tunnel...${NC}" | tee -a "$LOG_FILE"
    
    nohup python3 web_server.py > /tmp/web_server.log 2>&1 &
    WEB_PID=$!
    echo -e "${GREEN}✅ Web server iniciado (PID: $WEB_PID)${NC}" | tee -a "$LOG_FILE"
    
    echo -e "${YELLOW}⏳ Esperando a que Cloudflare Tunnel inicie (60s)...${NC}" | tee -a "$LOG_FILE"
    sleep 60
    
    TUNNEL_URL=""
    MAX_RETRIES=5
    
    for attempt in $(seq 1 $MAX_RETRIES); do
        echo -e "${YELLOW}🔍 Intento $attempt/$MAX_RETRIES: Detectando tunnel...${NC}" | tee -a "$LOG_FILE"
        
        if [ -f /tmp/cloudflared.log ]; then
            TUNNEL_URL=$(grep -oP 'https://[a-z0-9-]+\\.trycloudflare\\.com' /tmp/cloudflared.log | tail -1)
            if [ -n "$TUNNEL_URL" ]; then
                echo -e "${GREEN}✅ Tunnel detectado desde logs: $TUNNEL_URL${NC}" | tee -a "$LOG_FILE"
                break
            fi
        fi
        
        TUNNEL_RESPONSE=$(curl -s http://localhost:8080/get_url 2>/dev/null || echo "{}")
        TUNNEL_URL=$(echo "$TUNNEL_RESPONSE" | python3 -c "import sys, json; data = json.load(sys.stdin); print(data.get('tunnel_url', ''))" 2>/dev/null || echo "")
        
        if [ -n "$TUNNEL_URL" ] && [ "$TUNNEL_URL" != "None" ]; then
            echo -e "${GREEN}✅ Tunnel detectado desde API: $TUNNEL_URL${NC}" | tee -a "$LOG_FILE"
            break
        fi
        
        if [ $attempt -lt $MAX_RETRIES ]; then
            echo -e "${YELLOW}⏳ Esperando 15s antes de reintentar...${NC}" | tee -a "$LOG_FILE"
            sleep 15
        fi
    done
    
    if [ -n "$TUNNEL_URL" ] && [ "$TUNNEL_URL" != "None" ]; then
        echo -e "${GREEN}✅ Cloudflare Tunnel detectado: $TUNNEL_URL${NC}" | tee -a "$LOG_FILE"
        
        echo "$TUNNEL_URL" > /tmp/tunnel_url.txt
        
        echo -e "${YELLOW}📤 Notificando al bot de Discord...${NC}" | tee -a "$LOG_FILE"
        
        CODESPACE_NAME="${CODESPACE_NAME:-unknown}"
        TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        
        NOTIFY_RESPONSE=$(python3 -c "
import requests
import json
import sys

try:
    payload = {
        'user_id': '$DISCORD_USER_ID',
        'codespace_name': '$CODESPACE_NAME',
        'tunnel_url': '$TUNNEL_URL',
        'tunnel_type': 'cloudflare',
        'tunnel_port': 8080,
        'timestamp': '$TIMESTAMP',
        'auto_started': True
    }
    
    response = requests.post(
        '$BOT_WEBHOOK_URL',
        json=payload,
        timeout=15
    )
    
    print(response.status_code)
    sys.exit(0 if response.status_code == 200 else 1)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1)
        
        NOTIFY_EXIT_CODE=$?
        
        if [ $NOTIFY_EXIT_CODE -eq 0 ]; then
            echo -e "${GREEN}✅ Bot notificado exitosamente (HTTP $NOTIFY_RESPONSE)${NC}" | tee -a "$LOG_FILE"
        else
            echo -e "${RED}❌ Error notificando al bot: $NOTIFY_RESPONSE${NC}" | tee -a "$LOG_FILE"
        fi
    else
        echo -e "${RED}❌ No se pudo detectar URL del Cloudflare Tunnel${NC}" | tee -a "$LOG_FILE"
        echo -e "${YELLOW}Últimas 30 líneas de cloudflared.log:${NC}" | tee -a "$LOG_FILE"
        tail -30 /tmp/cloudflared.log 2>/dev/null | tee -a "$LOG_FILE" || echo "  (log no encontrado)" | tee -a "$LOG_FILE"
    fi
    
elif [ -f auto_webserver_setup.sh ]; then
    echo -e "${YELLOW}🌐 Ejecutando auto_webserver_setup.sh...${NC}" | tee -a "$LOG_FILE"
    nohup bash auto_webserver_setup.sh > /tmp/web_server.log 2>&1 &
    echo -e "${GREEN}✅ Script de webserver iniciado${NC}" | tee -a "$LOG_FILE"
else
    echo -e "${YELLOW}⚠️  web_server.py no encontrado${NC}" | tee -a "$LOG_FILE"
fi

if [ -f start_server.sh ]; then
    echo -e "${YELLOW}🎮 Iniciando servidor de Minecraft...${NC}" | tee -a "$LOG_FILE"
    nohup bash start_server.sh > /tmp/minecraft_server.log 2>&1 &
    MC_PID=$!
    echo -e "${GREEN}✅ Minecraft iniciado (PID: $MC_PID)${NC}" | tee -a "$LOG_FILE"
elif [ -f run.sh ]; then
    echo -e "${YELLOW}🎮 Iniciando servidor con run.sh...${NC}" | tee -a "$LOG_FILE"
    nohup bash run.sh > /tmp/minecraft_server.log 2>&1 &
    MC_PID=$!
    echo -e "${GREEN}✅ Servidor iniciado (PID: $MC_PID)${NC}" | tee -a "$LOG_FILE"
fi

if [ -f main.py ] && [ -d "d0ce3-Addons" ] || grep -q "d0ce3-Addons" main.py 2>/dev/null; then
    echo -e "${YELLOW}🔧 Iniciando d0ce3-Addons...${NC}" | tee -a "$LOG_FILE"
    nohup python3 main.py > /tmp/addons.log 2>&1 &
    ADDONS_PID=$!
    echo -e "${GREEN}✅ d0ce3-Addons iniciado (PID: $ADDONS_PID)${NC}" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
echo -e "${GREEN}   ✨ Startup completado${NC}" | tee -a "$LOG_FILE"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo -e "${GREEN}📊 Procesos activos:${NC}" | tee -a "$LOG_FILE"
ps aux | grep -E "python3|cloudflared|java" | grep -v grep | tee -a "$LOG_FILE" || echo "  (ninguno detectado)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [ -n "$TUNNEL_URL" ]; then
    echo -e "${GREEN}🌐 Tunnel URL: $TUNNEL_URL${NC}" | tee -a "$LOG_FILE"
fi

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo "✅ [$(date)] Startup script finalizado" | tee -a "$LOG_FILE"
