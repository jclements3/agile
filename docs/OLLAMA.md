# Ollama and Qwen3-4B-SysMLv2: a local SysML v2 assistant

A small language model that runs on the laptop itself, tuned to turn plain-language requirements into SysML v2
text. It is **optional**: nothing in the kit needs it, and every line it writes is a draft that the kit's own
checkers must pass before it is committed.

## What it is

| | |
|---|---|
| Model | `Babitdor/Qwen3-4B-SysMLv2` on the Ollama registry ([model page](https://ollama.com/Babitdor/Qwen3-4B-SysMLv2)) |
| Publisher | a single community user (`Babitdor`), not Qwen/Alibaba and not Ollama |
| Base | Qwen3, 4 billion parameters, fine-tuned for SysML v2 textual models |
| What it claims | natural-language requirements -> SysML v2 text; 2-3 design alternatives per prompt |
| Download | one tag, `latest`: 2.5 GB, 40K-token context, digest `b8a8d69fdeec` |
| Laptop | runs on the CPU alone; 8-16 GB of RAM is enough (the model takes about 3-4 GB while it runs) |
| License | **not stated** on the model page |
| Training data | **not stated** |
| Status (2026-10-05) | last updated about 11 months earlier; about 45 downloads |

That last block matters on a government laptop: the provenance, license and training data are unknown, so treat
it as unvetted third-party software and get it approved the way any other download is (next section).

## Before you install: approvals

- [ ] **Software intake.** Ollama (an executable) and the model (a 2.5 GB data file) both need the program's
      approval to be installed. Ask through the normal software request, with the facts above.
- [ ] **License.** The model page states none. Ask whoever approves software whether that is acceptable, or
      whether only models with a stated license (for example base Qwen3, Apache-2.0) are allowed.
- [ ] **Data handling.** Ollama runs locally; prompts and answers stay on the laptop. Even so, only give it
      information your marking rules allow on that machine, the same rule `lib/Ai.pm` applies to any AI service.
- [ ] **Network.** Downloading needs the internet. If the work laptop is restricted, bring the model in by the
      approved offline route ("Getting the model without internet" below).

## Install Ollama (Windows)

Requirements (from [Ollama's Windows docs](https://docs.ollama.com/windows)): Windows 10 22H2 or newer; about 4 GB
of disk for Ollama itself plus 2.5 GB for this model. A GPU is optional (NVIDIA driver 551.61+ or AMD); without one
it runs on the CPU, more slowly.

1. Download `OllamaSetup.exe` from <https://ollama.com/download>.
2. Run it. It **does not need Administrator**: it installs into your home folder and adds a tray icon.
3. Check it from Git Bash:

   ```bash
   ollama --version
   curl -s http://localhost:11434/api/version     # the local service answers on port 11434
   ```

No installer allowed? Ollama also ships a standalone `ollama-windows-amd64.zip` (CLI only): unzip it to a folder
in your home directory, run `ollama serve` in one Git Bash window and use `ollama` from another.

Models go to `C:\Users\<you>\.ollama\models`. To keep them elsewhere (another drive, outside OneDrive), set the
user environment variable `OLLAMA_MODELS` (Settings -> "Edit environment variables for your account"), then quit
and restart Ollama.

## Get the model

```bash
ollama pull Babitdor/Qwen3-4B-SysMLv2      # 2.5 GB, once
ollama list                                # NAME ... ID b8a8d69fdeec ... SIZE 2.5 GB
ollama show Babitdor/Qwen3-4B-SysMLv2      # parameters, context length, template
```

Check that the ID in `ollama list` starts `b8a8d69fdeec`. If it does not, the model on the registry has changed
since this doc was written: stop and read the model page again before using it.

### Getting the model without internet

1. On an approved machine with internet, install Ollama and `ollama pull Babitdor/Qwen3-4B-SysMLv2`.
2. Copy the whole `models` folder (`%USERPROFILE%\.ollama\models`, with its `manifests` and `blobs`
   subfolders) to approved removable media, and record a checksum of the archive:

   ```bash
   cd ~/.ollama && tar -cf qwen3-4b-sysmlv2.tar models && sha256sum qwen3-4b-sysmlv2.tar
   ```

3. On the work laptop, check the checksum, unpack it into `%USERPROFILE%\.ollama\` (or wherever
   `OLLAMA_MODELS` points), restart Ollama, and run `ollama list` to confirm the ID above.

## Use it

```bash
ollama run Babitdor/Qwen3-4B-SysMLv2
>>> Write SysML v2 text for a seeker part def with an output port carrying a track,
... and a requirement with doorsId SYS-101 that it tracks the threat. Only the SysML v2 text.
```

Qwen3 models can print a `<think>...</think>` section before the answer. Ignore it; recent Ollama versions can turn
it off with `ollama run --think=false ...` or the `/set nothink` command inside a session.

Habits that make a small model useful:

- Ask for **one thing at a time**: a part def, a port def, a requirement, a connection. Small models drift on
  long prompts.
- Paste the **context it must fit**: the existing part def or the package's imports, so it reuses your names.
- Ask for **text only**, then check it (next section). It is a fast first draft, never the answer.
- Use it on the converter's `// TODO` lines: paste the TODO and the v1 element's description, ask for the v2
  equivalent, check, keep or rewrite.

## Check everything it writes

The model has no idea whether its output parses. The kit does:

```bash
ollama run Babitdor/Qwen3-4B-SysMLv2 "..." > draft.sysml
perl tools/sysml/sysml.pl check draft.sysml                  # the official SysML v2 grammar
perl tools/sysml/model.pl lint                                # names, types, imports, duplicates, in the model
```

Only text that passes both goes into `model/`, through the same branch, review and gate as everything else. The
grammar check catches syntax; lint catches names that resolve to nothing. Neither proves the model is *right*:
you are still the engineer of record.

From Vim, the same loop without leaving the editor:

```vim
:r !ollama run Babitdor/Qwen3-4B-SysMLv2 "SysML v2 text only: a port def TrackPort with an out attribute track : String"
\mx      " grammar-check this file
\ml      " lint the model
```

## Hook it into the kit's AI summary (optional)

`lib/Ai.pm` already speaks the OpenAI-style chat API that Ollama serves, using the `curl` in Git for Windows. In a
project's `scrum.conf`:

```
ai_backend = curl
ai_url     = http://localhost:11434/v1/chat/completions
ai_model   = Babitdor/Qwen3-4B-SysMLv2
```

Then `perl bin/daily.pl ai` (Vim: `:SAi`) sends the day's stand-up digest to the local model instead of a cloud
service. This model was tuned for SysML, not status writing, so a general model (for example `ollama pull qwen3:4b`,
if approved) may write better summaries; `ai_model` picks which. `ai_backend = paste` (the default) needs no AI at
all.

## Troubleshooting and removal

| Symptom | Cause and fix |
|---|---|
| `ollama: command not found` in Git Bash | open a new Git Bash after installing; or use the full path `~/AppData/Local/Programs/Ollama/ollama.exe` |
| `could not connect` / port 11434 refused | the service is not running: start Ollama from the Start menu (or `ollama serve`) |
| very slow answers | normal on CPU only: a few words a second. Close other large programs; keep prompts short |
| out of memory | the laptop has under 8 GB free: close programs, or use a smaller model |
| `ollama list` shows another ID | the registry model changed: re-read the model page and re-approve before use |

To remove it: `ollama rm Babitdor/Qwen3-4B-SysMLv2`, then uninstall Ollama from Settings -> "Add or remove
programs". If you moved the models with `OLLAMA_MODELS`, delete that folder yourself: the uninstaller does not.

## Sources

- Model page: <https://ollama.com/Babitdor/Qwen3-4B-SysMLv2> and its tags: <https://ollama.com/Babitdor/Qwen3-4B-SysMLv2/tags>
- Ollama on Windows: <https://docs.ollama.com/windows>
- Ollama download: <https://ollama.com/download>
