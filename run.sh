#!/bin/bash

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 設定
STACK_NAME="rds-replication-stack"
TEMPLATE_FILE="templates/rds-replication.yaml"
DMS_STACK_NAME="dms-replication"
DMS_TEMPLATE_FILE="templates/dms-replication.yaml"
IAM_STACK_NAME="dms-iam-roles"
IAM_TEMPLATE_FILE="iam-setup/dms-iam-roles.yaml"
REGION=$(aws configure get region)
if [ -z "$REGION" ]; then
    REGION="ap-northeast-1" # デフォルトリージョン
fi

# ヘルプメッセージを表示
function show_help {
    echo -e "${BLUE}RDSレプリケーション検証環境操作ツール${NC}"
    echo ""
    echo -e "使い方: $0 ${GREEN}コマンド${NC} [オプション]"
    echo ""
    echo -e "${YELLOW}利用可能なコマンド:${NC}"
    echo -e "  ${GREEN}deploy${NC}              - CloudFormationスタックをデプロイします"
    echo -e "  ${GREEN}update${NC}              - CloudFormationスタックを更新します"
    echo -e "  ${GREEN}delete${NC}              - CloudFormationスタックを削除します"
    echo -e "  ${GREEN}status${NC}              - スタックのステータスを表示します"
    echo -e "  ${GREEN}outputs${NC}             - スタックの出力値を表示します"
    echo -e "  ${GREEN}connect-ec2${NC}         - 踏み台EC2インスタンスにSSM接続します"
    echo -e "  ${GREEN}port-forward-master${NC} - マスターDBへのポートフォワーディングを設定します"
    echo -e "  ${GREEN}port-forward-second${NC} - セカンドDBへのポートフォワーディングを設定します"
    echo -e "  ${GREEN}prepare-sample-data${NC} - サンプルデータファイルを準備します"
    echo -e "  ${GREEN}import-sample-db${NC}    - ローカルからサンプルデータベースをインポートします"
    echo -e "  ${GREEN}verify-replication${NC}  - レプリケーションの検証を行います"
    echo -e "  ${GREEN}deploy-dms${NC}          - DMSレプリケーションスタックをデプロイします"
    echo -e "  ${GREEN}status-dms${NC}          - DMSレプリケーションスタックのステータスを表示します"
    echo -e "  ${GREEN}start-dms${NC}           - DMSレプリケーションタスクを開始します"
    echo -e "  ${GREEN}stop-dms${NC}            - DMSレプリケーションタスクを停止します"
    echo -e "  ${GREEN}restart-dms${NC}         - DMSレプリケーションタスクを再起動します"
    echo -e "  ${GREEN}delete-dms${NC}          - DMSレプリケーションスタックを削除します"
    echo -e "  ${GREEN}deploy-iam${NC}          - DMSに必要なIAMロールをデプロイします"
    echo -e "  ${GREEN}delete-iam${NC}          - DMSのIAMロールスタックを削除します"
    echo -e "  ${GREEN}status-iam${NC}          - DMSのIAMロールスタックのステータスを表示します"
    echo -e "  ${GREEN}help${NC}                - このヘルプメッセージを表示します"
    echo ""
    echo -e "${YELLOW}例:${NC}"
    echo -e "  $0 ${GREEN}deploy${NC} --db-password MySecurePassword123"
    echo -e "  $0 ${GREEN}connect-ec2${NC}"
    echo -e "  $0 ${GREEN}prepare-sample-data${NC}"
    echo -e "  $0 ${GREEN}port-forward-master${NC} --local-port 13306"
    echo -e "  $0 ${GREEN}port-forward-second${NC} --local-port 13307"
    echo -e "  $0 ${GREEN}import-sample-db${NC} --master-port 13306 --second-port 13307"
    echo -e "  $0 ${GREEN}verify-replication${NC} --master-port 13306 --second-port 13307"
    echo -e "  $0 ${GREEN}deploy-dms${NC} --db-password MySecurePassword123 --source-db world"
    echo -e "  $0 ${GREEN}delete-dms${NC}"
    echo -e "  $0 ${GREEN}deploy-iam${NC}"
    echo -e "  $0 ${GREEN}delete-iam${NC}"
    echo -e "  $0 ${GREEN}status-iam${NC}"
    echo ""
}

# スタックの存在確認
function check_stack_exists {
    aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION &> /dev/null
    return $?
}

# DMSスタックの存在確認
function check_dms_stack_exists {
    aws cloudformation describe-stacks --stack-name $DMS_STACK_NAME --region $REGION &> /dev/null
    return $?
}

# スタックの出力値を取得
function get_stack_output {
    local output_key=$1
    aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" --output text
}

