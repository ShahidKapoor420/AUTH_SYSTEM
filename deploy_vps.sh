#!/bin/bash

# Whisker Auth - VPS Deployment Script
# Run this script on your VPS to deploy the application

set -e  # Exit on any error

echo "🐱 Whisker Auth - VPS Deployment"
echo "=================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="whisker-auth"
APP_USER="whisker"
APP_DIR="/var/www/$APP_NAME"
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
SYSTEMD_DIR="/etc/systemd/system"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Update system
log_info "Updating system packages..."
apt update && apt upgrade -y

# Install required packages
log_info "Installing required packages..."
apt install -y python3 python3-pip python3-venv nginx postgresql postgresql-contrib supervisor ufw git curl

# Create application user
if ! id "$APP_USER" &>/dev/null; then
    log_info "Creating application user: $APP_USER"
    useradd -m -s /bin/bash $APP_USER
else
    log_info "User $APP_USER already exists"
fi

# Create application directory
log_info "Setting up application directory..."
mkdir -p $APP_DIR
chown $APP_USER:$APP_USER $APP_DIR

# Copy application files (assuming they're in current directory)
log_info "Copying application files..."
cp -r frontend/ $APP_DIR/
cp -r backend/ $APP_DIR/
cp requirements-production.txt $APP_DIR/requirements.txt
cp .env.example $APP_DIR/.env
chown -R $APP_USER:$APP_USER $APP_DIR

# Create virtual environment
log_info "Creating Python virtual environment..."
sudo -u $APP_USER python3 -m venv $APP_DIR/venv

# Install Python dependencies
log_info "Installing Python dependencies..."
sudo -u $APP_USER $APP_DIR/venv/bin/pip install --upgrade pip
sudo -u $APP_USER $APP_DIR/venv/bin/pip install -r $APP_DIR/requirements.txt

# Setup PostgreSQL
log_info "Setting up PostgreSQL database..."
sudo -u postgres createdb $APP_NAME || log_warning "Database may already exist"

# Generate secure passwords
DB_PASSWORD=$(openssl rand -base64 32)
SECRET_KEY=$(openssl rand -base64 32)
JWT_SECRET=$(openssl rand -base64 32)

# Create database user
sudo -u postgres psql -c "CREATE USER $APP_USER WITH PASSWORD '$DB_PASSWORD';" || log_warning "User may already exist"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $APP_NAME TO $APP_USER;"

# Update .env file
log_info "Configuring environment variables..."
cat > $APP_DIR/.env << EOF
FLASK_ENV=production
SECRET_KEY=$SECRET_KEY
JWT_SECRET_KEY=$JWT_SECRET
DATABASE_URL=postgresql://$APP_USER:$DB_PASSWORD@localhost/$APP_NAME
PORT=5000
EOF

chown $APP_USER:$APP_USER $APP_DIR/.env
chmod 600 $APP_DIR/.env

# Create Gunicorn configuration
log_info "Creating Gunicorn configuration..."
cat > $APP_DIR/gunicorn.conf.py << 'EOF'
import multiprocessing

bind = "127.0.0.1:5000"
workers = multiprocessing.cpu_count() * 2 + 1
worker_class = "sync"
worker_connections = 1000
max_requests = 1000
max_requests_jitter = 100
timeout = 30
keepalive = 2
preload_app = True
user = "whisker"
group = "whisker"
tmp_upload_dir = None
logfile = "/var/log/whisker-auth/gunicorn.log"
loglevel = "info"
accesslog = "/var/log/whisker-auth/access.log"
access_log_format = '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s"'
EOF

# Create log directory
mkdir -p /var/log/whisker-auth
chown $APP_USER:$APP_USER /var/log/whisker-auth

