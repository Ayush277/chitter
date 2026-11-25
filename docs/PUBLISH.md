# Publishing to GitHub (account: Ayush277)

The repository is ready: history is clean, commits are authored as `Ayush Kumar <Ayush277@users.noreply.github.com>`, and no private data or large generated files are tracked.

```bash
# 1. one-time: install the GitHub CLI and log in (opens your browser; you approve it, no token to paste)
brew install gh
gh auth login --web --git-protocol https

# 2. create the PUBLIC repo, set its description and topics, and push everything with the v0.1.0 tag
cd ~/chitter
gh repo create Ayush277/chitter --public --source=. --remote=origin --push \
  --description "Free, local-first live subtitles, voice-over and AI meeting notes for calls. Mac app + Chrome extension." \
  --homepage "https://ayush277.github.io/chitter/"
git push origin v0.1.0
gh repo edit Ayush277/chitter --add-topic swift --add-topic macos --add-topic chrome-extension --add-topic speech-recognition \
  --add-topic live-captions --add-topic translation --add-topic on-device-ai --add-topic privacy --add-topic accessibility --add-topic meeting-notes

# 3. publish the website (GitHub Pages, deployed by docs/github-workflows/pages.yml)
gh api -X POST repos/Ayush277/chitter/pages -f build_type=workflow

# 4. star it (so it is marked), then pin it on your profile (see below)
gh api -X PUT user/starred/Ayush277/chitter
```

**Pinning to the top of your profile** can only be done in the web UI: open https://github.com/Ayush277, click **Customize your pins**, tick `chitter`, and save.

**Releases (optional):** `scripts/package.sh` builds the DMG, ZIP and `checksums.txt`; then
`gh release create v0.1.0 dist/Chitter-0.1.0.dmg dist/Chitter-0.1.0.zip dist/checksums.txt --title "Chitter 0.1.0" --notes-file CHANGELOG.md`.
`scripts/release.sh Ayush277` fills the Homebrew cask with the real checksum.

The app is not notarised; see the README for first-launch steps.

## CI and Pages workflows
The GitHub Actions files (`ci.yml`, `pages.yml`, `release.yml`) are stored in `docs/github-workflows/` so the first push needs no special token permission. To switch them on, run `gh auth refresh -s workflow`, then `mkdir -p .github && git mv docs/github-workflows .github/workflows`, commit and push.
