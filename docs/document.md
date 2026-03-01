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