# Create systemd service
log_info "Creating systemd service..."
cat > $SYSTEMD_DIR/whisker-auth.service << EOF
[Unit]
Description=Whisker Auth - Secure Authentication System
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=notify
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_DIR/backend
Environment=PATH=$APP_DIR/venv/bin
ExecStart=$APP_DIR/venv/bin/gunicorn --config $APP_DIR/gunicorn.conf.py app:app
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=always
RestartSec=3
KillMode=mixed
TimeoutStopSec=5
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$APP_DIR /var/log/whisker-auth
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# Create Nginx configuration
log_info "Creating Nginx configuration..."
cat > $NGINX_AVAILABLE/$APP_NAME << 'EOF'
server {
    listen 80;
    server_name _;  # Replace with your domain
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied expired no-cache no-store private must-revalidate auth;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml+rss application/javascript;
    
    # Static files
    location /static/ {
        alias /var/www/whisker-auth/frontend/assets/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Frontend files
    location / {
        root /var/www/whisker-auth/frontend;
        try_files $uri $uri/ /index.html;
    }
    
    # API routes
    location /api/ {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Logs
    access_log /var/log/nginx/whisker-auth-access.log;
    error_log /var/log/nginx/whisker-auth-error.log;
}
EOF

# Enable Nginx site
ln -sf $NGINX_AVAILABLE/$APP_NAME $NGINX_ENABLED/

# Remove default Nginx site
rm -f $NGINX_ENABLED/default

# Test Nginx configuration
nginx -t

# Configure firewall
log_info "Configuring firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 'Nginx Full'
ufw --force enable

# Initialize database
log_info "Initializing database..."
cd $APP_DIR/backend
sudo -u $APP_USER $APP_DIR/venv/bin/python -c "
from app import app, db, create_tables
with app.app_context():
    create_tables()
    print('Database initialized successfully')
"

# Start and enable services
log_info "Starting services..."
systemctl daemon-reload
systemctl enable whisker-auth
systemctl start whisker-auth
systemctl restart nginx

# Setup log rotation
log_info "Setting up log rotation..."
cat > /etc/logrotate.d/whisker-auth << 'EOF'
/var/log/whisker-auth/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 whisker whisker
    postrotate
        systemctl reload whisker-auth
    endscript
}
EOF

# Create maintenance script
log_info "Installing maintenance script..."
cp whisker-auth-maintenance /usr/local/bin/
chmod +x /usr/local/bin/whisker-auth-maintenance

# Create backup cron job
log_info "Setting up automated backups..."
cat > /etc/cron.d/whisker-auth-backup << 'EOF'
# Backup Whisker Auth database daily at 2 AM
0 2 * * * root /usr/local/bin/whisker-auth-maintenance backup
EOF

# Final status check
log_info "Checking service status..."
sleep 5

if systemctl is-active --quiet whisker-auth; then
    log_success "Whisker Auth service is running"
else
    log_error "Whisker Auth service failed to start"
    journalctl -u whisker-auth --no-pager -n 20
fi

if systemctl is-active --quiet nginx; then
    log_success "Nginx service is running"
else
    log_error "Nginx service failed to start"
fi

# Get server IP
SERVER_IP=$(curl -s https://ipinfo.io/ip || hostname -I | awk '{print $1}')

echo ""
log_success "🎉 Whisker Auth deployment completed!"
echo ""
echo "📋 Deployment Summary:"
echo "======================"
echo "🌐 Application URL: http://$SERVER_IP"
echo "👤 Default admin: admin / Whisker123!"
echo "👤 Demo user: demo / demo123"
echo "📁 App directory: $APP_DIR"
echo "📊 Logs: /var/log/whisker-auth/"
echo "🔧 Management: whisker-auth-maintenance {start|stop|restart|status|logs|update|backup}"
echo ""
echo "🔐 Database credentials saved in: $APP_DIR/.env"
echo ""
echo "Next steps:"
echo "1. Configure your domain name in Nginx config"
echo "2. Set up SSL with Let's Encrypt (recommended)"
echo "3. Configure environment variables if needed"
echo "4. Set up monitoring (optional)"
echo ""
log_info "To set up SSL: certbot --nginx -d yourdomain.com"
echo ""