# サンプルデータファイルを準備
function prepare_sample_data {
    echo -e "${BLUE}サンプルデータファイルを準備しています...${NC}"

    # サンプルデータディレクトリを作成
    local SAMPLE_DIR="resources/samples"
    mkdir -p "$SAMPLE_DIR"

    # World データベースの準備
    if [ -f "$SAMPLE_DIR/world.sql" ]; then
        echo -e "${GREEN}world.sql ファイルは既に存在します${NC}"
    elif [ -f "$SAMPLE_DIR/world-db.zip" ]; then
        echo -e "${BLUE}world-db.zip を解凍しています...${NC}"

        # 一時ディレクトリを作成
        local TEMP_DIR=$(mktemp -d)
        unzip -q "$SAMPLE_DIR/world-db.zip" -d "$TEMP_DIR"

        # 解凍されたSQLファイルを探して移動
        local SQL_FILE=$(find "$TEMP_DIR" -name "*.sql" | head -n 1)
        if [ -n "$SQL_FILE" ]; then
            cp "$SQL_FILE" "$SAMPLE_DIR/world.sql"
            echo -e "${GREEN}world.sql ファイルを作成しました${NC}"
        else
            echo -e "${RED}world-db.zip 内にSQLファイルが見つかりませんでした${NC}"
            echo -e "${YELLOW}手動で world.sql ファイルを $SAMPLE_DIR ディレクトリに配置してください${NC}"
        fi

        # 一時ディレクトリを削除
        rm -rf "$TEMP_DIR"
    else
        echo -e "${YELLOW}world-db.zip ファイルが見つかりません${NC}"
        echo -e "${YELLOW}MySQL公式サイト (https://dev.mysql.com/doc/index-other.html) から「world database」をダウンロードし、${NC}"
        echo -e "${YELLOW}$SAMPLE_DIR/world.sql として保存してください${NC}"
    fi

    # Employees データベースの準備
    if [ -f "$SAMPLE_DIR/employees.sql" ]; then
        echo -e "${GREEN}employees.sql ファイルは既に存在します${NC}"
    elif [ -f "$SAMPLE_DIR/test_db-1.0.7.tar.gz" ]; then
        echo -e "${BLUE}test_db-1.0.7.tar.gz を解凍しています...${NC}"

        # 一時ディレクトリを作成
        local TEMP_DIR=$(mktemp -d)

        # tar.gzファイルを解凍
        echo -e "${BLUE}アーカイブを展開中...${NC}"
        tar -xzf "$SAMPLE_DIR/test_db-1.0.7.tar.gz" -C "$TEMP_DIR"

        # 解凍されたディレクトリを探す
        local TEST_DB_DIR=$(find "$TEMP_DIR" -type d -name "test_db*" | head -n 1)

        if [ -d "$TEST_DB_DIR" ]; then
            # employees.sqlファイルが存在するか確認
            if [ -f "$TEST_DB_DIR/employees.sql" ]; then
                echo -e "${BLUE}employees.sql ファイルをコピーしています...${NC}"
                cp "$TEST_DB_DIR/employees.sql" "$SAMPLE_DIR/employees.sql"
                echo -e "${GREEN}employees.sql ファイルを作成しました${NC}"
                echo -e "${BLUE}ファイルサイズ: $(du -h "$SAMPLE_DIR/employees.sql" | cut -f1)${NC}"
            else
                echo -e "${RED}employees.sql ファイルが見つかりません${NC}"
                echo -e "${YELLOW}手動で employees.sql ファイルを $SAMPLE_DIR ディレクトリに配置してください${NC}"
            fi
        else
            echo -e "${RED}test_db-1.0.7.tar.gz の解凍に失敗しました${NC}"
            echo -e "${YELLOW}手動で employees.sql ファイルを $SAMPLE_DIR ディレクトリに配置してください${NC}"
        fi

        # 一時ディレクトリを削除
        echo -e "${BLUE}一時ファイルを削除中...${NC}"
        rm -rf "$TEMP_DIR"
    else
        echo -e "${YELLOW}test_db-1.0.7.tar.gz ファイルが見つかりません${NC}"
        echo -e "${YELLOW}以下の手順でEmployeesデータベースを準備してください:${NC}"
        echo -e "1. ${YELLOW}GitHub リポジトリ (https://github.com/datacharmer/test_db) からダウンロード${NC}"
        echo -e "2. ${YELLOW}ダウンロードしたファイルを $SAMPLE_DIR/test_db-1.0.7.tar.gz として保存${NC}"
        echo -e "3. ${YELLOW}再度 ./run.sh prepare-sample-data を実行${NC}"
    fi

    # 結果の確認
    if [ -f "$SAMPLE_DIR/world.sql" ] && [ -f "$SAMPLE_DIR/employees.sql" ]; then
        echo -e "${GREEN}サンプルデータファイルの準備が完了しました${NC}"
        echo -e "${BLUE}次のステップ:${NC}"
        echo -e "1. ${YELLOW}./run.sh port-forward-master --local-port 13306${NC} (別ターミナルで実行)"
        echo -e "2. ${YELLOW}./run.sh port-forward-second --local-port 13307${NC} (別ターミナルで実行)"
        echo -e "3. ${YELLOW}./run.sh import-sample-db --master-port 13306 --second-port 13307${NC}"
    else
        echo -e "${RED}サンプルデータファイルの準備に失敗しました${NC}"
        echo -e "${YELLOW}必要なファイルを手動で $SAMPLE_DIR ディレクトリに配置してください:${NC}"
        [ ! -f "$SAMPLE_DIR/world.sql" ] && echo -e "- world.sql"
        [ ! -f "$SAMPLE_DIR/employees.sql" ] && echo -e "- employees.sql"
    fi
}

# ローカルからサンプルデータベースをインポート
function import_sample_db_local {
    local master_port=13306
    local second_port=13307

    # パラメータの解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            --master-port)
                master_port="$2"
                shift 2
                ;;
            --second-port)
                second_port="$2"
                shift 2
                ;;
            *)
                echo -e "${RED}エラー: 不明なオプション: $1${NC}"
                return 1
                ;;
        esac
    done

    # スタックが存在するか確認
    if ! check_stack_exists; then
        echo -e "${RED}エラー: スタック '$STACK_NAME' が存在しません${NC}"
        return 1
    fi

    # サンプルデータファイルの存在確認
    local SAMPLE_DIR="resources/samples"
    if [ ! -f "$SAMPLE_DIR/world.sql" ] || [ ! -f "$SAMPLE_DIR/employees.sql" ]; then
        echo -e "${RED}エラー: サンプルデータファイルが見つかりません${NC}"
        echo -e "${YELLOW}先に以下のコマンドを実行してサンプルデータを準備してください:${NC}"
        echo -e "  $0 prepare-sample-data"
        return 1
    fi

    echo -e "${BLUE}ローカルからサンプルデータベースをインポートします...${NC}"
    echo -e "${YELLOW}注意: このコマンドを実行する前に、別のターミナルで以下のコマンドを実行してポートフォワーディングを設定してください:${NC}"
    echo -e "  $0 port-forward-master --local-port $master_port"
    echo -e "  $0 port-forward-second --local-port $second_port"
    echo ""

    # ポートフォワーディングの確認
    echo -e "${BLUE}ポートフォワーディングの接続確認を行います...${NC}"
    local master_check=false
    local second_check=false

    # マスターDBへの接続確認
    if nc -z localhost $master_port 2>/dev/null; then
        echo -e "${GREEN}マスターDBへのポートフォワーディング (localhost:$master_port) が正常に機能しています${NC}"
        master_check=true
    else
        echo -e "${RED}マスターDBへのポートフォワーディングが機能していません${NC}"
        echo -e "${YELLOW}別のターミナルで以下のコマンドを実行してください:${NC}"
        echo -e "  $0 port-forward-master --local-port $master_port"
    fi

    # セカンドDBへの接続確認
    if nc -z localhost $second_port 2>/dev/null; then
        echo -e "${GREEN}セカンドDBへのポートフォワーディング (localhost:$second_port) が正常に機能しています${NC}"
        second_check=true
    else
        echo -e "${RED}セカンドDBへのポートフォワーディングが機能していません${NC}"
        echo -e "${YELLOW}別のターミナルで以下のコマンドを実行してください:${NC}"
        echo -e "  $0 port-forward-second --local-port $second_port"
    fi

    # 両方のポートフォワーディングが機能していない場合は終了
    if [ "$master_check" = false ] || [ "$second_check" = false ]; then
        echo -e "${RED}ポートフォワーディングの設定を確認してから再試行してください${NC}"
        return 1
    fi

    # スクリプトを実行
    echo -e "${BLUE}サンプルデータベースのインポートを開始します...${NC}"
    ./scripts/import_sample_db.sh --local \
        --second-endpoint "localhost:$second_port" \
        --master-endpoint "localhost:$master_port"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}サンプルデータベースのインポートが完了しました${NC}"
        echo -e "${BLUE}次のステップ:${NC}"
        echo -e "1. ${YELLOW}./run.sh deploy-dms --db-password <パスワード> --source-db world${NC}"
        echo -e "2. DMSレプリケーションが完了したら: ${YELLOW}./run.sh verify-replication --master-port $master_port --second-port $second_port${NC}"
    else
        echo -e "${RED}サンプルデータベースのインポートに失敗しました${NC}"
        echo -e "${YELLOW}エラーの詳細を確認するには、スクリプトを直接実行してみてください:${NC}"
        echo -e "  ./scripts/import_sample_db.sh --local --second-endpoint localhost:$second_port --master-endpoint localhost:$master_port"
        return 1
    fi
}

