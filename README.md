# RDSレプリケーション検証環境

## 概要

このプロジェクトはAWS RDSインスタンス間のレプリケーション検証環境を構築するためのCloudFormationテンプレートを提供します。

## 構成

- VPC、サブネット、セキュリティグループなどのネットワークリソース
- 2つのRDSインスタンス（MySQL 8.0.28）
  - マスターDB: `hogedb`
  - セカンドDB: `fugadb`
- SSM接続可能な踏み台EC2インスタンス
  - プライベートサブネットに配置
  - MySQLクライアントがプリインストール済み

## 前提条件

- AWS CLIがインストールされていること
- AWS認証情報が設定されていること
- CloudFormationスタックを作成するための適切なIAM権限があること
- SSMセッションマネージャーを使用するための権限があること

## 使い方

### CloudFormationスタックのデプロイ

以下のAWS CLIコマンドを使用してCloudFormationスタックをデプロイします：

```bash
aws cloudformation create-stack \
  --stack-name rds-replication-stack \
  --template-body file://rds-replication.yaml \
  --parameters ParameterKey=DBPassword,ParameterValue=YOUR_PASSWORD_HERE \
  --capabilities CAPABILITY_IAM
```

パラメータの説明：
- `--stack-name`: スタックの名前を指定します
- `--template-body`: テンプレートファイルのパスを指定します
- `--parameters`: テンプレートのパラメータを指定します（少なくともDBPasswordは必須）
- `--capabilities`: 必要な機能を指定します（IAMリソース作成のため必須）

### CloudFormationスタックの更新

テンプレートを変更した後、以下のコマンドでスタックを更新できます：

```bash
aws cloudformation update-stack \
  --stack-name rds-replication-stack \
  --template-body file://rds-replication.yaml \
  --parameters ParameterKey=DBPassword,ParameterValue=YOUR_PASSWORD_HERE \
  --capabilities CAPABILITY_IAM
```

既存のパラメータ値を再利用する場合（新しく追加されたパラメータには値を指定）：

```bash
aws cloudformation update-stack \
  --stack-name rds-replication-stack \
  --template-body file://rds-replication.yaml \
  --parameters ParameterKey=DBPassword,UsePreviousValue=true \
               ParameterKey=MasterDBName,UsePreviousValue=true \
               ParameterKey=SecondDBName,UsePreviousValue=true \
               ParameterKey=DBInstanceClass,UsePreviousValue=true \
               ParameterKey=DBUsername,UsePreviousValue=true \
               ParameterKey=EC2InstanceType,ParameterValue=t3.micro \
               ParameterKey=LatestAmiId,ParameterValue=/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
  --capabilities CAPABILITY_IAM
```

注意: 新しく追加されたパラメータ（EC2InstanceTypeやLatestAmiIdなど）には`UsePreviousValue=true`を指定できません。これらには明示的に値を指定する必要があります。

変更セットを使用した更新（推奨）：

```bash
# 変更セットの作成
aws cloudformation create-change-set \
  --stack-name rds-replication-stack \
  --change-set-name update-rds-replication \
  --template-body file://rds-replication.yaml \
  --parameters ParameterKey=DBPassword,ParameterValue=YOUR_PASSWORD_HERE \
               ParameterKey=MasterDBName,UsePreviousValue=true \
               ParameterKey=SecondDBName,UsePreviousValue=true \
               ParameterKey=DBInstanceClass,UsePreviousValue=true \
               ParameterKey=DBUsername,UsePreviousValue=true \
               ParameterKey=EC2InstanceType,ParameterValue=t3.micro \
               ParameterKey=LatestAmiId,ParameterValue=/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
  --capabilities CAPABILITY_IAM

# 変更セットの内容確認
aws cloudformation describe-change-set \
  --stack-name rds-replication-stack \
  --change-set-name update-rds-replication

# 変更セットの実行
aws cloudformation execute-change-set \
  --stack-name rds-replication-stack \
  --change-set-name update-rds-replication
```

注意事項：
- 一部のリソース変更は置き換えが必要となり、ダウンタイムが発生する可能性があります
- 更新前にテンプレートの変更内容を十分に確認してください
- 重要なデータがある場合は、事前にバックアップを取得してください

### スタックの進行状況の確認

```bash
aws cloudformation describe-stacks --stack-name rds-replication-stack
```

### スタックの出力の取得

デプロイが完了したら、以下のコマンドでRDSエンドポイントなどの出力値を取得できます：

```bash
aws cloudformation describe-stacks \
  --stack-name rds-replication-stack \
  --query "Stacks[0].Outputs"
```

### EC2踏み台サーバーへの接続

SSMセッションマネージャーを使用して踏み台サーバーに接続します：

```bash
# スタック出力から取得したコマンドを使用
aws ssm start-session --target i-xxxxxxxxxxxxxxxxx
```

### RDSへの接続

踏み台サーバーに接続後、以下のコマンドでRDSインスタンスに接続できます：

```bash
# マスターDBへの接続
mysql -h <マスターDBエンドポイント> -u admin -p hogedb

# セカンドDBへの接続
mysql -h <セカンドDBエンドポイント> -u admin -p fugadb
```

### スタックの削除

検証が終了したら、以下のコマンドでスタックを削除できます：

```bash
aws cloudformation delete-stack --stack-name rds-replication-stack
```

## パラメータ

テンプレートでは以下のパラメータをカスタマイズできます：

- `MasterDBName`: マスターデータベース名（デフォルト: hogedb）
- `SecondDBName`: 2つ目のRDSインスタンス上のデータベース名（デフォルト: fugadb）
- `DBInstanceClass`: DBインスタンスクラス（デフォルト: db.t3.medium）
- `DBUsername`: データベース管理者ユーザー名（デフォルト: admin）
- `DBPassword`: データベース管理者パスワード（必須）
- `EC2InstanceType`: 踏み台サーバーのインスタンスタイプ（デフォルト: t3.micro）
- `LatestAmiId`: 踏み台サーバーのAMI ID（デフォルト: 最新のAmazon Linux 2）

## 注意事項

- このテンプレートはテスト・検証用途を想定しています
- 本番環境での使用には適切なセキュリティ設定を追加してください
- RDSインスタンスとEC2インスタンスには料金が発生します。使用後は忘れずに削除してください
- EC2インスタンスはプライベートサブネットに配置されており、インターネットアクセスはありません
- SSM接続のためのVPCエンドポイントが設定されています

## ライセンス

## 連絡先