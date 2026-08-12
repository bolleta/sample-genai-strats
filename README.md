# sample-genai-strats (personal reference)

Personal reference fork of [aws-samples/sample-genai-strats](https://github.com/aws-samples/sample-genai-strats).

This repo contains the `agentcore-building-ai-agents` workshop with bug fixes and notes applied during hands-on work.

## Included

| Path | Description |
|------|-------------|
| `workshops/agentcore-building-ai-agents/` | Amazon Bedrock AgentCore workshop — customer support agent with memory, knowledge base, and gateway |
| `agentcore/` | AgentCore SDK boilerplate examples |

## Bug Fixes Applied

### `terraform/memory/memory.tf` — race condition on memory strategy creation

`aws_bedrockagentcore_memory` enters `UPDATING` state after creation. Attaching strategies immediately causes:

```
ValidationException: Memory is in transitional state UPDATING. Cannot update memory.
```

**Fix:** added `time_sleep.wait_for_memory` (30s) with `depends_on` on both strategy resources.

## Getting Started

```bash
cd workshops/agentcore-building-ai-agents
make deploy-infra   # Terraform apply
make deploy-agent   # Build & push agent container
```

See [`workshops/agentcore-building-ai-agents/README.md`](workshops/agentcore-building-ai-agents/README.md) for full instructions.

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

MIT-0 — See [LICENSE](LICENSE).
