#!/bin/bash
# サンプルデータベースのインポートスクリプト

# エラーが発生したら終了
set -e

# 設定
STACK_NAME=$1
if [ -z "$STACK_NAME" ]; then
  echo "使用方法: $0 <スタック名>"
  exit 1
fi

# CloudFormationスタックから情報を取得
echo "CloudFormationスタックから情報を取得中..."
SECOND_DB_ENDPOINT=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='SecondDBEndpoint'].OutputValue" --output text)
MASTER_DB_ENDPOINT=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='MasterDBEndpoint'].OutputValue" --output text)

# 認証情報の入力
read -p "データベースユーザー名: " DB_USERNAME
read -sp "データベースパスワード: " DB_PASSWORD
echo ""

# サンプルデータベースのダウンロード
echo "サンプルデータベースをダウンロード中..."
mkdir -p ~/sample_db
cd ~/sample_db

# World データベース
if [ ! -f world.sql ]; then
  echo "World データベースをダウンロード中..."
  wget -q https://downloads.mysql.com/docs/world.sql.gz
  gunzip world.sql.gz
fi

# Employees データベース
if [ ! -f employees.sql ]; then
  echo "Employees データベースをダウンロード中..."
  wget -q https://github.com/datacharmer/test_db/archive/refs/heads/master.zip
  unzip -q master.zip
  cd test_db-master
  # 必要なファイルを結合
  cat employees.sql load_departments.dump load_employees.dump load_dept_emp.dump load_dept_manager.dump load_titles.dump load_salaries.dump > ../employees.sql
  cd ..
  rm -rf test_db-master master.zip
fi

# セカンドDBにサンプルデータベースをインポート
echo "セカンドDBにWorld データベースをインポート中..."
mysql -h $SECOND_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD -e "CREATE DATABASE IF NOT EXISTS world;"
mysql -h $SECOND_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD world < world.sql

echo "セカンドDBにEmployees データベースをインポート中..."
mysql -h $SECOND_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD -e "CREATE DATABASE IF NOT EXISTS employees;"
mysql -h $SECOND_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD employees < employees.sql

# マスターDBに空のWorldデータベースを作成
echo "マスターDBに空のWorld データベースを作成中..."
mysql -h $MASTER_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD -e "CREATE DATABASE IF NOT EXISTS world;"

echo "サンプルデータベースのインポートが完了しました。"
echo "セカンドDB: $SECOND_DB_ENDPOINT"
echo "マスターDB: $MASTER_DB_ENDPOINT"
echo ""
echo "次のステップ:"
echo "1. DMSレプリケーションスタックをデプロイしてください。"
echo "2. レプリケーションタスクが完了したら、verify_replication.sh スクリプトを実行してレプリケーションを検証してください。"