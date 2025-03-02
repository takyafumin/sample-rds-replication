# デプロイガイド

このガイドでは、AWS DMSを使用したAurora MySQL間のレプリケーション環境を構築する手順を詳しく説明します。

## 前提条件

- AWS CLIがインストールされていること
- AWS認証情報が設定されていること
- CloudFormationスタックを作成するための適切なIAM権限があること
- SSMセッションマネージャーを使用するための権限があること

## デプロイ手順

### ステップ1: 基本的なAurora MySQL環境をデプロイ

まず、2つのAurora MySQLクラスターと踏み台サーバーを含む基本的な環境をデプロイします。

```bash
aws cloudformation deploy \
  --template-file rds-replication.yaml \
  --stack-name aurora-mysql-env \
  --parameter-overrides \
    DBUsername=admin \
    DBPassword=YourStrongPassword \
    MasterDBName=hogedb \
    SecondDBName=fugadb \
  --capabilities CAPABILITY_IAM
```

このコマンドは以下のリソースをデプロイします：
- VPCとサブネット
- 2つのAurora MySQLクラスター（マスターDBとセカンドDB）
- 踏み台サーバー用のEC2インスタンス
- 必要なセキュリティグループとIAMロール

デプロイには約15〜20分かかります。

### ステップ2: サンプルデータベースをインポート

次に、踏み台サーバーにSSM経由で接続し、サンプルデータベースをインポートします。

1. 踏み台サーバーに接続：

```bash
aws ssm start-session --target $(aws cloudformation describe-stacks --stack-name aurora-mysql-env --query "Stacks[0].Outputs[?OutputKey=='BastionInstanceId'].OutputValue" --output text)
```

2. 踏み台サーバー上でスクリプトをダウンロードまたはコピー：

```bash
# スクリプトがすでにサーバー上にある場合は、実行権限を付与
chmod +x import_sample_db.sh
```

3. サンプルデータベースをインポート：

```bash
./import_sample_db.sh aurora-mysql-env
```

このスクリプトは以下の処理を行います：
- WorldデータベースとEmployeesデータベースをダウンロード
- セカンドDBにこれらのデータベースをインポート
- マスターDBに空のWorldデータベースを作成

### ステップ3: DMSレプリケーションをデプロイ

サンプルデータベースのインポートが完了したら、DMSレプリケーションをデプロイします。

```bash
aws cloudformation deploy \
  --template-file dms-replication.yaml \
  --stack-name dms-replication \
  --parameter-overrides \
    ExistingStackName=aurora-mysql-env \
    DBUsername=admin \
    DBPassword=YourStrongPassword \
    SourceDatabaseName=world \
  --capabilities CAPABILITY_IAM
```

このコマンドは以下のリソースをデプロイします：
- DMSレプリケーションインスタンス
- DMSソースエンドポイント（セカンドDBを指す）
- DMSターゲットエンドポイント（マスターDBを指す）
- DMSレプリケーションタスク
- 必要なIAMロールとセキュリティグループ

デプロイには約10〜15分かかります。

### ステップ4: レプリケーションを検証

DMSレプリケーションのデプロイが完了したら、レプリケーションが正常に機能しているかを検証します。

1. 踏み台サーバーに接続（まだ接続していない場合）：

```bash
aws ssm start-session --target $(aws cloudformation describe-stacks --stack-name aurora-mysql-env --query "Stacks[0].Outputs[?OutputKey=='BastionInstanceId'].OutputValue" --output text)
```

2. レプリケーションを検証：

```bash
chmod +x verify_replication.sh
./verify_replication.sh aurora-mysql-env
```

このスクリプトは以下の検証を行います：
- ソースとターゲットのデータベース間でテーブル数を比較
- 各テーブルの行数を比較
- 新しい行を挿入して継続的なレプリケーションをテスト

### ステップ5: DMSタスクの管理（必要に応じて）

DMSタスクを管理するには、以下のコマンドを使用します：

```bash
# タスクのステータスを確認
./manage_dms_task.sh dms-replication status

# タスクを停止
./manage_dms_task.sh dms-replication stop

# タスクを開始
./manage_dms_task.sh dms-replication start

# タスクを再起動
./manage_dms_task.sh dms-replication restart
```

## トラブルシューティング

### 一般的な問題

1. **接続エラー**: EC2インスタンスがRDSエンドポイントに到達できることを確認してください。セキュリティグループの設定を確認します。

2. **権限エラー**: AWS CLIの認証情報と、SSMセッションマネージャーを使用するための適切なIAM権限があることを確認してください。

3. **レプリケーションエラー**: DMSタスクのステータスとログを確認してください。バイナリログが有効になっていることを確認します。

### DMSタスクのログ確認

DMSタスクのログを確認するには、以下のコマンドを使用します：

```bash
aws dms describe-replication-tasks --filters Name=replication-task-arn,Values=<タスクARN> --query "ReplicationTasks[0].ReplicationTaskStats"
```

## クリーンアップ

環境を削除するには、以下の順序でスタックを削除します：

```bash
# 1. DMSレプリケーションスタックを削除
aws cloudformation delete-stack --stack-name dms-replication

# 2. Aurora MySQL環境スタックを削除
aws cloudformation delete-stack --stack-name aurora-mysql-env
```

スタックの削除には約10〜15分かかります。