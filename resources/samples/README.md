# サンプルデータディレクトリ

このディレクトリには、DMSレプリケーションのテストに使用されるサンプルデータベースファイルが保存されます。

## 含まれるサンプルデータ

1. **World データベース**
   - 出典: MySQL公式サンプルデータベース
   - URL: https://dev.mysql.com/doc/index-other.html (「Example Databases」セクションの「world database」)
   - 内容: 国、都市、言語に関する情報を含むシンプルなデータベース

2. **Employees データベース**
   - 出典: datacharmer/test_db GitHub リポジトリ
   - URL: https://github.com/datacharmer/test_db
   - 内容: 従業員情報を含む大規模なサンプルデータベース

## 必要なファイル

このディレクトリには以下のファイルを配置する必要があります：

- `world.sql` - World データベースのダンプファイル
- `employees.sql` - Employees データベースのダンプファイル

## ファイルの準備手順

### World データベース

1. MySQL公式サイト (https://dev.mysql.com/doc/index-other.html) から「world database」をダウンロード
2. ダウンロードしたファイル（例: `world-db.zip`）を解凍
3. 解凍したファイルを `world.sql` として保存または名前変更

または、既にダウンロードされている `world-db.zip` ファイルを使用する場合：

```bash
unzip world-db.zip
# 解凍されたSQLファイルを確認
ls -la
# 必要に応じてファイル名を変更
mv [解凍されたSQLファイル] world.sql
```

### Employees データベース

1. GitHub リポジトリ (https://github.com/datacharmer/test_db) からダウンロード
2. リポジトリをクローンまたはZIPファイルとしてダウンロード
3. 以下のファイルを結合して `employees.sql` として保存：
   - employees.sql
   - load_departments.dump
   - load_employees.dump
   - load_dept_emp.dump
   - load_dept_manager.dump
   - load_titles.dump
   - load_salaries.dump

または、既にダウンロードされている `test_db-1.0.7.tar.gz` ファイルを使用する場合：

```bash
tar -xzf test_db-1.0.7.tar.gz
cd test_db-1.0.7
# 必要なファイルを結合
cat employees.sql load_departments.dump load_employees.dump load_dept_emp.dump load_dept_manager.dump load_titles.dump load_salaries.dump > ../employees.sql
cd ..
```

## 注意事項

- このディレクトリは `.gitignore` で管理対象外に設定されています。
- 最新のスクリプトでは、サンプルデータは自動的にダウンロードされません。手動で上記のファイルを準備する必要があります。
- `scripts/import_sample_db.sh` スクリプトは、このディレクトリに配置された `world.sql` と `employees.sql` ファイルを使用してデータベースをインポートします。