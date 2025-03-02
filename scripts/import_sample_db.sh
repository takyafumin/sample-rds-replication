#!/bin/bash
# サンプルデータベースのインポートスクリプト

# エラーが発生したら終了
set -e

# 引数の解析
STACK_NAME=""
SOURCE_DB_ENDPOINT=""
TARGET_DB_ENDPOINT=""
LOCAL_MODE=false

# ヘルプメッセージを表示
function show_help {
    echo "使用方法:"
    echo "  スタック名を指定して実行 (EC2内): $0 <スタック名>"
    echo "  ローカルから実行: $0 --local --source-endpoint <ソースDBエンドポイント> --target-endpoint <ターゲットDBエンドポイント>"
    echo ""
    echo "オプション:"
    echo "  --local                ローカルモードで実行"
    echo "  --source-endpoint      ソースDBのエンドポイント"
    echo "  --target-endpoint      ターゲットDBのエンドポイント"
    echo "  --help                 このヘルプメッセージを表示"
    exit 1
}

# 引数の解析
while [[ $# -gt 0 ]]; do
    case $1 in
        --local)
            LOCAL_MODE=true
            shift
            ;;
        --source-endpoint)
            SOURCE_DB_ENDPOINT="$2"
            shift 2
            ;;
        --target-endpoint)
            TARGET_DB_ENDPOINT="$2"
            shift 2
            ;;
        --help)
            show_help
            ;;
        *)
            if [ -z "$STACK_NAME" ]; then
                STACK_NAME="$1"
                shift
            else
                echo "エラー: 不明な引数 '$1'"
                show_help
            fi
            ;;
    esac
done

# 引数の検証
if [ "$LOCAL_MODE" = true ]; then
    if [ -z "$SOURCE_DB_ENDPOINT" ] || [ -z "$TARGET_DB_ENDPOINT" ]; then
        echo "エラー: ローカルモードでは --source-endpoint と --target-endpoint が必須です"
        show_help
    fi
else
    if [ -z "$STACK_NAME" ]; then
        echo "エラー: スタック名が指定されていません"
        show_help
    fi
fi

# CloudFormationスタックから情報を取得（ローカルモードでない場合）
if [ "$LOCAL_MODE" = false ]; then
    echo "CloudFormationスタックから情報を取得中..."
    SOURCE_DB_ENDPOINT=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='SecondDBEndpoint'].OutputValue" --output text)
    TARGET_DB_ENDPOINT=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='MasterDBEndpoint'].OutputValue" --output text)
fi

# 認証情報の入力
read -p "データベースユーザー名: " DB_USERNAME
read -sp "データベースパスワード: " DB_PASSWORD
echo ""

# サンプルデータディレクトリの確認
SAMPLE_DIR="../resources/samples"
if [ ! -d "$SAMPLE_DIR" ]; then
    SAMPLE_DIR="resources/samples"
    if [ ! -d "$SAMPLE_DIR" ]; then
        echo "エラー: サンプルデータディレクトリが見つかりません"
        exit 1
    fi
fi

# World データベースのインポート（ソースDB）
echo "ソースDBに World データベースをインポートしています..."
mysql -h $SOURCE_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP -e "CREATE DATABASE IF NOT EXISTS world;"
mysql -h $SOURCE_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP world < "$SAMPLE_DIR/world.sql"

# World データベースをレプリケーション用に mydb としてコピー
echo "ソースDBに mydb データベースを作成しています（レプリケーション対象）..."
mysql -h $SOURCE_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP -e "CREATE DATABASE IF NOT EXISTS mydb;"
mysql -h $SOURCE_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP -e "
    USE world;
    SHOW TABLES;" | grep -v Tables_in | while read table; do
    echo "テーブル $table をコピーしています..."
    mysql -h $SOURCE_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP -e "
        CREATE TABLE IF NOT EXISTS mydb.$table LIKE world.$table;
        INSERT INTO mydb.$table SELECT * FROM world.$table;
    "
done

# World データベースを worldnonrepl としてコピー（レプリケーション非対象）
echo "ソースDBに worldnonrepl データベースを作成しています（レプリケーション非対象）..."
mysql -h $SOURCE_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP -e "CREATE DATABASE IF NOT EXISTS worldnonrepl;"
mysql -h $SOURCE_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP -e "
    USE world;
    SHOW TABLES;" | grep -v Tables_in | while read table; do
    echo "テーブル $table をコピーしています..."
    mysql -h $SOURCE_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP -e "
        CREATE TABLE IF NOT EXISTS worldnonrepl.$table LIKE world.$table;
        INSERT INTO worldnonrepl.$table SELECT * FROM world.$table;
    "
done

# ターゲットDBに空のデータベースを作成
echo "ターゲットDBに空の mydb データベースを作成しています..."
mysql -h $TARGET_DB_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP -e "CREATE DATABASE IF NOT EXISTS mydb;"

echo "サンプルデータベースのインポートが完了しました"
echo ""
echo "次のステップ:"
echo "1. DMSレプリケーションスタックをデプロイ: ./run.sh deploy-dms --db-password <パスワード> --source-db mydb"
echo "2. DMSレプリケーションタスクを開始: ./run.sh start-dms"
echo "3. レプリケーションの検証: ./run.sh verify-replication <スタック名>"