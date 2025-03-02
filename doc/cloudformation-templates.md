# CloudFormationテンプレート

このプロジェクトでは、以下の2つのCloudFormationテンプレートを使用します。

## 1. rds-replication.yaml

基本的なAurora MySQL環境を構築するためのテンプレートです。

### 主要リソース

- **VPC** - プライベートネットワーク環境
- **サブネット** - パブリックサブネット2つとプライベートサブネット2つ
- **Aurora MySQLクラスター** - 2つのデータベースクラスター
  - マスターDB: `hogedb`（デフォルト、変更可能）
  - セカンドDB: `fugadb`（デフォルト、変更可能）
- **踏み台EC2インスタンス** - SSM接続可能なEC2インスタンス

### パラメータ

| パラメータ名 | 説明 | デフォルト値 |
|------------|------|------------|
| MasterDBName | マスターデータベース名 | hogedb |
| SecondDBName | セカンドデータベース名 | fugadb |
| DBInstanceClass | DBインスタンスクラス | db.t3.medium |
| DBUsername | データベース管理者ユーザー名 | admin |
| DBPassword | データベース管理者パスワード | - |
| UseCustomKMSKey | カスタムKMSキーを使用するかどうか | true |
| EC2InstanceType | 踏み台サーバーのインスタンスタイプ | t3.micro |
| LatestAmiId | 最新のAmazon Linux 2 AMI ID | /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 |

### 出力値

| 出力名 | 説明 |
|--------|------|
| MasterDBEndpoint | マスターDBのエンドポイント |
| MasterDBReadEndpoint | マスターDBのリードエンドポイント |
| SecondDBEndpoint | セカンドDBのエンドポイント |
| SecondDBReadEndpoint | セカンドDBのリードエンドポイント |
| BastionInstanceId | 踏み台サーバーのインスタンスID |
| SSMConnectCommand | SSMを使用して踏み台サーバーに接続するコマンド |

## 2. dms-replication.yaml

AWS DMSを使用してセカンドDBからマスターDBへのレプリケーションを設定するためのテンプレートです。

### 主要リソース

- **カスタムリソース** - 既存スタックの出力値を取得するためのLambda関数
- **DMSサブネットグループ** - 既存VPCのプライベートサブネットを使用
- **DMSセキュリティグループ** - 既存のRDSセキュリティグループとの通信を許可
- **DMSサービスロール** - 必要なIAMロールとポリシー
- **DMSレプリケーションインスタンス** - レプリケーションを実行するインスタンス
- **DMSソースエンドポイント** - セカンドDBを指すエンドポイント
- **DMSターゲットエンドポイント** - マスターDBを指すエンドポイント
- **DMSレプリケーションタスク** - レプリケーション設定

### パラメータ

| パラメータ名 | 説明 | デフォルト値 |
|------------|------|------------|
| ExistingStackName | 既存のAurora MySQLスタックの名前 | - |
| DBUsername | データベースユーザー名 | - |
| DBPassword | データベースパスワード | - |
| DMSInstanceClass | DMSレプリケーションインスタンスのクラス | dms.t3.medium |
| SourceDatabaseName | レプリケーション対象のデータベース名 | world |

### 出力値

| 出力名 | 説明 |
|--------|------|
| DMSTaskARN | DMSレプリケーションタスクのARN |
| StopTaskCommand | レプリケーションタスクを停止するコマンド |
| StartTaskCommand | レプリケーションタスクを再開するコマンド |

## テンプレートの連携

`dms-replication.yaml`テンプレートは、`rds-replication.yaml`で作成されたリソースを参照します。具体的には、カスタムリソース（Lambda関数）を使用して既存スタックの出力値を取得し、DMSリソースの設定に使用します。

これにより、2つのスタックを別々にデプロイしながらも、リソース間の連携を実現しています。