# Homebrew Release Playbook (arj)

This checklist is used to update the Homebrew tap formula in `merenkoff/homebrew-arj` for each new `ARJ.swift` release.

## Quick Steps

```bash
# 0) Set release parameters
export VER="1.2.0"
export URL="https://github.com/merenkoff/ARJ.swift/archive/refs/tags/${VER}.tar.gz"

# 1) Compute sha256 for the new source tarball
export SHA=$(curl -sL "$URL" | shasum -a 256 | awk '{print $1}')
echo "$SHA"

# 2) Update Formula/arj.rb in homebrew-arj:
#    - url "$URL"
#    - sha256 "$SHA"

# 3) Validate formula
brew audit --strict --online merenkoff/arj/arj

# 4) Reinstall from source and run formula test
brew reinstall --build-from-source merenkoff/arj/arj
brew test merenkoff/arj/arj

# 5) Commit and push in homebrew-arj
git add Formula/arj.rb
git commit -m "arj ${VER}"
git push
```

## Pre-push Checklist

- Tag `${VER}` exists in `ARJ.swift`.
- `sha256` is computed from the exact `${VER}` tarball.
- `brew audit --strict --online` passes.
- `brew test` passes.
