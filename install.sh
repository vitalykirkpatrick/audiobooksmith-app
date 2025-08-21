#!/bin/bash

# =============================================================================
# AudiobookSmith.app Complete Installation Script
# =============================================================================
# This script fixes 403 Forbidden errors, installs all dependencies,
# and ensures the app works properly through the browser
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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo or run as root user)"
fi

log "🚀 Starting AudiobookSmith.app complete installation..."

# Get current directory
CURRENT_DIR=$(pwd)
log "Current directory: $CURRENT_DIR"

# Detect if we're in the right directory or need to clone
if [ ! -f "src/main.py" ]; then
    if [ ! -d "audiobooksmith-app" ]; then
        log "📥 Cloning AudiobookSmith repository..."
        git clone https://github.com/vitalykirkpatrick/audiobooksmith-app.git
    fi
    cd audiobooksmith-app
fi

APP_DIR=$(pwd)
log "Application directory: $APP_DIR"

# Update system packages
log "📦 Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

# Install system dependencies
log "🔧 Installing system dependencies..."
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
    libxcb-xfixes0-dev \
    sqlite3 \
    libsqlite3-dev

# Create virtual environment
log "🐍 Creating Python virtual environment..."
if [ -d "venv" ]; then
    rm -rf venv
fi
python3 -m venv venv
source venv/bin/activate

# Upgrade pip and install wheel
log "⚙️ Upgrading pip and installing build tools..."
pip install --upgrade pip setuptools wheel

# Install Python dependencies
log "📚 Installing Python dependencies..."
pip install -r requirements.txt

# Create necessary directories with proper permissions
log "📁 Creating necessary directories..."
mkdir -p /tmp/audible_uploads
mkdir -p /tmp/audible_analysis
mkdir -p /var/log/audiobooksmith
mkdir -p /var/run/audiobooksmith

# Set proper ownership and permissions
chown -R www-data:www-data "$APP_DIR"
chown -R www-data:www-data /tmp/audible_uploads
chown -R www-data:www-data /tmp/audible_analysis
chown -R www-data:www-data /var/log/audiobooksmith
chown -R www-data:www-data /var/run/audiobooksmith

chmod 755 /tmp/audible_uploads
chmod 755 /tmp/audible_analysis
chmod 755 /var/log/audiobooksmith
chmod 755 /var/run/audiobooksmith

# Stop any existing services
log "🛑 Stopping existing services..."
systemctl stop audiobooksmith 2>/dev/null || true
supervisorctl stop audiobooksmith 2>/dev/null || true

# Create startup script
log "📝 Creating startup script..."
cat > "$APP_DIR/start.sh" << EOF
#!/bin/bash
cd "$APP_DIR"
source venv/bin/activate
export FLASK_ENV=production
export PYTHONPATH="$APP_DIR:\$PYTHONPATH"
python src/main.py
EOF

chmod +x "$APP_DIR/start.sh"
chown www-data:www-data "$APP_DIR/start.sh"

# Create systemd service
log "🔧 Creating systemd service..."
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
Environment=FLASK_ENV=production
Environment=PYTHONPATH=$APP_DIR
ExecStart=$APP_DIR/start.sh
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Create supervisor configuration as backup
log "📋 Creating supervisor configuration..."
systemctl start supervisor 2>/dev/null || true
systemctl enable supervisor 2>/dev/null || true

cat > /etc/supervisor/conf.d/audiobooksmith.conf << EOF
[program:audiobooksmith]
command=$APP_DIR/start.sh
directory=$APP_DIR
user=www-data
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/audiobooksmith/app.log
environment=PATH="$APP_DIR/venv/bin",FLASK_ENV="production",PYTHONPATH="$APP_DIR"
EOF

# Configure Nginx to fix 403 Forbidden error
log "🌐 Configuring Nginx..."

# Remove default site that might cause conflicts
rm -f /etc/nginx/sites-enabled/default

