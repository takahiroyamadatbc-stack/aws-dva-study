#!/bin/bash
set -e

# アプリケーション起動(ダミー): デプロイされたバージョンを確認できるようマーカーを残す
echo "dva-010 dummy app version: $(date -u +%Y-%m-%dT%H:%M:%SZ)" | sudo tee /opt/dva-010-app/version.txt
