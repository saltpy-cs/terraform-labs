#!/bin/bash
# Provisioned by Terraform — do not edit manually
# templatefile() substitutes ${env} and ${project} at plan time.
ENV="${env}"
PROJECT="${project}"

echo "Starting ${project} in ${env} environment" >> /var/log/startup.log
yum install -y httpd
systemctl start httpd
systemctl enable httpd
echo "<h1>${project} - ${env}</h1>" > /var/www/html/index.html