# スタックをデプロイ
function deploy_stack {
    local db_password=""
    local db_username="admin"
    local master_db_name="hogedb"
    local second_db_name="fugadb"
    local db_instance_class="db.t3.medium"
    local ec2_instance_type="t3.micro"

    # パラメータの解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            --db-password)
                db_password="$2"
                shift 2
                ;;
            --db-username)
                db_username="$2"
                shift 2
                ;;
            --master-db-name)
                master_db_name="$2"
                shift 2
                ;;
            --second-db-name)
                second_db_name="$2"
                shift 2
                ;;
            --db-instance-class)
                db_instance_class="$2"
                shift 2
                ;;
            --ec2-instance-type)
                ec2_instance_type="$2"
                shift 2
                ;;
            *)
                echo -e "${RED}エラー: 不明なオプション: $1${NC}"
                return 1
                ;;
        esac
    done

    # DBパスワードが指定されていない場合はエラー
    if [ -z "$db_password" ]; then
        echo -e "${RED}エラー: DBパスワードを指定してください (--db-password)${NC}"
        return 1
    fi

    echo -e "${BLUE}CloudFormationスタックをデプロイしています...${NC}"

    # スタックのデプロイ
    aws cloudformation create-stack \
        --stack-name $STACK_NAME \
        --template-body file://$TEMPLATE_FILE \
        --region $REGION \
        --parameters \
            ParameterKey=DBPassword,ParameterValue=$db_password \
            ParameterKey=DBUsername,ParameterValue=$db_username \
            ParameterKey=MasterDBName,ParameterValue=$master_db_name \
            ParameterKey=SecondDBName,ParameterValue=$second_db_name \
            ParameterKey=DBInstanceClass,ParameterValue=$db_instance_class \
            ParameterKey=EC2InstanceType,ParameterValue=$ec2_instance_type \
        --capabilities CAPABILITY_IAM

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}スタックの作成を開始しました。完了までに15-20分かかることがあります。${NC}"
        echo -e "ステータスを確認するには: $0 status"
    else
        echo -e "${RED}スタックの作成に失敗しました。${NC}"
        return 1
    fi
}

# スタックを更新
function update_stack {
    local db_password=""
    local use_previous_password=false
    local db_username=""
    local use_previous_username=false
    local master_db_name=""
    local use_previous_master_db_name=false
    local second_db_name=""
    local use_previous_second_db_name=false
    local db_instance_class=""
    local use_previous_db_instance_class=false
    local ec2_instance_type=""
    local use_previous_ec2_instance_type=false

    # パラメータの解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            --db-password)
                db_password="$2"
                use_previous_password=false
                shift 2
                ;;
            --use-previous-password)
                use_previous_password=true
                shift
                ;;
            --db-username)
                db_username="$2"
                use_previous_username=false
                shift 2
                ;;
            --use-previous-username)
                use_previous_username=true
                shift
                ;;
            --master-db-name)
                master_db_name="$2"
                use_previous_master_db_name=false
                shift 2
                ;;
            --use-previous-master-db-name)
                use_previous_master_db_name=true
                shift
                ;;
            --second-db-name)
                second_db_name="$2"
                use_previous_second_db_name=false
                shift 2
                ;;
            --use-previous-second-db-name)
                use_previous_second_db_name=true
                shift
                ;;
            --db-instance-class)
                db_instance_class="$2"
                use_previous_db_instance_class=false
                shift 2
                ;;
            --use-previous-db-instance-class)
                use_previous_db_instance_class=true
                shift
                ;;
            --ec2-instance-type)
                ec2_instance_type="$2"
                use_previous_ec2_instance_type=false
                shift 2
                ;;
            --use-previous-ec2-instance-type)
                use_previous_ec2_instance_type=true
                shift
                ;;
            *)
                echo -e "${RED}エラー: 不明なオプション: $1${NC}"
                return 1
                ;;
        esac
    done

    # スタックが存在するか確認
    if ! check_stack_exists; then
        echo -e "${RED}エラー: スタック '$STACK_NAME' が存在しません${NC}"
        return 1
    fi

    echo -e "${BLUE}CloudFormationスタックを更新しています...${NC}"

    # パラメータの構築
    local parameters=""

    if [ "$use_previous_password" = true ]; then
        parameters="$parameters ParameterKey=DBPassword,UsePreviousValue=true"
    elif [ -n "$db_password" ]; then
        parameters="$parameters ParameterKey=DBPassword,ParameterValue=$db_password"
    else
        echo -e "${YELLOW}警告: DBパスワードが指定されていません。--db-password または --use-previous-password を使用してください${NC}"
        parameters="$parameters ParameterKey=DBPassword,UsePreviousValue=true"
    fi

    if [ "$use_previous_username" = true ]; then
        parameters="$parameters ParameterKey=DBUsername,UsePreviousValue=true"
    elif [ -n "$db_username" ]; then
        parameters="$parameters ParameterKey=DBUsername,ParameterValue=$db_username"
    else
        parameters="$parameters ParameterKey=DBUsername,UsePreviousValue=true"
    fi

    if [ "$use_previous_master_db_name" = true ]; then
        parameters="$parameters ParameterKey=MasterDBName,UsePreviousValue=true"
    elif [ -n "$master_db_name" ]; then
        parameters="$parameters ParameterKey=MasterDBName,ParameterValue=$master_db_name"
    else
        parameters="$parameters ParameterKey=MasterDBName,UsePreviousValue=true"
    fi

    if [ "$use_previous_second_db_name" = true ]; then
        parameters="$parameters ParameterKey=SecondDBName,UsePreviousValue=true"
    elif [ -n "$second_db_name" ]; then
        parameters="$parameters ParameterKey=SecondDBName,ParameterValue=$second_db_name"
    else
        parameters="$parameters ParameterKey=SecondDBName,UsePreviousValue=true"
    fi

    if [ "$use_previous_db_instance_class" = true ]; then
        parameters="$parameters ParameterKey=DBInstanceClass,UsePreviousValue=true"
    elif [ -n "$db_instance_class" ]; then
        parameters="$parameters ParameterKey=DBInstanceClass,ParameterValue=$db_instance_class"
    else
        parameters="$parameters ParameterKey=DBInstanceClass,UsePreviousValue=true"
    fi

    if [ "$use_previous_ec2_instance_type" = true ]; then
        parameters="$parameters ParameterKey=EC2InstanceType,UsePreviousValue=true"
    elif [ -n "$ec2_instance_type" ]; then
        parameters="$parameters ParameterKey=EC2InstanceType,ParameterValue=$ec2_instance_type"
    else
        parameters="$parameters ParameterKey=EC2InstanceType,UsePreviousValue=true"
    fi

    parameters="$parameters ParameterKey=LatestAmiId,UsePreviousValue=true"

    # スタックの更新
    aws cloudformation update-stack \
        --stack-name $STACK_NAME \
        --template-body file://$TEMPLATE_FILE \
        --region $REGION \
        --parameters $parameters \
        --capabilities CAPABILITY_IAM

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}スタックの更新を開始しました。完了までに時間がかかることがあります。${NC}"
        echo -e "ステータスを確認するには: $0 status"
    else
        echo -e "${RED}スタックの更新に失敗しました。${NC}"
        return 1
    fi
}

