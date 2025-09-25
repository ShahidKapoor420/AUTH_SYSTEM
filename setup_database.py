"""
Manual Database Setup for Whisker Auth TXA
"""
import sqlite3
import os
import secrets
import hashlib
import base64
import hmac
from datetime import datetime

def generate_secure_hash(data, salt=None):
    """Generate secure password hash"""
    if salt is None:
        salt = secrets.token_bytes(32)
    
    key = hashlib.pbkdf2_hmac('sha256', data.encode(), salt, 100000)
    return base64.b64encode(salt + key).decode('utf-8')

def generate_license_key():
    """Generate unique license key"""
    return secrets.token_hex(32).upper()

# Create database directory
db_path = 'backend/instance/whisker_auth_txa.db'
os.makedirs(os.path.dirname(db_path), exist_ok=True)

# Connect to database
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Create tables
cursor.executescript('''
-- Users table
CREATE TABLE IF NOT EXISTS txa_users (
    id INTEGER PRIMARY KEY,
    uuid TEXT UNIQUE,
    username TEXT UNIQUE NOT NULL,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    password_salt TEXT NOT NULL,
    status TEXT DEFAULT 'active',
    is_admin BOOLEAN DEFAULT 0,
    security_level INTEGER DEFAULT 1,
    failed_login_attempts INTEGER DEFAULT 0,
    lockout_until DATETIME,
    last_login_at DATETIME,
    last_login_ip TEXT,
    registered_device_id TEXT,
    hardware_info TEXT,
    device_locked BOOLEAN DEFAULT 0,
    license_key TEXT,
    license_type TEXT DEFAULT 'standard',
    license_expires_at DATETIME,
    allowed_applications TEXT,
    application_roles TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_activity_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Licenses table
CREATE TABLE IF NOT EXISTS txa_licenses (
    id INTEGER PRIMARY KEY,
    key TEXT UNIQUE NOT NULL,
    type TEXT DEFAULT 'standard',
    status TEXT DEFAULT 'unused',
    user_id INTEGER,
    assigned_to TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    activated_at DATETIME,
    expires_at DATETIME,
    max_applications INTEGER DEFAULT 5,
    used_applications INTEGER DEFAULT 0,
    max_devices INTEGER DEFAULT 1,
    registered_devices TEXT,
    FOREIGN KEY (user_id) REFERENCES txa_users(id)
);

-- Applications table
CREATE TABLE IF NOT EXISTS txa_applications (
    id INTEGER PRIMARY KEY,
    uuid TEXT UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    current_version TEXT DEFAULT '1.0.0',
    minimum_version TEXT DEFAULT '1.0.0',
    force_update BOOLEAN DEFAULT 0,
    status TEXT DEFAULT 'active',
    maintenance_message TEXT,
    secret_key TEXT UNIQUE,
    requires_license BOOLEAN DEFAULT 1,
    required_license_type TEXT DEFAULT 'standard',
    total_users INTEGER DEFAULT 0,
    active_sessions INTEGER DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Sessions table
CREATE TABLE IF NOT EXISTS txa_sessions (
    id INTEGER PRIMARY KEY,
    session_id TEXT UNIQUE NOT NULL,
    user_id INTEGER NOT NULL,
    application_id INTEGER,
    device_id TEXT NOT NULL,
    ip_address TEXT,
    user_agent TEXT,
    is_active BOOLEAN DEFAULT 1,
    expires_at DATETIME,
    access_token_hash TEXT,
    last_activity_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES txa_users(id),
    FOREIGN KEY (application_id) REFERENCES txa_applications(id)
);

-- Security Events table
CREATE TABLE IF NOT EXISTS txa_security_events (
    id INTEGER PRIMARY KEY,
    event_type TEXT NOT NULL,
    severity TEXT DEFAULT 'info',
    user_id INTEGER,
    application_id INTEGER,
    device_id TEXT,
    ip_address TEXT,
    description TEXT,
    details TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES txa_users(id),
    FOREIGN KEY (application_id) REFERENCES txa_applications(id)
);
''')

# Create admin user
admin_password = 'TXA2024!@#'
admin_password_hash = generate_secure_hash(admin_password)
admin_uuid = secrets.token_hex(18)

cursor.execute('''
INSERT OR IGNORE INTO txa_users (
    uuid, username, email, password_hash, password_salt, 
    status, is_admin, security_level, license_type
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
''', (
    admin_uuid, 'admin', 'admin@whiskerauth.com', 
    admin_password_hash, secrets.token_hex(16),
    'active', 1, 10, 'enterprise'
))

# Create sample license keys
sample_licenses = [
    (generate_license_key(), 'standard', 5),
    (generate_license_key(), 'premium', 10),
    (generate_license_key(), 'enterprise', 25)
]

for key, license_type, max_apps in sample_licenses:
    cursor.execute('''
    INSERT OR IGNORE INTO txa_licenses (key, type, max_applications)
    VALUES (?, ?, ?)
    ''', (key, license_type, max_apps))

# Create sample application
app_uuid = secrets.token_hex(18)
app_secret = secrets.token_hex(32)

cursor.execute('''
INSERT OR IGNORE INTO txa_applications (
    uuid, name, description, current_version, minimum_version, secret_key
) VALUES (?, ?, ?, ?, ?, ?)
''', (
    app_uuid, 'Whisker Auth Demo', 
    'Demo application for TXA authentication',
    '3.1.2', '3.0.0', app_secret
))

# Commit changes
conn.commit()

# Get sample license for display
cursor.execute('SELECT key, type FROM txa_licenses WHERE status = "unused" LIMIT 1')
sample_license = cursor.fetchone()

print("🔐 WHISKER AUTH - DATABASE INITIALIZED")
print("=====================================")
print("✅ Database Created: whisker_auth_txa.db")
print("✅ Tables: Users, Licenses, Applications, Sessions, Security Events")
print("")
print("👤 Admin Account:")
print("   Username: admin")
print("   Password: TXA2024!@#")
print("   Security Level: 10")
print("")
print("🎫 Sample License Key:")
if sample_license:
    print(f"   Key: {sample_license[0]}")
    print(f"   Type: {sample_license[1]}")
else:
    print("   No licenses available")
print("")
print("✅ Database setup complete!")

conn.close()