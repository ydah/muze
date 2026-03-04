# Releasing Muze

## 1. Validate

```bash
bundle install
bundle exec rspec
bundle exec rubocop
bundle exec yard doc
```

## 2. Update version and changelog

- Update `lib/muze/version.rb`
- Add release notes to `CHANGELOG.md`

## 3. Build and verify gem

```bash
bundle exec rake build
ls -lh pkg/
```

## 4. Commit and tag

```bash
git add .
git commit -m "release: vX.Y.Z"
git tag vX.Y.Z
```

## 5. Push

```bash
git push origin main --tags
```

## 6. Publish

```bash
gem push pkg/muze-X.Y.Z.gem
```
