#!/bin/bash
# サンプルデータベースのインポートスクリプト

# エラーが発生したら終了
set -e

# 引数の解析
STACK_NAME=""
SECOND_DB_ENDPOINT=""
MASTER_DB_ENDPOINT=""
LOCAL_MODE=false

# ヘルプメッセージを表示
function show_help {
    echo "使用方法:"
    echo "  スタック名を指定して実行 (EC2内): $0 <スタック名>"
    echo "  ローカルから実行: $0 --local --second-endpoint <セカンドDBエンドポイント> --master-endpoint <マスターDBエンドポイント>"
    echo ""
    echo "オプション:"
    echo "  --local                ローカルモードで実行"
    echo "  --second-endpoint      セカンドDBのエンドポイント"
    echo "  --master-endpoint      マスターDBのエンドポイント"
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
        --second-endpoint)
            SECOND_DB_ENDPOINT="$2"
            shift 2
            ;;
        --master-endpoint)
            MASTER_DB_ENDPOINT="$2"
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

# 引数のバリデーション
if [ "$LOCAL_MODE" = true ]; then
    if [ -z "$SECOND_DB_ENDPOINT" ] || [ -z "$MASTER_DB_ENDPOINT" ]; then
        echo "エラー: ローカルモードでは --second-endpoint と --master-endpoint が必須です"
        show_help
    fi
else
    if [ -z "$STACK_NAME" ]; then
        echo "エラー: スタック名が指定されていません"
        show_help
    fi
fi

# スクリプトのディレクトリを取得
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# プロジェクトのルートディレクトリを取得
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." &> /dev/null && pwd )"
# サンプルデータディレクトリを設定
SAMPLE_DATA_DIR="$PROJECT_ROOT/resources/samples"

# CloudFormationスタックから情報を取得（ローカルモードでない場合）
if [ "$LOCAL_MODE" = false ]; then
    echo "CloudFormationスタックから情報を取得中..."
    SECOND_DB_ENDPOINT=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='SecondDBEndpoint'].OutputValue" --output text)
    MASTER_DB_ENDPOINT=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='MasterDBEndpoint'].OutputValue" --output text)
else
    echo "ローカルモードで実行中..."
    echo "セカンドDBエンドポイント: $SECOND_DB_ENDPOINT"
    echo "マスターDBエンドポイント: $MASTER_DB_ENDPOINT"
fi

# 認証情報の入力
read -p "データベースユーザー名: " DB_USERNAME
read -sp "データベースパスワード: " DB_PASSWORD
echo ""

# サンプルデータディレクトリの確認
echo "サンプルデータディレクトリを確認中..."
mkdir -p "$SAMPLE_DATA_DIR"

# World データベースファイルの確認
if [ ! -f "$SAMPLE_DATA_DIR/world.sql" ]; then
  echo "エラー: world.sql ファイルが見つかりません。"
  echo "resources/samples ディレクトリに world.sql ファイルを手動で配置してください。"
  exit 1
fi

echo "必要なファイルが見つかりました。データベースのインポートを開始します..."

# ホスト名とポートを分離する関数
parse_endpoint() {
    local endpoint=$1
    local host=$(echo $endpoint | cut -d':' -f1)
    local port=$(echo $endpoint | cut -d':' -f2)
    echo "$host $port"
}

# エンドポイントを解析
SECOND_DB_HOST=$(echo $SECOND_DB_ENDPOINT | cut -d':' -f1)
SECOND_DB_PORT=$(echo $SECOND_DB_ENDPOINT | cut -d':' -f2)
MASTER_DB_HOST=$(echo $MASTER_DB_ENDPOINT | cut -d':' -f1)
MASTER_DB_PORT=$(echo $MASTER_DB_ENDPOINT | cut -d':' -f2)

# セカンドDBにWorldデータベースをインポート（レプリケーション対象）
echo "セカンドDBにWorld データベースをインポート中（レプリケーション対象）..."
mysql -h $SECOND_DB_HOST -P $SECOND_DB_PORT -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP -e "CREATE DATABASE IF NOT EXISTS world;"
mysql -h $SECOND_DB_HOST -P $SECOND_DB_PORT -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP world < "$SAMPLE_DATA_DIR/world.sql"

# セカンドDBにWorldNonReplデータベースをインポート（レプリケーション非対象）
echo "セカンドDBにWorldNonRepl データベースをインポート中（レプリケーション非対象）..."
mysql -h $SECOND_DB_HOST -P $SECOND_DB_PORT -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP -e "CREATE DATABASE IF NOT EXISTS worldnonrepl;"
mysql -h $SECOND_DB_HOST -P $SECOND_DB_PORT -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP worldnonrepl < "$SAMPLE_DATA_DIR/world.sql"

# マスターDBに空のWorldデータベースを作成（レプリケーション対象）
echo "マスターDBに空のWorld データベースを作成中（レプリケーション対象）..."
mysql -h $MASTER_DB_HOST -P $MASTER_DB_PORT -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP -e "CREATE DATABASE IF NOT EXISTS world;"

echo "サンプルデータベースのインポートが完了しました。"
echo "セカンドDB: $SECOND_DB_ENDPOINT"
echo "  - world データベース（レプリケーション対象）"
echo "  - worldnonrepl データベース（レプリケーション非対象）"
echo "マスターDB: $MASTER_DB_ENDPOINT"
echo "  - world データベース（空、レプリケーション対象）"
echo ""
echo "次のステップ:"
echo "1. DMSレプリケーションスタックをデプロイしてください:"
echo "   ./run.sh deploy-dms --db-password <パスワード> --source-db world"
echo "2. レプリケーションタスクが完了したら、レプリケーションを検証してください:"
echo "   ./run.sh verify-replication --master-port <マスターポート> --second-port <セカンドポート>"
echo ""
echo "検証のポイント:"
echo "- world データベースはレプリケーションされるはずです"
echo "- worldnonrepl データベースはレプリケーションされないはずです"