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

