# AWS全体構成

## ネットワーク
- VPC（例：2AZ）
  - Private Subnet (AZ-a)
    - RDS(Postgres)
    - SSM作業EC2（※どちらのAZでもOK）
    - App Runner VPC Connector 用サブネット
  - Private Subnet (AZ-c)
    - RDSのMulti-AZや冗長化用（推奨）
    - VPC Connector用（推奨）

## コンポーネント
- App Runner
  - 公開Web/API（インターネット向け）として稼働
  - Outgoing traffic を “Custom VPC” にして VPC Connector を紐づけ

- RDS for PostgreSQL
  - Private Subnet 配置（DBは外部公開しない）
  - Security Group で App Runner側SGから5432のみ許可

- SSM作業EC2（SSH踏み台の代替）
  - Private Subnetに配置
  - 22番(SSH)は開けない（inbound 0でOK
  - Session Manager で接続して、EC2上で psql などを実行
  - 依存要素
    - IAM Instance Profile（SSMに必要な権限）
    - VPC Endpoint（推奨） もしくは NAT（どちらか必須）

---

## Secrets Manager / KMS / IAM 設計

### Terraformで管理するもの
- Secrets Manager の **Secret の器**
  - aws_secretsmanager_secret  
    - 名前・説明  
    - KMSキー指定  
    - タグ  
    - 削除保護
- 必要に応じた暗号鍵
  - aws_kms_key  
  - aws_kms_alias
- App Runner 側の設定
  - どの Secret を参照するかの定義
- IAM
  - App Runner が Secrets Manager を読める最小権限
  - KMS の Decrypt 権限

### Terraformで管理しないもの
- Secret の **値そのもの（aws_secretsmanager_secret_version）**
  - 本番値は AWS CLI / Console / CI から投入
  - Terraform state への平文保存を回避

### IAM（App Runner 用）
- 許可アクション
  - secretsmanager:GetSecretValue
  - kms:Decrypt
- 許可リソース
  - 参照する Secret ARN
  - 利用する KMS Key ARN

---

## Terraform 適用手順（0 から構築する場合）

1. **認証情報の準備**  
   Terraform から操作する AWS アカウントのクレデンシャルを AWS CLI または環境変数で設定し、`aws sts get-caller-identity` などで確認します。
2. **変数ファイルの用意**  
   `terraform/terraform.tfvars.example` を `terraform/terraform.tfvars` にコピーし、`project_name` や `db_username`、タグなど環境に応じて更新します（DB パスワードは Secrets Manager により自動生成・管理されるため不要）。
3. **初期化**  
   `cd terraform` 後に `terraform init` を実行してプロバイダをダウンロードします。
4. **差分確認**  
   `terraform plan` を実行して作成されるリソースを確認します。RDS のマスターシークレットは apply 中に自動作成され、App Runner などの依存リソースも同一 run で問題ありません。
5. **適用**  
   `terraform apply` を実行し、内容を確認して `yes` を入力します。完了後は `terraform output` で VPC ID や App Runner URL、Secrets Manager ARN などを取得できます。
6. **動作確認**  
   App Runner 経由でアプリと DB が疎通できること、SSM EC2 に Session Manager で接続できることなどを確認し、必要に応じて Terraform state をバックアップします。

### App Runner 用 ECR イメージの更新（オプション）
Terraform は常に `app_runner_ecr_repository_url` で示すリポジトリを作成しますが、デフォルト (`use_managed_ecr = false`) では `app_runner_image_identifier` で指定した public ECR イメージを参照するだけです。自前のリポジトリから起動したい場合は `use_managed_ecr = true` に切り替え、App Runner を再作成してから以下の手順でイメージをプッシュします。

1. `terraform output app_runner_ecr_repository_url` でリポジトリ URL を確認します（例: `123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/terraform-sample-app`）。
2. ローカルでログイン: `aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin <repository_url>`。
3. アプリコンテナをビルドしてタグ付け: `docker build -t <repository_url>:<tag> .`。
4. `docker push <repository_url>:<tag>` でプッシュすると、App Runner が `app_runner_image_tag` で指定したタグ（デフォルト latest）を pull して再デプロイできます。

---

## SSM 経由で RDS に接続する手順

1. **Session Manager プラグインの準備**  
   ローカル端末で AWS CLI v2 および Session Manager Plugin をインストールし、`aws configure` で対象アカウント／リージョン (ap-northeast-1) に接続できるようにします。

2. **Secrets Manager から DB 資格情報を取得**  
   `terraform output app_runner_secret_arn` などで RDS が管理するシークレット ARN を確認し、以下で最新パスワードを取得します。  
   ```bash
   aws secretsmanager get-secret-value \
     --secret-id <シークレットARN> \
     --region ap-northeast-1 \
     --query SecretString --output text
   ```
   取得した JSON の `password` を `PGPASSWORD` として控えておきます。

3. **ポートフォワーディングを開始**  
   Session Manager で RDS へのトンネルを張ります (別ターミナルで実行すると便利です)。  
   ```bash
   aws ssm start-session \
     --target <SSM作業EC2のインスタンスID> \
     --document-name AWS-StartPortForwardingSessionToRemoteHost \
     --parameters '{
       "host":["<RDSエンドポイント>"],
       "portNumber":["5432"],
       "localPortNumber":["5432"]
     }' \
     --region ap-northeast-1
   ```
   `Port 5432 opened ... Waiting for connections...` が表示されたままの状態で次へ進みます。

4. **`psql` で接続**  
   別ターミナルを開き、取得したパスワードと `sslmode=require` を使って接続します。  
   ```bash
   export PGPASSWORD=<Step2で取得したpassword>
   psql "host=localhost port=5432 dbname=appdb user=appuser sslmode=require"
   ```
   接続が完了したら通常通り SQL を実行できます。終了後は `Ctrl+C` で Session Manager のポートフォワーディングを停止します。