# スタックを削除
function delete_stack {
    # スタックが存在するか確認
    if ! check_stack_exists; then
        echo -e "${RED}エラー: スタック '$STACK_NAME' が存在しません${NC}"
        return 1
    fi

    echo -e "${YELLOW}警告: スタック '$STACK_NAME' を削除します。この操作は元に戻せません。${NC}"
    read -p "続行しますか？ (y/n): " confirm

    if [ "$confirm" != "y" ]; then
        echo -e "${BLUE}操作をキャンセルしました${NC}"
        return 0
    fi

    echo -e "${BLUE}CloudFormationスタックを削除しています...${NC}"

    aws cloudformation delete-stack --stack-name $STACK_NAME --region $REGION

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}スタックの削除を開始しました。完了までに時間がかかることがあります。${NC}"
    else
        echo -e "${RED}スタックの削除に失敗しました。${NC}"
        return 1
    fi
}

# スタックのステータスを表示
function show_stack_status {
    # スタックが存在するか確認
    if ! check_stack_exists; then
        echo -e "${RED}エラー: スタック '$STACK_NAME' が存在しません${NC}"
        return 1
    fi

    echo -e "${BLUE}スタックのステータスを取得しています...${NC}"

    local status=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION \
        --query "Stacks[0].StackStatus" --output text)

    echo -e "スタック名: ${GREEN}$STACK_NAME${NC}"
    echo -e "ステータス: ${YELLOW}$status${NC}"

    # スタックイベントを表示
    echo -e "\n${BLUE}最近のスタックイベント:${NC}"
    aws cloudformation describe-stack-events --stack-name $STACK_NAME --region $REGION \
        --query "StackEvents[0:5].[Timestamp,LogicalResourceId,ResourceStatus,ResourceStatusReason]" \
        --output table
}

# スタックの出力値を表示
function show_stack_outputs {
    # スタックが存在するか確認
    if ! check_stack_exists; then
        echo -e "${RED}エラー: スタック '$STACK_NAME' が存在しません${NC}"
        return 1
    fi

    echo -e "${BLUE}スタックの出力値を取得しています...${NC}"

    aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION \
        --query "Stacks[0].Outputs[].[OutputKey,OutputValue,Description]" \
        --output table
}

# EC2インスタンスに接続
function connect_to_ec2 {
    # スタックが存在するか確認
    if ! check_stack_exists; then
        echo -e "${RED}エラー: スタック '$STACK_NAME' が存在しません${NC}"
        return 1
    fi

    echo -e "${BLUE}踏み台EC2インスタンスに接続しています...${NC}"

    local instance_id=$(get_stack_output "BastionInstanceId")

    if [ -z "$instance_id" ]; then
        echo -e "${RED}エラー: EC2インスタンスIDを取得できませんでした${NC}"
        return 1
    fi

    echo -e "インスタンスID: ${GREEN}$instance_id${NC}"
    echo -e "SSMセッションを開始しています..."

    aws ssm start-session --target $instance_id --region $REGION
}

# マスターDBへのポートフォワーディングを設定
function port_forward_master {
    local local_port=3306

    # パラメータの解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            --local-port)
                local_port="$2"
                shift 2
                ;;
            *)
                echo -e "${RED}エラー: 不明なオプション: $1${NC}"
                return 1
                ;;
        esac
    done

    # スタックが存在するか確認
    if ! check_stack_exists; then
        echo -e "${RED}エラー: スタック '$STACK_NAME' が存在しません${NC}"
        return 1
    fi

    echo -e "${BLUE}マスターDBへのポートフォワーディングを設定しています...${NC}"

    local instance_id=$(get_stack_output "BastionInstanceId")
    local db_endpoint=$(get_stack_output "MasterDBEndpoint")

    if [ -z "$instance_id" ] || [ -z "$db_endpoint" ]; then
        echo -e "${RED}エラー: 必要な情報を取得できませんでした${NC}"
        return 1
    fi

    echo -e "インスタンスID: ${GREEN}$instance_id${NC}"
    echo -e "DBエンドポイント: ${GREEN}$db_endpoint${NC}"
    echo -e "ローカルポート: ${GREEN}$local_port${NC}"
    echo -e "ポートフォワーディングを開始しています..."

    aws ssm start-session \
        --target $instance_id \
        --document-name AWS-StartPortForwardingSessionToRemoteHost \
        --parameters "{\"host\":[\"$db_endpoint\"],\"portNumber\":[\"3306\"], \"localPortNumber\":[\"$local_port\"]}" \
        --region $REGION
}

