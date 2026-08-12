# AgentCore Agent Template

Amazon Bedrock AgentCore を使ってエージェントを素早く立ち上げるためのテンプレートリポジトリ。  
[aws-samples/sample-genai-strats](https://github.com/aws-samples/sample-genai-strats) を個人用リファレンスとしてカスタマイズしたもの。

## 構成

```
workshops/agentcore-building-ai-agents/
├── src/agent/               # エージェント本体 (Python / Strands)
│   ├── agent_config.py      # ★ 設定の起点 — ここを最初に編集
│   ├── agent.py             # エントリポイント・ツール登録
│   ├── system_prompt.py     # ★ エージェントの役割定義
│   ├── memory_config.py     # AgentCore Memory 接続 (インフラ)
│   ├── mcp_client.py        # AgentCore Gateway 接続 (インフラ)
│   ├── identity_helper.py   # Cognito / WorkloadIdentity 認証 (インフラ)
│   └── tools/
│       ├── example_lookup.py    # ★ ツール例 — 置き換える
│       └── knowledge_base.py    # Knowledge Base RAG ツール (汎用)
├── src/lambdas/
│   └── example-tool/        # ★ Gateway 経由で呼ばれる Lambda ツール例
├── knowledge-base/
│   └── example-doc.txt      # ★ Knowledge Base に投入するドキュメント
└── terraform/
    ├── bootstrap.tf          # ★ プロジェクト名はここで変更
    ├── workshop.tf           # 全モジュールの組み立て
    ├── memory/               # AgentCore Memory
    ├── knowledge_base/       # Bedrock Knowledge Base + S3 Vectors
    ├── gateway/              # AgentCore Gateway + Cognito + Lambda tools
    ├── identity/             # WorkloadIdentity + CredentialProvider
    └── runtime/              # AgentCore Runtime (コンテナ不要)
```

## 新しいエージェントの作り方

### 1. プロジェクト名を変更

`terraform/bootstrap.tf`:
```hcl
project_name_short = "my-agent"   # ← 変更
```

### 2. エージェント設定を変更

`src/agent/agent_config.py`:
```python
AGENT_NAME             = "My Agent"
MODEL_ID               = "us.anthropic.claude-sonnet-4-6"
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
make deploy-infra          # Terraform apply
make run-agent-locally     # ローカルで動作確認
make invoke-agent          # デプロイ済み Runtime を呼び出す
```

## ファイルの編集不要ゾーン

以下はインフラ配線であり、通常は触らなくてよい:

| ファイル | 役割 |
|---|---|
| `identity_helper.py` | Cognito / WorkloadIdentity トークン取得 |
| `mcp_client.py` | Gateway MCP 接続 |
| `logger.py` | ログ設定 |
| `terraform/identity/` | WorkloadIdentity + OAuth2 CredentialProvider |
| `terraform/gateway/cognito.tf` | Cognito M2M 認証 |
| `terraform/*/observability.tf` | CloudWatch Logs + X-Ray |

## バグ修正メモ

**`terraform/memory/memory.tf` — メモリ strategy の race condition**  
`aws_bedrockagentcore_memory` 作成直後は `UPDATING` 状態で strategy をアタッチできない。  
`time_sleep(30s)` + `depends_on` で回避済み。

## ライセンス

MIT-0 — See [LICENSE](LICENSE).
