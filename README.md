# Archived — this work has moved

This is a fork of [aws-samples/sample-genai-strats](https://github.com/aws-samples/sample-genai-strats)
where I customized the upstream Amazon Bedrock AgentCore workshops. That work has since
been extracted into a standalone repository:

**→ [bolleta/agentcore-agent-template-jp](https://github.com/bolleta/agentcore-agent-template-jp)**

A deployable Terraform template for Amazon Bedrock AgentCore agents, tuned for
ap-northeast-1 (Tokyo) and Japanese workloads. What changed relative to upstream — all
five Terraform modules wired and deployable, three defects fixed, IAM narrowed from
`bedrock:*` to an explicit action list, multilingual embeddings for Japanese retrieval,
and a consistency test suite with CI — is documented in that repository's README.

This repository is archived and kept only as the original development record: the seven
commits dated 2026-08-12 on top of upstream `main` are where the customization actually
happened.

---

Upstream: [aws-samples/sample-genai-strats](https://github.com/aws-samples/sample-genai-strats),
MIT-0, © Amazon.com, Inc. or its affiliates. The `LICENSE` and copyright notice are
retained unchanged.