# セカンドDBへのポートフォワーディングを設定
function port_forward_second {
    local local_port=3307

    # パラメータの解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            --local-port)
                local_port="$2"
                shift 2
                ;;
            *)
                echo -e "${RED}エラー: 不明なオプション: $1${NC}"
                return 1
                ;;
        esac
    done

    # スタックが存在するか確認
    if ! check_stack_exists; then
        echo -e "${RED}エラー: スタック '$STACK_NAME' が存在しません${NC}"
        return 1
    fi

    echo -e "${BLUE}セカンドDBへのポートフォワーディングを設定しています...${NC}"

    local instance_id=$(get_stack_output "BastionInstanceId")
    local db_endpoint=$(get_stack_output "SecondDBEndpoint")

    if [ -z "$instance_id" ] || [ -z "$db_endpoint" ]; then
        echo -e "${RED}エラー: 必要な情報を取得できませんでした${NC}"
        return 1
    fi

    echo -e "インスタンスID: ${GREEN}$instance_id${NC}"
    echo -e "DBエンドポイント: ${GREEN}$db_endpoint${NC}"
    echo -e "ローカルポート: ${GREEN}$local_port${NC}"
    echo -e "ポートフォワーディングを開始しています..."

    aws ssm start-session \
        --target $instance_id \
        --document-name AWS-StartPortForwardingSessionToRemoteHost \
        --parameters "{\"host\":[\"$db_endpoint\"],\"portNumber\":[\"3306\"], \"localPortNumber\":[\"$local_port\"]}" \
        --region $REGION
}

# DMSレプリケーションスタックをデプロイ
function deploy_dms_stack {
    local db_password=""
    local db_username="admin"
    local source_db_name="world"

    # オプションの解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            --db-password)
                db_password="$2"
                shift 2
                ;;
            --db-username)
                db_username="$2"
                shift 2
                ;;
            --source-db)
                source_db_name="$2"
                shift 2
                ;;
            *)
                echo -e "${RED}エラー: 不明なオプション: $1${NC}"
                return 1
                ;;
        esac
    done

    # 必須パラメータのチェック
    if [ -z "$db_password" ]; then
        echo -e "${RED}エラー: --db-password は必須です${NC}"
        return 1
    fi

    # 基本スタックが存在するか確認
    if ! check_stack_exists; then
        echo -e "${RED}エラー: 基本スタック '$STACK_NAME' が存在しません。まず基本スタックをデプロイしてください。${NC}"
        return 1
    fi

    echo -e "${BLUE}DMSレプリケーションスタックをデプロイしています...${NC}"
    echo -e "${BLUE}ソースデータベース: ${source_db_name}${NC}"

    # CloudFormationスタックをデプロイ
    aws cloudformation deploy \
        --template-file $DMS_TEMPLATE_FILE \
        --stack-name $DMS_STACK_NAME \
        --parameter-overrides \
            ExistingStackName=$STACK_NAME \
            DBUsername=$db_username \
            DBPassword=$db_password \
            SourceDatabaseName=$source_db_name \
        --capabilities CAPABILITY_IAM \
        --region $REGION

    local result=$?
    if [ $result -eq 0 ]; then
        echo -e "${GREEN}DMSレプリケーションスタックのデプロイが完了しました${NC}"
        echo -e "${BLUE}次のステップ:${NC}"
        echo -e "1. ${YELLOW}./run.sh status-dms${NC} でDMSタスクのステータスを確認"
        echo -e "2. レプリケーションが完了したら: ${YELLOW}./run.sh verify-replication --master-port 13306 --second-port 13307${NC}"
    else
        echo -e "${RED}DMSレプリケーションスタックのデプロイに失敗しました${NC}"
    fi

    return $result
}

# DMSスタックのステータスを表示
function show_dms_status {
    if ! check_dms_stack_exists; then
        echo -e "${RED}エラー: DMSスタック '$DMS_STACK_NAME' が存在しません${NC}"
        return 1
    fi

    echo -e "${BLUE}DMSレプリケーションスタックのステータス:${NC}"
    aws cloudformation describe-stacks --stack-name $DMS_STACK_NAME --region $REGION \
        --query "Stacks[0].StackStatus" --output text

    echo -e "\n${BLUE}DMSレプリケーションタスクのステータス:${NC}"
    local task_arn=$(aws cloudformation describe-stacks --stack-name $DMS_STACK_NAME --region $REGION \
        --query "Stacks[0].Outputs[?OutputKey=='ReplicationTaskArn'].OutputValue" --output text)

    if [ -n "$task_arn" ]; then
        aws dms describe-replication-tasks --filters Name=replication-task-arn,Values=$task_arn \
            --query "ReplicationTasks[0].Status" --output text --region $REGION

        echo -e "\n${BLUE}レプリケーション統計:${NC}"
        aws dms describe-replication-tasks --filters Name=replication-task-arn,Values=$task_arn \
            --query "ReplicationTasks[0].ReplicationTaskStats" --output json --region $REGION
    else
        echo -e "${YELLOW}DMSレプリケーションタスクが見つかりません${NC}"
    fi
}

# DMSタスクを管理（開始、停止、再起動）
function manage_dms_task {
    local action=$1

    if ! check_dms_stack_exists; then
        echo -e "${RED}エラー: DMSスタック '$DMS_STACK_NAME' が存在しません${NC}"
        return 1
    fi

    local task_arn=$(aws cloudformation describe-stacks --stack-name $DMS_STACK_NAME --region $REGION \
        --query "Stacks[0].Outputs[?OutputKey=='ReplicationTaskArn'].OutputValue" --output text)

    if [ -z "$task_arn" ]; then
        echo -e "${RED}エラー: DMSレプリケーションタスクが見つかりません${NC}"
        return 1
    fi

    case $action in
        start)
            echo -e "${BLUE}DMSレプリケーションタスクを開始しています...${NC}"
            aws dms start-replication-task --replication-task-arn $task_arn \
                --start-replication-task-type start-replication --region $REGION
            ;;
        stop)
            echo -e "${BLUE}DMSレプリケーションタスクを停止しています...${NC}"
            aws dms stop-replication-task --replication-task-arn $task_arn --region $REGION
            ;;
        restart)
            echo -e "${BLUE}DMSレプリケーションタスクを再起動しています...${NC}"
            aws dms start-replication-task --replication-task-arn $task_arn \
                --start-replication-task-type reload-target --region $REGION
            ;;
        *)
            echo -e "${RED}エラー: 不明なアクション: $action${NC}"
            return 1
            ;;
    esac

    echo -e "${GREEN}コマンドが実行されました。タスクのステータスを確認するには './run.sh status-dms' を実行してください${NC}"
}

