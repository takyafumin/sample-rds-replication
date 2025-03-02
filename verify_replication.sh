#!/bin/bash
# レプリケーション検証スクリプト

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

# 両方のデータベースからテーブル数を取得して比較
echo "レプリケーション状態を検証中..."

# セカンドDBのテーブル数を取得
SECOND_DB_TABLES=$(mysql -h $SECOND_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'world';" -s)

# マスターDBのテーブル数を取得
MASTER_DB_TABLES=$(mysql -h $MASTER_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'world';" -s)

echo "セカンドDB (ソース) のテーブル数: $SECOND_DB_TABLES"
echo "マスターDB (ターゲット) のテーブル数: $MASTER_DB_TABLES"

if [ "$SECOND_DB_TABLES" -eq "$MASTER_DB_TABLES" ]; then
  echo "✅ テーブル数が一致しています。"
else
  echo "❌ テーブル数が一致していません。レプリケーションに問題がある可能性があります。"
fi

# 各テーブルの行数を比較
echo ""
echo "各テーブルの行数を比較中..."

# テーブル一覧を取得
TABLES=$(mysql -h $SECOND_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD -e "SHOW TABLES FROM world;" -s)

# 各テーブルの行数を比較
for TABLE in $TABLES; do
  SECOND_DB_ROWS=$(mysql -h $SECOND_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD -e "SELECT COUNT(*) FROM world.$TABLE;" -s)
  MASTER_DB_ROWS=$(mysql -h $MASTER_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD -e "SELECT COUNT(*) FROM world.$TABLE;" -s)

  echo "テーブル: $TABLE"
  echo "  セカンドDB (ソース) の行数: $SECOND_DB_ROWS"
  echo "  マスターDB (ターゲット) の行数: $MASTER_DB_ROWS"

  if [ "$SECOND_DB_ROWS" -eq "$MASTER_DB_ROWS" ]; then
    echo "  ✅ 行数が一致しています。"
  else
    echo "  ❌ 行数が一致していません。"
  fi
  echo ""
done

# レプリケーションの継続的な変更をテスト
echo "継続的なレプリケーションをテスト中..."
echo "セカンドDB (ソース) に新しい行を挿入します..."

# 現在の時刻を使用してユニークな値を作成
TIMESTAMP=$(date +%Y%m%d%H%M%S)
CITY_NAME="TestCity$TIMESTAMP"

# セカンドDBに新しい行を挿入
mysql -h $SECOND_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD -e "INSERT INTO world.city (Name, CountryCode, District, Population) VALUES ('$CITY_NAME', 'JPN', 'Test District', 12345);"

# 少し待機してレプリケーションが行われるのを待つ
echo "レプリケーションが完了するまで10秒待機中..."
sleep 10

# マスターDBで挿入された行を確認
MASTER_DB_CHECK=$(mysql -h $MASTER_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD -e "SELECT COUNT(*) FROM world.city WHERE Name = '$CITY_NAME';" -s)

if [ "$MASTER_DB_CHECK" -eq "1" ]; then
  echo "✅ 継続的なレプリケーションが正常に機能しています。挿入された行がマスターDBに複製されました。"
else
  echo "❌ 継続的なレプリケーションに問題があります。挿入された行がマスターDBに複製されていません。"
fi

echo ""
echo "レプリケーション検証が完了しました。"