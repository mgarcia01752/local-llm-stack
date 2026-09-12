# local-llm-stack

Install a local LLM and document question-answering stack on Ubuntu/Xubuntu using
Ollama and Open WebUI. The installer sets up systemd services, downloads a chat
model and an embedding model, and configures local retrieval-augmented generation
(RAG).

| Component | Role | Default |
| --- | --- | --- |
| Ollama | Runs chat and embedding models locally | localhost:11434 |
| Chat model | Generates answers | `gemma4:12b` |
| Embedding model | Converts document chunks and questions into vectors for retrieval | `nomic-embed-text` |
| Open WebUI | Chat interface, document ingestion, knowledge collections and retrieval | localhost:8080 |

RAG retrieves relevant passages from your documents and includes them in the
model's input. It does not train or fine-tune the chat model. Open WebUI provides
this workflow already; this single-host setup uses its built-in storage without
provisioning a separate vector database service.
[Open WebUI RAG overview](https://docs.openwebui.com/features/chat-conversations/rag/).

## Install

Supported systems: Ubuntu/Xubuntu 22.04 and 24.04 with systemd, sudo, and an
installed Python 3.11 or 3.12 with matching venv support. Downloading packages and
models requires internet access. Available RAM, disk space and GPU capacity must
accommodate both models; inference speed depends on your hardware.

On Ubuntu 24.04, from the repository checkout:

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-venv
./scripts/install-local-llm.sh --help
./scripts/install-local-llm.sh
```

On Ubuntu 22.04, first install a supported Python independently of the system
interpreter, then select it with `PYTHON_BIN=python3.11`. See the
[installation guide](docs/install-local-llm.md) for prerequisites and configuration.

Open http://localhost:8080, create your administrator account, and select
`gemma4:12b` for chat. The service listens only on localhost by default.

To select different locally available Ollama models:

```bash
MODEL=gemma4:12b EMBEDDING_MODEL=nomic-embed-text ./scripts/install-local-llm.sh
```

The embedding model is separate from the chat model and must support embeddings.
The default is an [Ollama embedding model](https://ollama.com/library/nomic-embed-text).

## Ask questions about your documents (RAG)

1. In Open WebUI, open **Settings > Admin > Documents**. Verify that the embedding
   engine is **Ollama**, the model is **nomic-embed-text**, and the Ollama embedding
   URL is `http://127.0.0.1:11434`. Save any changes before uploading documents.
2. Open **Workspace > Knowledge**, create a collection, and upload your documents.
   Start with plain text or a PDF containing selectable text. Wait for processing
   to finish, and check that extracted text contains the expected content.
3. Start a chat with your local chat model. Use **#** in the chat input to attach
   the knowledge collection. Select **Focused Retrieval (RAG)** where offered.
4. Ask a specific question and request supporting quotations or source references.
   Open the returned citations and compare them with the original document.

For a one-off question, attach a file directly to a chat. For a reusable assistant,
associate a knowledge collection with a model in **Workspace > Models**.
[Knowledge workflow](https://docs.openwebui.com/features/workspace/knowledge/),
[basic document chat](https://docs.openwebui.com/getting-started/essentials/).

### Verify retrieval

Create `rag-check.txt` containing a fact invented for this test:

```text
The calibration code for Project Cedar is violet-7319.
```

Upload it, attach its collection to a new chat, and ask:
“What is Project Cedar's calibration code? Quote the supporting source.”
Check that the answer includes `violet-7319` and points to the uploaded text.
Also ask for an absent fact, such as the project's budget; the answer should say
that the supplied documents do not provide it. This is a manual acceptance check,
not a guarantee that every future answer will be grounded correctly.

### Existing installations and troubleshooting

- Saved Admin UI settings can override the installer's environment defaults.
  Rerunning the installer does not forcibly reset them. Check the embedding
  configuration explicitly. [Configuration persistence](https://docs.openwebui.com/reference/env-configuration/).
- After changing the embedding model, reindex existing knowledge documents in
  **Admin > Documents**. Old and new embeddings are not interchangeable.
  [Reindexing guidance](https://docs.openwebui.com/features/chat-conversations/rag/).
- For empty or incomplete results, inspect extracted text first. Scanned PDFs need
  OCR; complex layouts may need a different extraction engine. OCR services are
  not installed by this repository. [Extraction troubleshooting](https://docs.openwebui.com/troubleshooting/rag/).
- If a model does not reliably call knowledge tools, disable native function
  calling for that model to use automatic RAG injection.
  [Knowledge retrieval modes](https://docs.openwebui.com/features/workspace/knowledge/).
- If passages are truncated, adjust context capacity and retrieval settings to
  fit your model and hardware. Larger context windows consume more memory.

## Local data and network behavior

Chat generation and configured RAG embeddings use the local Ollama service.
Open WebUI data is kept under `$HOME/open-webui/data`, with its persistent secret
key in `$HOME/open-webui`. Preserve both when backing up the installation; stop
Open WebUI before taking a simple filesystem copy for consistency.

“Local” does not mean this installer creates an air-gapped environment. Initial
installation downloads dependencies and models, and optional WebUI features may
contact external services or download additional resources. Keep cloud providers,
web search and external extraction services disabled for a local document flow.
Fully offline operation requires separately preparing and testing all needed
assets; this installer does not enforce network isolation.

## Git helpers

Review all changes, including new files, before saving. The save helper stages all
tracked changes and untracked files that are not ignored, then creates a commit:

```bash
git status --short
git diff
tools/git/git-save.sh --commit-msg "Feature: Add local RAG setup"
```

Push a committed, clean `main` or `master` branch to `origin`:

```bash
tools/git/git-push.sh
```

The push helper rejects dirty working trees, other branches, and history that is
behind or diverged from the remote. It never force-pushes. Both helpers accept
`--help` and locate the repository relative to their own script paths.
