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
SOURCE_DB_ENDPOINT=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='SecondDBEndpoint'].OutputValue" --output text)
TARGET_DB_ENDPOINT=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='MasterDBEndpoint'].OutputValue" --output text)

# 認証情報の入力
read -p "データベースユーザー名: " DB_USERNAME
read -sp "データベースパスワード: " DB_PASSWORD
echo ""

# 両方のデータベースからテーブル数を取得して比較
echo "レプリケーション状態を検証中..."

# ソースDBのテーブル数を取得
SOURCE_DB_TABLES=$(mysql -h $SOURCE_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'world';" -s)

# ターゲットDBのテーブル数を取得
TARGET_DB_TABLES=$(mysql -h $TARGET_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'world';" -s)

echo "ソースDB (ソース) のテーブル数: $SOURCE_DB_TABLES"
echo "ターゲットDB (ターゲット) のテーブル数: $TARGET_DB_TABLES"

if [ "$SOURCE_DB_TABLES" -eq "$TARGET_DB_TABLES" ]; then
  echo "✅ テーブル数が一致しています。"
else
  echo "❌ テーブル数が一致していません。レプリケーションに問題がある可能性があります。"
fi

# 各テーブルの行数を比較
echo ""
echo "各テーブルの行数を比較中..."

# テーブル一覧を取得
TABLES=$(mysql -h $SOURCE_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD -e "SHOW TABLES FROM world;" -s)

# 各テーブルの行数を比較
for TABLE in $TABLES; do
  SOURCE_DB_ROWS=$(mysql -h $SOURCE_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD -e "SELECT COUNT(*) FROM world.$TABLE;" -s)
  TARGET_DB_ROWS=$(mysql -h $TARGET_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD -e "SELECT COUNT(*) FROM world.$TABLE;" -s)

  echo "テーブル: $TABLE"
  echo "  ソースDB (ソース) の行数: $SOURCE_DB_ROWS"
  echo "  ターゲットDB (ターゲット) の行数: $TARGET_DB_ROWS"

  if [ "$SOURCE_DB_ROWS" -eq "$TARGET_DB_ROWS" ]; then
    echo "  ✅ 行数が一致しています。"
  else
    echo "  ❌ 行数が一致していません。レプリケーションに問題がある可能性があります。"
  fi
done

# レプリケーション非対象データベースの確認
echo ""
echo "レプリケーション非対象データベース (worldnonrepl) の検証..."

# ターゲットDBにworldnonreplデータベースが存在するか確認
NONREPL_DB_EXISTS=$(mysql -h $TARGET_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD -e "SHOW DATABASES LIKE 'worldnonrepl';" | grep -c worldnonrepl)

if [ "$NONREPL_DB_EXISTS" -eq 0 ]; then
  echo "✅ worldnonreplデータベースはターゲットDBに存在しません。レプリケーション対象外の設定が正常に機能しています。"
else
  echo "❌ worldnonreplデータベースがターゲットDBに存在します。レプリケーション対象外の設定に問題がある可能性があります。"
fi

# 継続的なレプリケーションをテスト
echo ""
echo "継続的なレプリケーションをテスト中..."
echo "ソースDBに新しい行を挿入します..."

# 現在の時刻を使用してユニークな値を作成
TIMESTAMP=$(date +%Y%m%d%H%M%S)
CITY_NAME="TestCity$TIMESTAMP"

# ソースDBに新しい行を挿入
mysql -h $SOURCE_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD -e "INSERT INTO world.city (Name, CountryCode, District, Population) VALUES ('$CITY_NAME', 'JPN', 'Test District', 12345);"

# 少し待機してレプリケーションが完了するのを待つ
echo "レプリケーションが完了するまで10秒待機しています..."
sleep 10

# 挿入した行がターゲットDBに存在するか確認
SOURCE_COUNT=$(mysql -h $SOURCE_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD -e "SELECT COUNT(*) FROM world.city WHERE Name = '$CITY_NAME';" -s)
TARGET_COUNT=$(mysql -h $TARGET_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD -e "SELECT COUNT(*) FROM world.city WHERE Name = '$CITY_NAME';" -s)

echo "ソースDBでの '$CITY_NAME' の数: $SOURCE_COUNT"
echo "ターゲットDBでの '$CITY_NAME' の数: $TARGET_COUNT"

if [ "$TARGET_COUNT" -eq "$SOURCE_COUNT" ] && [ "$TARGET_COUNT" -gt 0 ]; then
  echo "✅ 新しく挿入した行がターゲットDBに正常にレプリケーションされました。"
else
  echo "❌ 新しく挿入した行がターゲットDBにレプリケーションされていません。"
fi

echo ""
echo "レプリケーション検証が完了しました。"