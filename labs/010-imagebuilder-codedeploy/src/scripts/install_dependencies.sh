#!/bin/bash
set -e

# AMIには含めず、デプロイのたびにCodeDeployが実行するダミーの依存関係インストール
echo "アプリ依存関係インストール(ダミー)"
