# AWS DMS用IAMロールの設定手順

AWS Database Migration Service (DMS)を使用するには、特定のIAMロールが必要です。このドキュメントでは、DMSに必要なIAMロールを正しく設定する手順を説明します。

## 必要なIAMロール

DMSを使用するには、以下の2つの主要なIAMロールが必要です：

1. **dms-vpc-role** - DMSがVPC内のリソース（サブネット、セキュリティグループなど）にアクセスするために必要
2. **dms-cloudwatch-logs-role** - DMSがCloudWatch Logsにログを送信するために必要

## IAMロールの設定方法

CloudFormationを使用してIAMロールを作成する方法が最も管理しやすく推奨されます。

1. **IAMロール用CloudFormationテンプレートを確認**

   `iam-setup/dms-iam-roles.yaml`ファイルが既に用意されています。このテンプレートには、DMSに必要なIAMロールの定義が含まれています。

2. **CloudFormationスタックをデプロイ**

   以下のコマンドを実行して、IAMロールを作成します：

   ```bash
   ./run.sh deploy-iam
   ```

   > **注意**: 既に`dms-vpc-role`と`dms-cloudwatch-logs-role`が存在する場合、スクリプトはそれを検出し、既存のロールを使用します。一部のロールだけが存在する場合は警告が表示され、続行するかどうかを確認されます。

3. **スタックのデプロイ状況を確認**

   以下のコマンドでデプロイ状況を確認できます：

   ```bash
   ./run.sh status-iam
   ```

   `"StackStatus": "CREATE_COMPLETE"`と表示されれば成功です。

## IAMロールの検証

IAMロールが正しく作成されたことを確認するには、`./run.sh status-iam`コマンドを実行します。このコマンドは各IAMロールのARNを表示します。

## DMSレプリケーションのデプロイ

IAMロールの設定が完了したら、DMSレプリケーションをデプロイできます：

```bash
./run.sh deploy-dms --db-password <データベースパスワード> --source-db world
```

## トラブルシューティング

### 一般的なエラー

1. **「The IAM Role arn:aws:iam::XXXX:role/dms-vpc-role is not configured properly」エラー**

   このエラーは、`dms-vpc-role`が存在しないか、正しく設定されていない場合に発生します。以下を確認してください：

   - `./run.sh status-iam`コマンドを実行して、ロールが正しく作成されているか確認
   - 必要に応じて、`./run.sh deploy-iam`コマンドを再実行してください。

2. **「User is not authorized to perform: iam:PassRole on resource」エラー**

   このエラーは、DMSスタックをデプロイするユーザーに`iam:PassRole`権限がない場合に発生します。AWS管理者に連絡して、適切な権限を付与してもらってください。

3. **既存のロールを削除する必要がある場合**

   既存のロールを削除するには、以下のコマンドを実行します：

   ```bash
   ./run.sh delete-iam
   ```

## 参考情報

- [AWS DMS公式ドキュメント - IAMロールの作成](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Security.html#CHAP_Security.APIRole)
- [AWS DMS公式ドキュメント - トラブルシューティング](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Troubleshooting.html)