# Create optimized Nginx configuration
cat > /etc/nginx/sites-available/audiobooksmith << 'EOF'
server {
    listen 80;
    server_name audiobooksmith.app www.audiobooksmith.app localhost _;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

    # File upload size limit
    client_max_body_size 100M;
    client_body_timeout 300s;
    client_header_timeout 300s;

    # Proxy settings to fix 403 errors
    proxy_connect_timeout 75s;
    proxy_send_timeout 300s;
    proxy_read_timeout 300s;
    proxy_buffering off;
    proxy_cache off;
    proxy_request_buffering off;

    location / {
        # Fix for 403 Forbidden errors
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Additional headers to prevent 403 errors
        proxy_set_header Authorization $http_authorization;
        proxy_pass_header Authorization;
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # Handle large file uploads
    location /upload {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_request_buffering off;
        proxy_buffering off;
        client_max_body_size 100M;
    }

    # Error pages
    error_page 502 503 504 /50x.html;
    location = /50x.html {
        return 200 "AudiobookSmith is starting up. Please wait a moment and refresh.";
        add_header Content-Type text/plain;
    }
}
EOF

# Enable the site
ln -sf /etc/nginx/sites-available/audiobooksmith /etc/nginx/sites-enabled/

# Test Nginx configuration
log "🧪 Testing Nginx configuration..."
nginx -t || error "Nginx configuration test failed"

# Start services
log "🚀 Starting services..."
systemctl daemon-reload
systemctl enable audiobooksmith
systemctl start audiobooksmith

# Reload supervisor
supervisorctl reread 2>/dev/null || true
supervisorctl update 2>/dev/null || true

# Restart Nginx
systemctl enable nginx
systemctl restart nginx

# Wait for services to start
log "⏳ Waiting for services to start..."
sleep 10

# Health checks
log "🏥 Performing health checks..."

# Check if Flask app is running
FLASK_RUNNING=false
for i in {1..30}; do
    if curl -f -s http://localhost:5000/ > /dev/null 2>&1; then
        FLASK_RUNNING=true
        break
    fi
    sleep 2
done

if [ "$FLASK_RUNNING" = true ]; then
    log "✅ Flask application is running"
else
    warning "Flask application may still be starting. Checking logs..."
    journalctl -u audiobooksmith --no-pager -n 10
fi

# Check if Nginx is working
if curl -f -s http://localhost/ > /dev/null 2>&1; then
    log "✅ Nginx is working"
else
    warning "Nginx may have issues. Checking configuration..."
    nginx -t
fi

# Create monitoring script
log "📊 Creating monitoring script..."
cat > "$APP_DIR/monitor.sh" << 'EOF'
#!/bin/bash

echo "=== AudiobookSmith Status Monitor ==="
echo

# Check Flask app
echo "🐍 Flask Application:"
if curl -f -s http://localhost:5000/ > /dev/null; then
    echo "  ✅ Running on port 5000"
else
    echo "  ❌ Not responding on port 5000"
fi

# Check Nginx
echo "🌐 Nginx:"
if curl -f -s http://localhost/ > /dev/null; then
    echo "  ✅ Running and proxying correctly"
else
    echo "  ❌ Not responding or proxy issue"
fi

# Check services
echo "🔧 Services:"
if systemctl is-active --quiet audiobooksmith; then
    echo "  ✅ audiobooksmith service: active"
else
    echo "  ❌ audiobooksmith service: inactive"
fi

if systemctl is-active --quiet nginx; then
    echo "  ✅ nginx service: active"
else
    echo "  ❌ nginx service: inactive"
fi

# Check disk space
echo "💾 Disk Space:"
df -h /tmp/audible_uploads | tail -1
df -h /tmp/audible_analysis | tail -1

# Check recent logs
echo "📋 Recent Logs:"
journalctl -u audiobooksmith --no-pager -n 5 | tail -5

echo
echo "=== End Status ==="
EOF

chmod +x "$APP_DIR/monitor.sh"

# Create quick restart script
cat > "$APP_DIR/restart.sh" << 'EOF'
#!/bin/bash
echo "🔄 Restarting AudiobookSmith..."
systemctl restart audiobooksmith
systemctl reload nginx
sleep 5
echo "✅ Restart complete"
./monitor.sh
EOF

chmod +x "$APP_DIR/restart.sh"

# Final status check
log "🎯 Final status check..."
sleep 5

# Test the full chain
FINAL_TEST=false
for i in {1..10}; do
    if curl -f -s http://localhost/ > /dev/null 2>&1; then
        FINAL_TEST=true
        break
    fi
    sleep 3
done

if [ "$FINAL_TEST" = true ]; then
    log "🎉 SUCCESS! AudiobookSmith is now accessible!"
    echo -e "\n${GREEN}=== Installation Complete ===${NC}"
    echo -e "${GREEN}✅ AudiobookSmith is running at:${NC}"
    echo -e "${BLUE}   - http://localhost/${NC}"
    echo -e "${BLUE}   - http://$(hostname -I | awk '{print $1}')/${NC}"
    echo -e "${BLUE}   - https://audiobooksmith.app/ (if DNS is configured)${NC}"
    echo
    echo -e "${YELLOW}📋 Management Commands:${NC}"
    echo -e "  ${GREEN}Monitor status:${NC} ./monitor.sh"
    echo -e "  ${GREEN}Restart app:${NC} ./restart.sh"
    echo -e "  ${GREEN}View logs:${NC} journalctl -u audiobooksmith -f"
    echo -e "  ${GREEN}Stop app:${NC} systemctl stop audiobooksmith"
    echo -e "  ${GREEN}Start app:${NC} systemctl start audiobooksmith"
else
    error "Installation completed but application is not responding. Check logs with: journalctl -u audiobooksmith -f"
fi

log "🏁 Installation script completed!"

