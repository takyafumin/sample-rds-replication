# サンプルデータディレクトリ

このディレクトリには、DMSレプリケーションのテストに使用されるサンプルデータベースファイルが保存されます。

## 含まれるサンプルデータ

1. **World データベース**
   - 出典: MySQL公式サンプルデータベース
   - URL: https://dev.mysql.com/doc/index-other.html (「Example Databases」セクションの「world database」)
   - 内容: 国、都市、言語に関する情報を含むシンプルなデータベース

## 必要なファイル

このディレクトリには以下のファイルを配置する必要があります：

- `world.sql` - World データベースのダンプファイル

または、以下の圧縮ファイルを配置することで、`run.sh prepare-sample-data` コマンドを使用して自動的に上記のファイルを作成できます：

- `world-db.zip` - World データベースの圧縮ファイル

## ファイルの準備手順

### 自動準備（推奨）

プロジェクトルートディレクトリで以下のコマンドを実行すると、サンプルデータファイルを自動的に準備できます：

```bash
./run.sh prepare-sample-data
```

このコマンドは、`resources/samples` ディレクトリにある圧縮ファイルから必要なSQLファイルを抽出・作成します。

### 手動準備

#### World データベース

1. MySQL公式サイト (https://dev.mysql.com/doc/index-other.html) から「world database」をダウンロード
2. ダウンロードしたファイル（例: `world-db.zip`）をこのディレクトリに配置

または、既にダウンロードされている `world-db.zip` ファイルを使用する場合：

```bash
unzip world-db.zip
# 解凍されたSQLファイルを確認
ls -la
# 必要に応じてファイル名を変更
mv [解凍されたSQLファイル] world.sql
```

または、直接 `world.sql` ファイルをこのディレクトリに配置することもできます。

## 注意事項

- このディレクトリは `.gitignore` で管理対象外に設定されています。
- `run.sh prepare-sample-data` コマンドを使用すると、必要なサンプルデータファイルを自動的に準備できます。
- 自動準備が失敗した場合は、上記の手動準備手順に従ってファイルを配置してください。
- `scripts/import_sample_db.sh` スクリプトは、このディレクトリに配置された `world.sql` ファイルを使用して以下のデータベースをインポートします：
  - `world` データベース（レプリケーション対象）
  - `worldnonrepl` データベース（レプリケーション非対象）