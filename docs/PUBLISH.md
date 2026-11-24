# Publishing (the `gh` CLI wasn't available when v0.1.0 was built)
Replace `OWNER` with your GitHub user.
```bash
brew install gh && gh auth login
cd ~/chitter
sed -i '' 's/OWNER/YOUR_USER/g' site/index.html site/robots.txt site/sitemap.xml
gh repo create chitter --public --source=. --push
git push origin v0.1.0
gh api -X POST repos/YOUR_USER/chitter/pages -f build_type=workflow     # enable Pages (workflow deploy)
scripts/package.sh                                                      # DMG, ZIP, checksums.txt in dist/
gh release create v0.1.0 dist/Chitter-0.1.0.dmg dist/Chitter-0.1.0.zip dist/checksums.txt --title "Chitter 0.1.0" --notes-file CHANGELOG.md
scripts/release.sh YOUR_USER                                            # writes homebrew/chitter.rb with the real sha256
gh repo create homebrew-chitter --public && git -C . subtree split -P homebrew -b tap >/dev/null   # or copy homebrew/chitter.rb to Casks/chitter.rb in the tap repo
```
Then users run `brew install --cask YOUR_USER/chitter/chitter`.
The app is not notarised; see the README for first-launch steps.
