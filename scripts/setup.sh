#!/bin/bash
# スクリプトに実行権限を付与するためのセットアップスクリプト

echo "スクリプトに実行権限を付与しています..."
chmod +x scripts/import_sample_db.sh
chmod +x scripts/verify_replication.sh
chmod +x scripts/manage_dms_task.sh

echo "セットアップが完了しました。"
echo ""
echo "使用方法:"
echo "1. 基本的なAurora MySQL環境をデプロイ:"
echo "   aws cloudformation deploy --template-file templates/rds-replication.yaml --stack-name aurora-mysql-env --parameter-overrides DBUsername=admin DBPassword=YourStrongPassword --capabilities CAPABILITY_IAM"
echo ""
echo "2. 踏み台サーバーに接続してサンプルデータベースをインポート:"
echo "   aws ssm start-session --target \$(aws cloudformation describe-stacks --stack-name aurora-mysql-env --query \"Stacks[0].Outputs[?OutputKey=='BastionInstanceId'].OutputValue\" --output text)"
echo "   ./scripts/import_sample_db.sh aurora-mysql-env"
echo ""
echo "3. DMSレプリケーションをデプロイ:"
echo "   aws cloudformation deploy --template-file templates/dms-replication.yaml --stack-name dms-replication --parameter-overrides ExistingStackName=aurora-mysql-env DBUsername=admin DBPassword=YourStrongPassword --capabilities CAPABILITY_IAM"
echo ""
echo "4. レプリケーションを検証:"
echo "   ./scripts/verify_replication.sh aurora-mysql-env"
echo ""
echo "5. DMSタスクを管理:"
echo "   ./scripts/manage_dms_task.sh dms-replication status"