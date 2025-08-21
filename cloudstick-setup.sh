#!/bin/bash

# =============================================================================
# AudiobookSmith CloudStick Setup Script
# =============================================================================
# This script specifically addresses CloudStick default index.html issues
# and sets up AudiobookSmith to work properly with CloudStick control panel
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}$(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log "Starting AudiobookSmith CloudStick setup..."

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR"

log "Application directory: $APP_DIR"

# Check if running on CloudStick
if [ -d "/www/server" ] || [ -d "/www/wwwroot" ]; then
    info "CloudStick environment detected"
    CLOUDSTICK=true
else
    info "Standard environment detected"
    CLOUDSTICK=false
fi

# Install system dependencies if needed
if command -v apt-get &> /dev/null; then
    log "Installing system dependencies..."
    apt-get update -y
    apt-get install -y python3 python3-pip python3-venv curl supervisor
fi

# Navigate to app directory
cd "$APP_DIR"

# Create virtual environment
if [ ! -d "venv" ]; then
    log "Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
source venv/bin/activate

# Install dependencies
log "Installing Python dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# Create necessary directories
log "Creating upload and analysis directories..."
mkdir -p /tmp/audible_uploads /tmp/audible_analysis
chmod 755 /tmp/audible_uploads /tmp/audible_analysis

if [ "$CLOUDSTICK" = true ]; then
    log "Configuring for CloudStick environment..."
    
    # Create a simple startup script
    cat > start_audiobooksmith.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate
export FLASK_ENV=production
python src/main.py
EOF
    chmod +x start_audiobooksmith.sh
    
    # Create supervisor configuration for CloudStick
    SUPERVISOR_CONF="/etc/supervisor/conf.d/audiobooksmith.conf"
    cat > "$SUPERVISOR_CONF" << EOF
[program:audiobooksmith]
command=$APP_DIR/start_audiobooksmith.sh
directory=$APP_DIR
user=www-data
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/audiobooksmith.log
environment=PATH="$APP_DIR/venv/bin"
EOF

    # Start with supervisor
    log "Starting AudiobookSmith with supervisor..."
    supervisorctl reread
    supervisorctl update
    supervisorctl start audiobooksmith
    
    log "CloudStick setup completed!"
    log "AudiobookSmith is now running on port 5000"
    log "Configure your CloudStick reverse proxy to point to http://127.0.0.1:5000"
    
else
    # Standard deployment
    log "Setting up for standard environment..."
    
    # Create systemd service
    cat > /etc/systemd/system/audiobooksmith.service << EOF
[Unit]
Description=AudiobookSmith Flask Application
After=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$APP_DIR
Environment=PATH=$APP_DIR/venv/bin
ExecStart=$APP_DIR/venv/bin/python src/main.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    # Start service
    systemctl daemon-reload
    systemctl enable audiobooksmith
    systemctl start audiobooksmith
    
    log "Standard setup completed!"
fi

# Health check
log "Performing health check..."
sleep 5

if curl -f -s http://localhost:5000/ > /dev/null; then
    log "🎉 AudiobookSmith is running successfully!"
    log "Application is accessible at http://localhost:5000"
else
    warning "Application may still be starting up. Check logs if issues persist."
fi

# Display next steps
echo -e "\n${BLUE}=== Next Steps ===${NC}"
if [ "$CLOUDSTICK" = true ]; then
    echo -e "${YELLOW}1.${NC} Log into your CloudStick control panel"
    echo -e "${YELLOW}2.${NC} Create a new website for audiobooksmith.app"
    echo -e "${YELLOW}3.${NC} Set up reverse proxy to http://127.0.0.1:5000"
    echo -e "${YELLOW}4.${NC} Enable SSL if desired"
    echo -e "${YELLOW}5.${NC} Test the application at your domain"
    echo -e "\n${GREEN}Supervisor commands:${NC}"
    echo -e "  supervisorctl status audiobooksmith"
    echo -e "  supervisorctl restart audiobooksmith"
    echo -e "  supervisorctl stop audiobooksmith"
else
    echo -e "${YELLOW}1.${NC} Configure your web server (Nginx/Apache) to proxy to port 5000"
    echo -e "${YELLOW}2.${NC} Set up SSL certificate if needed"
    echo -e "${YELLOW}3.${NC} Test the application"
    echo -e "\n${GREEN}Service commands:${NC}"
    echo -e "  systemctl status audiobooksmith"
    echo -e "  systemctl restart audiobooksmith"
    echo -e "  journalctl -u audiobooksmith -f"
fi

log "Setup completed successfully!"

