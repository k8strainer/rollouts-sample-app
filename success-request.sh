#!/bin/bash
export REQUEST_HOST="sample-app.gke1.gfu.cloud"
while true; do curl $REQUEST_HOST/success -H "Host: $REQUEST_HOST" -H "X-Canary: always"; sleep 5; done
