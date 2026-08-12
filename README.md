# AgentCore Agent Template

Amazon Bedrock AgentCore を使ってエージェントを素早く立ち上げるためのテンプレートリポジトリ。  
[aws-samples/sample-genai-strats](https://github.com/aws-samples/sample-genai-strats) を個人用リファレンスとしてカスタマイズしたもの。

> 元ワークショップ: [Building AI Agents on AgentCore](https://catalog.us-east-1.prod.workshops.aws/workshops/05695036-0049-4114-a660-f15071df92dc/en-US)

---

## アーキテクチャ

### 全体像

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          呼び出し元 (クライアント)                         │
│             curl / SDK / 別エージェント                                    │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │  invoke_agent_runtime (HTTPS)
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                   AgentCore Runtime  (エージェント実行基盤)                 │
│                                                                         │
│   agent.py  ──────────────────────────────────────────────────────┐    │
│   ├── Strands Agent (Claude Sonnet 4.6)                            │    │
│   ├── system_prompt.py     ← エージェントの役割定義                  │    │
│   ├── tools/ (Python)      ← ドメイン固有ロジック                    │    │
│   ├── memory_config.py  ───┼──► AgentCore Memory                  │    │
│   └── mcp_client.py  ──────┼──► AgentCore Gateway (MCP)           │    │
│                             │                                      │    │
│   OTEL (X-Ray + CloudWatch Logs による自動トレース)                  │    │
└─────────────────────────────┼──────────────────────────────────────┘    │
                              │                                            │
          ┌───────────────────┼────────────────────┐                      │
          │                   │                    │                      │
          ▼                   ▼                    ▼                      │
┌──────────────┐  ┌──────────────────┐  ┌──────────────────────┐         │
│  AgentCore   │  │    AgentCore     │  │   Bedrock Knowledge  │         │
│   Memory     │  │    Gateway       │  │       Base           │         │
│              │  │  (MCP プロトコル) │  │                      │         │
│ ・会話の記憶  │  │  ・ツール公開     │  │ ・S3 ドキュメント     │         │
│ ・ユーザー   │  │  ・JWT 認証      │  │ ・S3 Vectors インデクス│         │
│   嗜好の蓄積 │  │  ・Lambda 呼出し  │  │ ・Cohere Embed v3    │         │
│             │  │                  │  │   (多言語 embedding)  │         │
│ SEMANTIC    │  │  ┌────────────┐  │  └──────────────────────┘         │
│ USER_PREF   │  │  │   Lambda   │  │                                    │
│ 2 strategy  │  │  │  example-  │  │                                    │
└─────────────┘  │  │    tool    │  │                                    │
                 │  └────────────┘  │                                    │
                 │                  │                                    │
                 │  ┌────────────┐  │                                    │
                 │  │  Cognito   │  │  ← JWT 発行 (client_credentials)  │
                 │  │  User Pool │  │                                    │
                 │  └────────────┘  │                                    │
                 └──────────────────┘                                    │
                          │                                              │
                          ▼                                              │
                 ┌──────────────────┐                                    │
                 │  AgentCore       │                                    │
                 │  Identity        │                                    │
                 │                  │                                    │
                 │ ・WorkloadIdentity│ ← Runtime が Gateway を呼ぶ際の    │
                 │ ・OAuth2          │   認証情報を自動取得               │
                 │   CredentialProv. │                                    │
                 └──────────────────┘                                    │
```

### コンポーネント一覧

| コンポーネント | AWSサービス | 役割 |
|---|---|---|
| **AgentCore Runtime** | Amazon Bedrock AgentCore | エージェントのホスティング基盤。コンテナ不要で Python コードを直接デプロイ |
| **Strands Agent** | Strands Agents SDK + Bedrock | ツール呼び出し・会話管理のオーケストレーター |
| **推論モデル** | Claude Sonnet 4.6 (`ap.*`) | 東京リージョン cross-region inference profile |
| **AgentCore Memory** | Amazon Bedrock AgentCore | 会話をまたいだ記憶の永続化。SEMANTIC（事実）と USER_PREFERENCE（嗜好）の2種類 |
| **AgentCore Gateway** | Amazon Bedrock AgentCore | Lambda ツールを MCP プロトコルで公開。JWT で認証 |
| **AgentCore Identity** | Amazon Bedrock AgentCore | Runtime が Gateway を呼ぶ際の OAuth2 トークン取得を自動化 |
| **Cognito User Pool** | Amazon Cognito | Gateway の JWT 発行元。client_credentials フロー (M2M) |
| **Knowledge Base** | Amazon Bedrock Knowledge Base | S3 ドキュメントをベクトル検索可能にする RAG 基盤 |
| **S3 Vectors** | Amazon S3 Vectors | ベクトルインデックスのストレージ（1024次元、cosine距離）|
| **Embedding モデル** | Cohere Embed Multilingual v3 | 日本語を含む100言語以上対応の embedding |
| **Lambda ツール** | AWS Lambda | Gateway 経由で公開される外部 API / DB アクセス用ツール |
| **CloudWatch + X-Ray** | Amazon CloudWatch, AWS X-Ray | 全コンポーネントの分散トレース・ログ収集 |

---

### リクエストフロー（詳細）

```
クライアント
    │
    │ 1. invoke_agent_runtime(payload={"prompt": "..."})
    ▼
AgentCore Runtime
    │
    │ 2. agent.py の invoke() を呼び出す
    ▼
Strands Agent
    ├─ 3a. Memory から過去の会話・嗜好を取得 (retrieval)
    ├─ 3b. Claude Sonnet 4.6 に system_prompt + user_prompt + memory を送信
    │
    │  Claude がツール呼び出しを決定
    ├─ 4a. Python ツール (例: search_knowledge_base)
    │       └─► Bedrock Knowledge Base (Cohere embed → S3 Vectors 検索)
    │
    ├─ 4b. MCP Gateway ツール (例: example_tool)
    │       └─► Cognito でトークン取得 (WorkloadIdentity 経由)
    │       └─► Gateway → Lambda 実行
    │
    │ 5. 最終回答をストリーミングで返却
    ▼
クライアント
    │
    └─ 6. 会話終了後、Memory に事実・嗜好を書き込み (flush)
```

---

### Terraform モジュール構成と依存関係

```
bootstrap.tf         # ランダムプレフィックス + project_name 生成
      │
      ├── module.knowledge_base   (独立)
      │     ├── S3 バケット (ドキュメント格納)
      │     ├── S3 Vectors インデックス
      │     └── Bedrock Knowledge Base
      │
      ├── module.memory           (独立)
      │     ├── AgentCore Memory
      │     ├── SEMANTIC strategy
      │     └── USER_PREFERENCE strategy
      │
      ├── module.gateway          (独立)
      │     ├── Cognito User Pool + M2M Client
      │     ├── AgentCore Gateway (MCP/JWT)
      │     └── Lambda ツール群
      │
      ├── module.identity         (gateway に依存)
      │     ├── WorkloadIdentity
      │     └── OAuth2 CredentialProvider ← Cognito の client_id/secret を注入
      │
      └── module.runtime          (全モジュールに依存)
            ├── S3 (agent.zip 格納)
            └── AgentCore Runtime
                  └── 環境変数で各モジュールの ID/URL を注入
```

---

## ファイル構成

```
workshops/agentcore-building-ai-agents/
├── src/agent/
│   ├── agent_config.py      # ★ 設定の起点 — ここを最初に編集
│   ├── agent.py             # エントリポイント・ツール登録
│   ├── system_prompt.py     # ★ エージェントの役割定義
│   ├── memory_config.py     # AgentCore Memory 接続 (インフラ)
│   ├── mcp_client.py        # AgentCore Gateway MCP 接続 (インフラ)
│   ├── identity_helper.py   # Cognito / WorkloadIdentity 認証 (インフラ)
│   └── tools/
│       ├── example_lookup.py    # ★ ツール例 — 置き換える
│       └── knowledge_base.py    # Knowledge Base RAG ツール (汎用)
├── src/lambdas/
│   └── example-tool/        # ★ Gateway 経由で呼ばれる Lambda ツール例
├── knowledge-base/
│   └── example-doc.txt      # ★ Knowledge Base に投入するドキュメント
├── .env.example             # ローカル開発用の環境変数サンプル
└── terraform/
    ├── bootstrap.tf          # ★ プロジェクト名はここで変更
    ├── workshop.tf           # 全モジュールの組み立て
    ├── memory/               # AgentCore Memory
    ├── knowledge_base/       # Bedrock Knowledge Base + S3 Vectors
    ├── gateway/              # AgentCore Gateway + Cognito + Lambda tools
    ├── identity/             # WorkloadIdentity + CredentialProvider
    └── runtime/              # AgentCore Runtime
```

---

## 新しいエージェントの作り方

### 1. プロジェクト名を変更

`terraform/bootstrap.tf`:
```hcl
project_name_short = "my-agent"   # ← 変更
```

### 2. エージェント設定を変更

`src/agent/agent_config.py`:
```python
AGENT_NAME              = "My Agent"
MODEL_ID                = "ap.anthropic.claude-sonnet-4-6"
MEMORY_NAMESPACE_PREFIX = "my-agent/user"   # terraform/memory/memory.tf と一致させる
```

### 3. システムプロンプトを書く

`src/agent/system_prompt.py` の `SYSTEM_PROMPT` を書き換える。

### 4. ツールを追加・差し替え

**Python ツール** (`src/agent/tools/`):  
`example_lookup.py` を参考に `@tool` デコレーターで関数を作り、`agent.py` の `tools` リストに追加する。

**Gateway ツール** (Lambda 経由で外部 API を叩く場合):  
1. `src/lambdas/example-tool/handler.py` を複製・編集  
2. `terraform/gateway/lambda.tf` にブロックを追加  
3. `terraform/gateway/gateway.tf` に `aws_bedrockagentcore_gateway_target` ブロックを追加  

### 5. Knowledge Base のドキュメントを差し替え

`knowledge-base/` の `example-doc.txt` を自分のドメインのドキュメントに置き換え、  
`terraform/knowledge_base/s3-kb-source.tf` の `kb_documents` リストを更新する。

### 6. Memory の namespace を合わせる

`terraform/memory/memory.tf` の `namespaces` を `agent_config.py` の `MEMORY_NAMESPACE_PREFIX` と一致させる。

### 7. デプロイ

```bash
cd workshops/agentcore-building-ai-agents
make build-agent-package   # agent.zip を作成
make deploy-infra          # Terraform apply (全モジュール)
make status                # デプロイ済みリソース ID を確認
make run-agent-locally     # ローカルで動作確認（Terraform デプロイ後）
make invoke-agent          # デプロイ済み Runtime を呼び出す
```

### ローカルでの部分動作確認（Terraform 不要）

```bash
cp .env.example .env
# .env を編集し、使いたいサービスの ID だけ埋める
# 未設定の変数はスキップされ、その機能がオフになる
# 例: MEMORY_ID, GATEWAY_URL を空欄にすると memory・MCP なしで動作
cd src/agent && uv run agent.py
```

---

## 日本語対応

| 設定 | 値 | 理由 |
|---|---|---|
| AWSリージョン | `ap-northeast-1` (東京) | デフォルト。`terraform/providers.tf` で変更可 |
| 推論モデル | `ap.anthropic.claude-sonnet-4-6` | 東京リージョンの cross-region inference profile |
| Embedding モデル | `cohere.embed-multilingual-v3` | 100言語以上対応、Titan v2より日本語精度が高い |
| チャンクサイズ | 150 tokens (overlap 20%) | 日本語は英語より文字密度が高いため小さめに設定 |
| システムプロンプト | 日本語ベース | ユーザーの言語に合わせて返答するよう指示済み |

### 他リージョンに変更する場合

`terraform/providers.tf`:
```hcl
provider "aws" {
  region = "us-east-1"
}
```

`src/agent/agent_config.py`:
```python
MODEL_ID = "us.anthropic.claude-sonnet-4-6"   # us-east-1 の場合は "us." プレフィックス
```

---

## ファイルの編集不要ゾーン（インフラ配線）

| ファイル | 役割 |
|---|---|
| `identity_helper.py` | Cognito / WorkloadIdentity トークン取得 |
| `mcp_client.py` | Gateway MCP 接続 |
| `logger.py` | ログ設定 |
| `terraform/identity/` | WorkloadIdentity + OAuth2 CredentialProvider |
| `terraform/gateway/cognito.tf` | Cognito M2M 認証 |
| `terraform/*/observability.tf` | CloudWatch Logs + X-Ray 分散トレース |

---

## バグ修正メモ

**`terraform/memory/memory.tf` — メモリ strategy の race condition**  
`aws_bedrockagentcore_memory` 作成直後は `UPDATING` 状態で strategy をアタッチできない。  
`time_sleep(30s)` + `depends_on` で回避済み。

---

## ライセンス

MIT-0 — See [LICENSE](LICENSE).
