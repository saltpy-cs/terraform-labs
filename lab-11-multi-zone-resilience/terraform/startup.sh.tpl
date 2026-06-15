#!/bin/bash
set -euo pipefail

apt-get update -y
apt-get install -y nginx curl

# Read instance identity from GCP metadata server
HOSTNAME=$(hostname)
ZONE=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/zone" \
  -H "Metadata-Flavor: Google" | cut -d'/' -f4)
INSTANCE_ID=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/id" \
  -H "Metadata-Flavor: Google")

# Main page — shows which instance and zone is serving the request
cat > /var/www/html/index.html <<HTML
<!DOCTYPE html>
<html>
<head><title>${project_name}</title></head>
<body>
  <h1>${project_name}</h1>
  <table>
    <tr><td><strong>Hostname</strong></td><td>$HOSTNAME</td></tr>
    <tr><td><strong>Zone</strong></td><td>$ZONE</td></tr>
    <tr><td><strong>Instance ID</strong></td><td>$INSTANCE_ID</td></tr>
  </table>
  <p><em>Reload to see load balancer round-robin across zones.</em></p>
</body>
</html>
HTML

# Health check endpoint — returns 200 OK when nginx is ready
echo "OK" > /var/www/html/health

systemctl enable nginx
systemctl start nginx
