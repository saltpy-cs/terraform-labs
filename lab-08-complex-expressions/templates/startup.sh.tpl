#!/bin/bash
# Provisioned by Terraform — do not edit manually.
# templatefile() substitutes ${env} and ${project} at plan time.
ENV="${env}"
PROJECT="${project}"

echo "Starting ${project} in ${env}" >> /var/log/startup.log
apt-get update -y
apt-get install -y nginx
systemctl start nginx
echo "<h1>${project} - ${env}</h1>" > /var/www/html/index.html
