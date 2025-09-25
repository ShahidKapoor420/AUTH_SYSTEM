"""
Simple License Key Generator for Whisker Auth TXA
"""
import secrets

def generate_license_key():
    """Generate a secure license key"""
    return secrets.token_hex(32).upper()

# Generate a sample license key
license_key = generate_license_key()

print("🎫 WHISKER AUTH - LICENSE KEY GENERATOR")
print("=" * 40)
print(f"📋 Your License Key: {license_key}")
print(f"🎯 License Type: Enterprise")
print(f"⏰ Valid Until: Never Expires")
print("=" * 40)
print("\n✅ Use this license key to login to Whisker Auth!")