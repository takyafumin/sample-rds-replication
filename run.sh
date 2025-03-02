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
    echo -e "  ${GREEN}help${NC}                - このヘルプメッセージを表示します"
    echo ""
    echo -e "${YELLOW}例:${NC}"
    echo -e "  $0 ${GREEN}deploy${NC} --db-password MySecurePassword123"
    echo -e "  $0 ${GREEN}connect-ec2${NC}"
    echo -e "  $0 ${GREEN}port-forward-master${NC} --local-port 13306"
    echo ""
}

# スタックの存在確認
function check_stack_exists {
    aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION &> /dev/null
    return $?
}

# スタックの出力値を取得
function get_stack_output {
    local output_key=$1
    aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" --output text
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

# メイン処理
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

# コマンドの解析
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