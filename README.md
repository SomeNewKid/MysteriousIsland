# MysteriousIsland

MysteriousIsland is a small Microsoft Foundry hosted-agent sample for testing
retrieval-augmented generation (RAG) with a code-first Python agent.

The hosted agent discusses Jules Verne's *The Mysterious Island*. It uses the
Agent Framework `FoundryChatClient` with Foundry's built-in `file_search` tool
against an uploaded vector store containing the book text and private reading
notes.

> [!WARNING]
> This is an experimental learning project and should not be considered
> production-ready.

## What It Does

The agent answers questions such as:

- "Who is Cyrus Harding?"
- "Who asked the question, 'Is it possible that he can have lived at the bottom
  of the sea?'"
- "What is the secret verification phrase for The Mysterious Island?"

The agent is instructed to use only uploaded knowledge through `file_search`.
The private reading notes intentionally contain experiment-specific facts that
are not part of the novel, which makes it easier to prove that retrieval is
working and the model is not relying on general training knowledge.

## Architecture

```text
Foundry hosted agent
  -> src/mysterious-island/main.py
  -> Agent Framework FoundryChatClient
  -> Foundry file_search tool
  -> Foundry vector store
  -> uploaded .knowledge/*.txt files
```

The azd project is rooted at the repository root. The deployable hosted-agent
source lives in `src/mysterious-island`.

## Knowledge Files

Knowledge source files are kept locally under `.knowledge/`, which is ignored by
Git. The current local setup uses:

```text
.knowledge/
  The Mysterious Island.txt
  Mysterious Island - Private Reading Notes.txt
```

The upload script indexes all `.txt` files in `.knowledge` into the Foundry
vector store and skips files that are already present by filename:

```powershell
.\scripts\upload-knowledge.ps1
```

After upload, the script records the vector store ID in the local azd
environment as:

```text
MYSTERIOUS_ISLAND_VECTOR_STORE_ID
```

That value is passed to the hosted container through `azure.yaml`.

## Foundry Setup

This project uses the Azure Developer CLI (`azd`) and the Foundry hosted-agent
extension. The important azd configuration is in `azure.yaml`:

```text
project name: mysterious-island
agent service: mysterious-island
agent name: mysterious-island
model deployment: gpt-4.1-mini
protocol: responses
```

The hosted agent expects these environment values:

- `AZURE_AI_MODEL_DEPLOYMENT_NAME`
- `MYSTERIOUS_ISLAND_VECTOR_STORE_ID`

The vector store must be created and populated before the deployed agent can
answer with file search.

## Requirements

- Python 3.11 for local development checks.
- PowerShell on Windows.
- Azure Developer CLI (`azd`) with the Foundry agent extension.
- An Azure subscription with access to the Foundry project.
- Azure authentication for the tenant that owns the Foundry project.

## Setup

Create the local development virtual environment and install dependencies:

```powershell
.\scripts\setup-dev.ps1
```

The setup script expects Python 3.11 at the path configured in
`scripts\setup-dev.ps1`.

## Uploading Knowledge

Place local `.txt` knowledge files in `.knowledge`, then run:

```powershell
.\scripts\upload-knowledge.ps1
```

The command calls Foundry, creates or reuses the vector store named
`mysterious-island-book`, uploads missing files, waits for indexing, and stores
the vector store ID for later deploys.

## Deploying

Deploy the hosted agent from the repository root:

```powershell
azd deploy
```

The command creates a new immutable hosted-agent version in Foundry.

## Invoking The Agent

Create a session:

```powershell
azd ai agent sessions create
```

Invoke the deployed agent:

```powershell
azd ai agent invoke --session-id <session-id> --new-conversation "Who is Cyrus Harding?"
```

The command calls the live Foundry endpoint and may incur Azure or model usage
costs.

## Monitoring Logs

Stream hosted-agent logs for a session:

```powershell
azd ai agent monitor --session-id <session-id> --follow
```

Startup logs include a local code marker such as:

```text
Mysterious Island agent starting version=2026-08-12.3 model=gpt-4.1-mini vector_store_id=...
```

Current Agent Framework hosting logs show `file_search` activity as
`search_tool_call` and `search_tool_result`, but the serialized query and result
details may appear empty because those content types are not fully supported by
the hosting log adapter yet.

## Development Checks

Run formatting, linting, and type checking:

```powershell
.\scripts\check.ps1
```

This runs:

- `ruff format .`
- `ruff check .`
- `pyright`

This project currently does not include unit tests.

## Project Structure

```text
src/mysterious-island/
  main.py           Hosted agent setup, instructions, file_search tool, server
  Dockerfile        Container definition used by the hosted agent
  requirements.txt  Hosted-agent runtime dependencies

scripts/
  setup-dev.ps1        Create local dev environment
  check.ps1            Run formatting, linting, and type checking
  upload-knowledge.ps1 Upload .knowledge/*.txt files to Foundry file search

docs/
  agent-framework-agent-with-local-tools-responses.md

azure.yaml      azd Foundry project and hosted-agent configuration
pyproject.toml  Local development dependency and tool configuration
```

## Notes

This project is a Foundry learning exercise, not a general-purpose literature
tutor. The private reading notes are deliberately artificial so retrieval can be
verified with answers that are impossible to know from the public novel alone.

Do not put secrets or sensitive personal data in `.knowledge`. The upload script
sends those files to the configured Foundry project for indexing.

The experimental GenAI tracing flag was tested and disabled because it triggered
a streaming runtime incompatibility in the current package combination.

## Third-Party Notices

This project has direct runtime dependencies on third-party Python packages,
including `agent-framework-foundry`, `agent-framework-foundry-hosting`,
`azure-ai-projects`, `azure-identity`, and `python-dotenv`. See each package's
PyPI license metadata for full license and notice terms.

## License

GNU General Public License v3.0. See the `LICENSE` file for details.
