#!/bin/bash
# DMSタスク管理スクリプト

# エラーが発生したら終了
set -e

# 設定
DMS_STACK_NAME=$1
ACTION=$2

if [ -z "$DMS_STACK_NAME" ] || [ -z "$ACTION" ]; then
  echo "使用方法: $0 <DMSスタック名> <start|stop|status|restart>"
  exit 1
fi

# CloudFormationスタックからDMSタスクARNを取得
echo "CloudFormationスタックから情報を取得中..."
DMS_TASK_ARN=$(aws cloudformation describe-stacks --stack-name $DMS_STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='DMSTaskARN'].OutputValue" --output text)

if [ -z "$DMS_TASK_ARN" ]; then
  echo "エラー: DMSタスクARNが見つかりません。スタック名が正しいか確認してください。"
  exit 1
fi

echo "DMSタスクARN: $DMS_TASK_ARN"

# タスクの現在のステータスを取得
get_task_status() {
  aws dms describe-replication-tasks --filters Name=replication-task-arn,Values=$DMS_TASK_ARN --query "ReplicationTasks[0].Status" --output text
}

# タスクの詳細情報を表示
show_task_details() {
  echo "タスクの詳細情報:"
  aws dms describe-replication-tasks --filters Name=replication-task-arn,Values=$DMS_TASK_ARN --query "ReplicationTasks[0].{Status:Status,MigrationType:MigrationType,StopReason:StopReason,ReplicationInstanceArn:ReplicationInstanceArn,SourceEndpointArn:SourceEndpointArn,TargetEndpointArn:TargetEndpointArn,CreationDate:CreationDate}" --output table
}

# アクションに応じた処理
case $ACTION in
  start)
    CURRENT_STATUS=$(get_task_status)
    if [ "$CURRENT_STATUS" == "stopped" ]; then
      echo "DMSタスクを開始中..."
      aws dms start-replication-task --replication-task-arn $DMS_TASK_ARN --start-replication-task-type resume-processing
      echo "タスクの開始をリクエストしました。ステータスを確認するには: $0 $DMS_STACK_NAME status"
    else
      echo "タスクを開始できません。現在のステータス: $CURRENT_STATUS"
      echo "タスクが停止状態の場合のみ開始できます。"
    fi
    ;;

  stop)
    echo "DMSタスクを停止中..."
    aws dms stop-replication-task --replication-task-arn $DMS_TASK_ARN
    echo "タスクの停止をリクエストしました。ステータスを確認するには: $0 $DMS_STACK_NAME status"
    ;;

  restart)
    echo "DMSタスクを再起動中..."
    # まずタスクを停止
    aws dms stop-replication-task --replication-task-arn $DMS_TASK_ARN

    # タスクが停止するまで待機
    echo "タスクが停止するまで待機中..."
    while true; do
      STATUS=$(get_task_status)
      if [ "$STATUS" == "stopped" ]; then
        break
      fi
      echo "現在のステータス: $STATUS - 待機中..."
      sleep 10
    done

    # タスクを再開
    echo "タスクを再開中..."
    aws dms start-replication-task --replication-task-arn $DMS_TASK_ARN --start-replication-task-type resume-processing
    echo "タスクの再起動をリクエストしました。ステータスを確認するには: $0 $DMS_STACK_NAME status"
    ;;

  status)
    STATUS=$(get_task_status)
    echo "現在のタスクステータス: $STATUS"
    show_task_details

    # タスク統計情報を表示
    echo ""
    echo "タスク統計情報:"
    aws dms describe-table-statistics --replication-task-arn $DMS_TASK_ARN --output table
    ;;

  *)
    echo "無効なアクション: $ACTION"
    echo "使用可能なアクション: start, stop, status, restart"
    exit 1
    ;;
esac