# ローカルからレプリケーションを検証
function verify_replication_local {
    local master_port=13306
    local second_port=13307

    # パラメータの解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            --master-port)
                master_port="$2"
                shift 2
                ;;
            --second-port)
                second_port="$2"
                shift 2
                ;;
            *)
                echo -e "${RED}エラー: 不明なオプション: $1${NC}"
                return 1
                ;;
        esac
    done

    # スタックが存在するか確認
    if ! check_stack_exists; then
        echo -e "${RED}エラー: スタック '$STACK_NAME' が存在しません${NC}"
        return 1
    fi

    # DMSスタックが存在するか確認
    if ! aws cloudformation describe-stacks --stack-name $DMS_STACK_NAME &>/dev/null; then
        echo -e "${RED}エラー: DMSスタック '$DMS_STACK_NAME' が存在しません${NC}"
        echo -e "${YELLOW}先に以下のコマンドを実行してDMSレプリケーションをデプロイしてください:${NC}"
        echo -e "  $0 deploy-dms --db-password <パスワード> --source-db world"
        return 1
    fi

    # ポートフォワーディングの確認
    echo -e "${BLUE}ポートフォワーディングの接続確認を行います...${NC}"
    local master_check=false
    local second_check=false

    # マスターDBへの接続確認
    if nc -z localhost $master_port 2>/dev/null; then
        echo -e "${GREEN}マスターDBへのポートフォワーディング (localhost:$master_port) が正常に機能しています${NC}"
        master_check=true
    else
        echo -e "${RED}マスターDBへのポートフォワーディングが機能していません${NC}"
        echo -e "${YELLOW}別のターミナルで以下のコマンドを実行してください:${NC}"
        echo -e "  $0 port-forward-master --local-port $master_port"
    fi

    # セカンドDBへの接続確認
    if nc -z localhost $second_port 2>/dev/null; then
        echo -e "${GREEN}セカンドDBへのポートフォワーディング (localhost:$second_port) が正常に機能しています${NC}"
        second_check=true
    else
        echo -e "${RED}セカンドDBへのポートフォワーディングが機能していません${NC}"
        echo -e "${YELLOW}別のターミナルで以下のコマンドを実行してください:${NC}"
        echo -e "  $0 port-forward-second --local-port $second_port"
    fi

    # 両方のポートフォワーディングが機能していない場合は終了
    if [ "$master_check" = false ] || [ "$second_check" = false ]; then
        echo -e "${RED}ポートフォワーディングの設定を確認してから再試行してください${NC}"
        return 1
    fi

    # 認証情報の入力
    read -p "データベースユーザー名: " DB_USERNAME
    read -sp "データベースパスワード: " DB_PASSWORD
    echo ""

    echo -e "${BLUE}レプリケーション状態を検証中...${NC}"

    # 1. レプリケーション対象データベース（world）の検証
    echo -e "${BLUE}=== レプリケーション対象データベース (world) の検証 ===${NC}"

    # セカンドDBのテーブル数を取得
    echo -e "${BLUE}セカンドDB (ソース) のテーブル数を取得中...${NC}"
    local SECOND_DB_TABLES=$(mysql -h localhost -P $second_port -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'world';" -s)
    if [ $? -ne 0 ]; then
        echo -e "${RED}セカンドDBへの接続に失敗しました${NC}"
        return 1
    fi

    # マスターDBのテーブル数を取得
    echo -e "${BLUE}マスターDB (ターゲット) のテーブル数を取得中...${NC}"
    local MASTER_DB_TABLES=$(mysql -h localhost -P $master_port -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'world';" -s)
    if [ $? -ne 0 ]; then
        echo -e "${RED}マスターDBへの接続に失敗しました${NC}"
        return 1
    fi

    echo -e "${BLUE}セカンドDB (ソース) のテーブル数: ${NC}$SECOND_DB_TABLES"
    echo -e "${BLUE}マスターDB (ターゲット) のテーブル数: ${NC}$MASTER_DB_TABLES"

    if [ "$SECOND_DB_TABLES" -eq "$MASTER_DB_TABLES" ]; then
        echo -e "${GREEN}✅ テーブル数が一致しています。レプリケーションが正常に機能しています。${NC}"
    else
        echo -e "${RED}❌ テーブル数が一致していません。レプリケーションに問題がある可能性があります。${NC}"
    fi

    # 各テーブルの行数を比較
    echo ""
    echo -e "${BLUE}各テーブルの行数を比較中...${NC}"

    # テーブル一覧を取得
    local TABLES=$(mysql -h localhost -P $second_port -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP -e "SHOW TABLES FROM world;" -s)
    if [ $? -ne 0 ]; then
        echo -e "${RED}テーブル一覧の取得に失敗しました${NC}"
        return 1
    fi

    # 各テーブルの行数を比較
    local all_match=true
    for TABLE in $TABLES; do
        local SECOND_DB_ROWS=$(mysql -h localhost -P $second_port -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP -e "SELECT COUNT(*) FROM world.$TABLE;" -s)
        local MASTER_DB_ROWS=$(mysql -h localhost -P $master_port -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP -e "SELECT COUNT(*) FROM world.$TABLE;" -s)

        echo -e "${BLUE}テーブル: ${NC}$TABLE"
        echo -e "  ${BLUE}セカンドDB (ソース) の行数: ${NC}$SECOND_DB_ROWS"
        echo -e "  ${BLUE}マスターDB (ターゲット) の行数: ${NC}$MASTER_DB_ROWS"

        if [ "$SECOND_DB_ROWS" -eq "$MASTER_DB_ROWS" ]; then
            echo -e "  ${GREEN}✅ 行数が一致しています。${NC}"
        else
            echo -e "  ${RED}❌ 行数が一致していません。${NC}"
            all_match=false
        fi
        echo ""
    done

    # 2. レプリケーション非対象データベース（worldnonrepl）の検証
    echo -e "${BLUE}=== レプリケーション非対象データベース (worldnonrepl) の検証 ===${NC}"

    # マスターDBにworldnonreplデータベースが存在するか確認
    local NONREPL_DB_EXISTS=$(mysql -h localhost -P $master_port -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = 'worldnonrepl';" -s)

    if [ "$NONREPL_DB_EXISTS" -eq "0" ]; then
        echo -e "${GREEN}✅ worldnonreplデータベースはマスターDBに存在しません。レプリケーション対象外の設定が正常に機能しています。${NC}"
    else
        echo -e "${RED}❌ worldnonreplデータベースがマスターDBに存在します。レプリケーション対象外の設定に問題がある可能性があります。${NC}"
        all_match=false

        # worldnonreplデータベースのテーブル数を確認
        local NONREPL_TABLES=$(mysql -h localhost -P $master_port -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'worldnonrepl';" -s)
        echo -e "${BLUE}マスターDBのworldnonreplデータベースのテーブル数: ${NC}$NONREPL_TABLES"
    fi

    # 3. 継続的なレプリケーションをテスト
    echo -e "${BLUE}=== 継続的なレプリケーションをテスト ===${NC}"
    echo -e "${BLUE}セカンドDB (ソース) に新しい行を挿入します...${NC}"

    # 現在の時刻を使用してユニークな値を作成
    local TIMESTAMP=$(date +%Y%m%d%H%M%S)
    local CITY_NAME="TestCity$TIMESTAMP"

    # セカンドDBに新しい行を挿入
    mysql -h localhost -P $second_port -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP -e "INSERT INTO world.city (Name, CountryCode, District, Population) VALUES ('$CITY_NAME', 'JPN', 'Test District', 12345);"
    if [ $? -ne 0 ]; then
        echo -e "${RED}新しい行の挿入に失敗しました${NC}"
        return 1
    fi

    # 少し待機してレプリケーションが行われるのを待つ
    echo -e "${BLUE}レプリケーションが完了するまで10秒待機中...${NC}"
    sleep 10

    # マスターDBで挿入された行を確認
    local MASTER_DB_CHECK=$(mysql -h localhost -P $master_port -u $DB_USERNAME -p$DB_PASSWORD --protocol=TCP -e "SELECT COUNT(*) FROM world.city WHERE Name = '$CITY_NAME';" -s)
    if [ $? -ne 0 ]; then
        echo -e "${RED}マスターDBでの確認に失敗しました${NC}"
        return 1
    fi

    if [ "$MASTER_DB_CHECK" -eq "1" ]; then
        echo -e "${GREEN}✅ 継続的なレプリケーションが正常に機能しています。挿入された行がマスターDBに複製されました。${NC}"
    else
        echo -e "${RED}❌ 継続的なレプリケーションに問題があります。挿入された行がマスターDBに複製されていません。${NC}"
        all_match=false
    fi

    echo ""
    if [ "$all_match" = true ]; then
        echo -e "${GREEN}レプリケーション検証が完了しました。すべてのテストに合格しました！${NC}"
        echo -e "${GREEN}・world データベースは正常にレプリケーションされています${NC}"
        echo -e "${GREEN}・worldnonrepl データベースはレプリケーションされていません（期待通り）${NC}"
    else
        echo -e "${YELLOW}レプリケーション検証が完了しましたが、一部のテストに失敗しました。${NC}"
        echo -e "${YELLOW}DMSタスクのステータスを確認してください: ${NC}./run.sh status-dms"
    fi
}

# DMSスタックを削除
function delete_dms_stack {
    # DMSスタックが存在するか確認
    if ! aws cloudformation describe-stacks --stack-name $DMS_STACK_NAME &>/dev/null; then
        echo -e "${RED}エラー: DMSスタック '$DMS_STACK_NAME' が存在しません${NC}"
        return 1
    fi

    echo -e "${BLUE}DMSレプリケーションスタックを削除します...${NC}"
    echo -e "${YELLOW}警告: この操作は取り消せません。DMSレプリケーションリソースがすべて削除されます。${NC}"
    read -p "続行しますか？ (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        echo -e "${BLUE}操作をキャンセルしました${NC}"
        return 0
    fi

    # DMSスタックを削除
    aws cloudformation delete-stack --stack-name $DMS_STACK_NAME

    echo -e "${BLUE}DMSレプリケーションスタックの削除を開始しました${NC}"
    echo -e "${BLUE}削除の進行状況は ${YELLOW}./run.sh status-dms${NC} で確認できます${NC}"
}

# DMSに必要なIAMロールをデプロイ
function deploy_iam_stack {
    echo -e "${BLUE}DMSに必要なIAMロールをデプロイしています...${NC}"

    # 既存のIAMロールを確認
    local vpc_role_exists=$(aws iam list-roles --query "Roles[?RoleName=='dms-vpc-role'].RoleName" --output text)
    local logs_role_exists=$(aws iam list-roles --query "Roles[?RoleName=='dms-cloudwatch-logs-role'].RoleName" --output text)

    if [[ -n "$vpc_role_exists" && -n "$logs_role_exists" ]]; then
        echo -e "${YELLOW}必要なIAMロール（dms-vpc-role, dms-cloudwatch-logs-role）は既に存在します${NC}"
        echo -e "${BLUE}既存のロールを使用します${NC}"

        # 既存のロールのARNを表示
        local vpc_role_arn=$(aws iam get-role --role-name dms-vpc-role --query "Role.Arn" --output text)
        local logs_role_arn=$(aws iam get-role --role-name dms-cloudwatch-logs-role --query "Role.Arn" --output text)

        echo -e "${BLUE}DMS VPC ロールARN:${NC} $vpc_role_arn"
        echo -e "${BLUE}DMS CloudWatch Logs ロールARN:${NC} $logs_role_arn"

        echo -e "${BLUE}次のステップ:${NC}"
        echo -e "1. ${YELLOW}./run.sh deploy-dms --db-password <パスワード> --source-db world${NC} でDMSレプリケーションをデプロイ"

        return 0
    fi

    # 一部のロールだけが存在する場合は警告
    if [[ -n "$vpc_role_exists" || -n "$logs_role_exists" ]]; then
        echo -e "${YELLOW}警告: 一部のDMS IAMロールは既に存在しますが、すべてが揃っていません${NC}"
        echo -e "${YELLOW}既存のロールを削除してから再デプロイすることをお勧めします${NC}"
        echo -e "${YELLOW}続行しますか？ (y/n)${NC}"
        read -r confirm
        if [[ $confirm != [yY] ]]; then
            echo -e "${BLUE}デプロイをキャンセルしました${NC}"
            return 0
        fi
    fi

    # CloudFormationスタックをデプロイ
    aws cloudformation deploy \
        --template-file $IAM_TEMPLATE_FILE \
        --stack-name $IAM_STACK_NAME \
        --capabilities CAPABILITY_NAMED_IAM \
        --region $REGION

    local result=$?
    if [ $result -eq 0 ]; then
        echo -e "${GREEN}DMSに必要なIAMロールのデプロイが完了しました${NC}"
        echo -e "${BLUE}次のステップ:${NC}"
        echo -e "1. ${YELLOW}./run.sh deploy-dms --db-password <パスワード> --source-db world${NC} でDMSレプリケーションをデプロイ"
    else
        echo -e "${RED}DMSに必要なIAMロールのデプロイに失敗しました${NC}"
        echo -e "${YELLOW}既存のIAMロールが原因の場合は、以下のコマンドで確認できます:${NC}"
        echo -e "${YELLOW}aws iam list-roles | grep -E \"dms-vpc-role|dms-cloudwatch-logs-role\"${NC}"
    fi

    return $result
}

# DMSのIAMロールスタックを削除
function delete_iam_stack {
    # スタックが存在するか確認
    if ! aws cloudformation describe-stacks --stack-name $IAM_STACK_NAME --region $REGION &> /dev/null; then
        echo -e "${YELLOW}IAMロールスタック '$IAM_STACK_NAME' は存在しません${NC}"
        return 0
    fi

    echo -e "${YELLOW}DMSのIAMロールスタックを削除します。よろしいですか？ (y/n)${NC}"
    read -r confirm
    if [[ $confirm != [yY] ]]; then
        echo -e "${BLUE}削除をキャンセルしました${NC}"
        return 0
    fi

    echo -e "${BLUE}DMSのIAMロールスタックを削除しています...${NC}"
    aws cloudformation delete-stack --stack-name $IAM_STACK_NAME --region $REGION

    echo -e "${BLUE}DMSのIAMロールスタックの削除を開始しました${NC}"
    echo -e "${BLUE}削除の進行状況は ${YELLOW}./run.sh status-iam${NC} で確認できます${NC}"
}

# DMSのIAMロールスタックのステータスを表示
function show_iam_status {
    # スタックが存在するか確認
    if ! aws cloudformation describe-stacks --stack-name $IAM_STACK_NAME --region $REGION &> /dev/null; then
        echo -e "${YELLOW}IAMロールスタック '$IAM_STACK_NAME' は存在しません${NC}"

        # 既存のIAMロールを確認
        local vpc_role_exists=$(aws iam list-roles --query "Roles[?RoleName=='dms-vpc-role'].RoleName" --output text)
        local logs_role_exists=$(aws iam list-roles --query "Roles[?RoleName=='dms-cloudwatch-logs-role'].RoleName" --output text)

        if [[ -n "$vpc_role_exists" && -n "$logs_role_exists" ]]; then
            echo -e "${YELLOW}ただし、必要なIAMロール（dms-vpc-role, dms-cloudwatch-logs-role）は既に存在します${NC}"

            # 既存のロールのARNを表示
            local vpc_role_arn=$(aws iam get-role --role-name dms-vpc-role --query "Role.Arn" --output text)
            local logs_role_arn=$(aws iam get-role --role-name dms-cloudwatch-logs-role --query "Role.Arn" --output text)

            echo -e "${BLUE}DMS VPC ロールARN:${NC} $vpc_role_arn"
            echo -e "${BLUE}DMS CloudWatch Logs ロールARN:${NC} $logs_role_arn"
        else
            echo -e "${YELLOW}必要なIAMロールも存在しません。${YELLOW}./run.sh deploy-iam${NC} を実行してデプロイしてください${NC}"
        fi

        return 0
    fi

    echo -e "${BLUE}DMSのIAMロールスタックのステータスを確認しています...${NC}"
    local stack_status=$(aws cloudformation describe-stacks --stack-name $IAM_STACK_NAME --region $REGION --query "Stacks[0].StackStatus" --output text)

    echo -e "${BLUE}スタック名:${NC} $IAM_STACK_NAME"
    echo -e "${BLUE}ステータス:${NC} $stack_status"

    if [[ $stack_status == "CREATE_COMPLETE" || $stack_status == "UPDATE_COMPLETE" ]]; then
        echo -e "${GREEN}IAMロールスタックは正常にデプロイされています${NC}"

        # IAMロールのARNを取得して表示
        local vpc_role_arn=$(aws cloudformation describe-stacks --stack-name $IAM_STACK_NAME --region $REGION --query "Stacks[0].Outputs[?OutputKey=='DMSVPCRoleARN'].OutputValue" --output text)
        local logs_role_arn=$(aws cloudformation describe-stacks --stack-name $IAM_STACK_NAME --region $REGION --query "Stacks[0].Outputs[?OutputKey=='DMSCloudWatchLogsRoleARN'].OutputValue" --output text)

        echo -e "${BLUE}DMS VPC ロールARN:${NC} $vpc_role_arn"
        echo -e "${BLUE}DMS CloudWatch Logs ロールARN:${NC} $logs_role_arn"
    elif [[ $stack_status == "ROLLBACK_COMPLETE" ]]; then
        echo -e "${YELLOW}IAMロールスタックのデプロイに失敗しました${NC}"

        # 既存のIAMロールを確認
        local vpc_role_exists=$(aws iam list-roles --query "Roles[?RoleName=='dms-vpc-role'].RoleName" --output text)
        local logs_role_exists=$(aws iam list-roles --query "Roles[?RoleName=='dms-cloudwatch-logs-role'].RoleName" --output text)

        if [[ -n "$vpc_role_exists" && -n "$logs_role_exists" ]]; then
            echo -e "${YELLOW}ただし、必要なIAMロール（dms-vpc-role, dms-cloudwatch-logs-role）は既に存在します${NC}"

            # 既存のロールのARNを表示
            local vpc_role_arn=$(aws iam get-role --role-name dms-vpc-role --query "Role.Arn" --output text)
            local logs_role_arn=$(aws iam get-role --role-name dms-cloudwatch-logs-role --query "Role.Arn" --output text)

            echo -e "${BLUE}DMS VPC ロールARN:${NC} $vpc_role_arn"
            echo -e "${BLUE}DMS CloudWatch Logs ロールARN:${NC} $logs_role_arn"

            echo -e "${YELLOW}スタックを削除するには ${YELLOW}./run.sh delete-iam${NC} を実行してください${NC}"
        else
            echo -e "${RED}必要なIAMロールも存在しません。スタックを削除してから再デプロイしてください${NC}"
            echo -e "${YELLOW}スタックを削除するには ${YELLOW}./run.sh delete-iam${NC} を実行してください${NC}"
        fi
    else
        echo -e "${YELLOW}IAMロールスタックは現在 $stack_status 状態です${NC}"
    fi
}

# メイン処理
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

command=$1
shift

case $command in
    deploy)
        deploy_stack "$@"
        ;;
    update)
        update_stack "$@"
        ;;
    delete)
        delete_stack
        ;;
    status)
        show_stack_status
        ;;
    outputs)
        show_stack_outputs
        ;;
    connect-ec2)
        connect_to_ec2
        ;;
    port-forward-master)
        port_forward_master "$@"
        ;;
    port-forward-second)
        port_forward_second "$@"
        ;;
    prepare-sample-data)
        prepare_sample_data
        ;;
    import-sample-db)
        import_sample_db_local "$@"
        ;;
    verify-replication)
        verify_replication_local "$@"
        ;;
    deploy-dms)
        deploy_dms_stack "$@"
        ;;
    status-dms)
        show_dms_status
        ;;
    start-dms)
        manage_dms_task "start"
        ;;
    stop-dms)
        manage_dms_task "stop"
        ;;
    restart-dms)
        manage_dms_task "restart"
        ;;
    delete-dms)
        delete_dms_stack
        ;;
    deploy-iam)
        deploy_iam_stack
        ;;
    delete-iam)
        delete_iam_stack
        ;;
    status-iam)
        show_iam_status
        ;;
    help)
        show_help
        ;;
    *)
        echo -e "${RED}エラー: 不明なコマンド: $command${NC}"
        show_help
        exit 1
        ;;
esac

exit $?