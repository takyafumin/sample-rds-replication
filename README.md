# RDSレプリケーション検証環境

## 概要

このプロジェクトはAWS RDSインスタンス間のレプリケーション検証環境を構築するためのCloudFormationテンプレートを提供します。

## 構成

- VPC、サブネット、セキュリティグループなどのネットワークリソース
- 2つのRDSインスタンス（MySQL 8.0.28）
  - マスターDB: `hogedb`
  - セカンドDB: `fugadb`

## 前提条件

- AWS CLIがインストールされていること
- AWS認証情報が設定されていること
- CloudFormationスタックを作成するための適切なIAM権限があること

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
- `--capabilities`: 必要な機能を指定します

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

### スタックの削除

検証が終了したら、以下のコマンドでスタックを削除できます：

```bash
aws cloudformation delete-stack --stack-name rds-replication-stack
```

## パラメータ

テンプレートでは以下のパラメータをカスタマイズできます：

- `MasterDBName`: マスターデータベース名（デフォルト: hogedb）
- `SecondDBName`: 2つ目のRDSインスタンス上のデータベース名（デフォルト: fugadb）
- `DBInstanceClass`: DBインスタンスクラス（デフォルト: db.t3.micro）
- `DBUsername`: データベース管理者ユーザー名（デフォルト: admin）
- `DBPassword`: データベース管理者パスワード（必須）

## 注意事項

- このテンプレートはテスト・検証用途を想定しています
- 本番環境での使用には適切なセキュリティ設定を追加してください
- RDSインスタンスには料金が発生します。使用後は忘れずに削除してください

## ライセンス

## 連絡先