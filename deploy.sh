#!/bin/bash

# =============================================================================
# AudiobookSmith.app Deployment Script
# =============================================================================
# This script fixes PyMuPDF installation issues on Ubuntu 22.04
# and properly configures the Flask application for deployment
# =============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

# =============================================================================
# This script fixes PyMuPDF installation issues on Ubuntu 22.04
# =============================================================================

log "Starting AudiobookSmith.app deployment..."

# Check if running as root for system operations
if [[ $EUID -eq 0 ]]; then
    warning "Running as root. This is recommended for initial setup."
else
    info "Running as regular user. Some operations may require sudo."
fi

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR"

log "Application directory: $APP_DIR"

# Update system packages
log "Updating system packages..."
if command -v apt-get &> /dev/null; then
    apt-get update -y
    apt-get upgrade -y
    
    # Install system dependencies
    log "Installing system dependencies..."
    apt-get install -y \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        build-essential \
        libssl-dev \
        libffi-dev \
        nginx \
        supervisor \
        git \
        curl \
        wget \
        unzip \
        software-properties-common \
        pkg-config \
        libfreetype6-dev \
        libfontconfig1-dev \
        libjpeg-dev \
        libopenjp2-7-dev \
        libpng-dev \
        libtiff-dev \
        zlib1g-dev \
        libxml2-dev \
        libxslt1-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        libxcb1-dev \
        libxcb-render0-dev \
        libxcb-shape0-dev \
        libxcb-xfixes0-dev
else
    warning "apt-get not found. Please install dependencies manually."
fi

# Navigate to application directory
cd "$APP_DIR"

# Create virtual environment if it doesn't exist
if [ ! -d "venv" ]; then
    log "Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
log "Activating virtual environment..."
source venv/bin/activate

# Upgrade pip
log "Upgrading pip..."
pip install --upgrade pip

# Install Python dependencies
log "Installing Python dependencies..."
pip install -r requirements.txt

# Create necessary directories
log "Creating necessary directories..."
mkdir -p /tmp/audible_uploads
mkdir -p /tmp/audible_analysis
chmod 755 /tmp/audible_uploads
chmod 755 /tmp/audible_analysis

# Create systemd service file
log "Creating systemd service..."
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

# Set proper permissions
log "Setting proper permissions..."
chown -R www-data:www-data "$APP_DIR"
chown -R www-data:www-data /tmp/audible_uploads
chown -R www-data:www-data /tmp/audible_analysis

# Configure Nginx
log "Configuring Nginx..."
cat > /etc/nginx/sites-available/audiobooksmith << EOF
server {
    listen 80;
    server_name audiobooksmith.app www.audiobooksmith.app localhost;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

    # File upload size limit
    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
        proxy_send_timeout 300s;
    }

    # Static files (if any)
    location /static {
        alias $APP_DIR/src/static;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

# Enable the site
if [ -f /etc/nginx/sites-enabled/default ]; then
    log "Removing default Nginx site..."
    rm -f /etc/nginx/sites-enabled/default
fi

ln -sf /etc/nginx/sites-available/audiobooksmith /etc/nginx/sites-enabled/

# Test Nginx configuration
log "Testing Nginx configuration..."
nginx -t

# Start and enable services
log "Starting and enabling services..."
systemctl daemon-reload
systemctl enable audiobooksmith
systemctl restart audiobooksmith
systemctl enable nginx
systemctl restart nginx

# Check service status
log "Checking service status..."
if systemctl is-active --quiet audiobooksmith; then
    log "AudiobookSmith service is running"
else
    error "AudiobookSmith service failed to start"
fi

if systemctl is-active --quiet nginx; then
    log "Nginx service is running"
else
    error "Nginx service failed to start"
fi

# Create a simple health check script
log "Creating health check script..."
cat > "$APP_DIR/health_check.sh" << 'EOF'
#!/bin/bash

# Health check script for AudiobookSmith
echo "Checking AudiobookSmith application health..."

# Check if the application is responding
if curl -f -s http://localhost:5000/ > /dev/null; then
    echo "✅ Application is responding"
else
    echo "❌ Application is not responding"
    echo "Checking service status..."
    systemctl status audiobooksmith
fi

# Check Nginx
if curl -f -s http://localhost/ > /dev/null; then
    echo "✅ Nginx is responding"
else
    echo "❌ Nginx is not responding"
    echo "Checking Nginx status..."
    systemctl status nginx
fi

# Check disk space for upload directories
echo "📁 Upload directory space:"
df -h /tmp/audible_uploads
echo "📁 Analysis directory space:"
df -h /tmp/audible_analysis

# Check recent logs
echo "📋 Recent application logs:"
journalctl -u audiobooksmith --no-pager -n 10
EOF

chmod +x "$APP_DIR/health_check.sh"

# Create log rotation configuration
log "Setting up log rotation..."
cat > /etc/logrotate.d/audiobooksmith << EOF
/var/log/audiobooksmith/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 www-data www-data
    postrotate
        systemctl reload audiobooksmith
    endscript
}
EOF

# Create log directory
mkdir -p /var/log/audiobooksmith
chown www-data:www-data /var/log/audiobooksmith

# Final status check
log "Performing final status check..."
sleep 5

if curl -f -s http://localhost/ > /dev/null; then
    log "🎉 Deployment successful! AudiobookSmith is now accessible at:"
    echo -e "${GREEN}   - http://localhost/${NC}"
    echo -e "${GREEN}   - http://$(hostname -I | awk '{print $1}')/${NC}"
    if [ -n "$DOMAIN" ]; then
        echo -e "${GREEN}   - http://$DOMAIN/${NC}"
    fi
else
    error "Deployment completed but application is not responding. Check logs with: journalctl -u audiobooksmith -f"
fi

log "Deployment completed successfully!"
log "Use './health_check.sh' to monitor the application health"
log "Use 'journalctl -u audiobooksmith -f' to view real-time logs"
log "Use 'systemctl restart audiobooksmith' to restart the application"

# Display useful commands
echo -e "\n${BLUE}=== Useful Commands ===${NC}"
echo -e "${YELLOW}Check application status:${NC} systemctl status audiobooksmith"
echo -e "${YELLOW}View application logs:${NC} journalctl -u audiobooksmith -f"
echo -e "${YELLOW}Restart application:${NC} systemctl restart audiobooksmith"
echo -e "${YELLOW}Check Nginx status:${NC} systemctl status nginx"
echo -e "${YELLOW}Test configuration:${NC} nginx -t"
echo -e "${YELLOW}Health check:${NC} ./health_check.sh"

