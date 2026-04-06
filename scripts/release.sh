#!/bin/bash
set -euo pipefail

# Release script for yswift
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 0.3.0

VERSION="${1:-}"

if [ -z "$VERSION" ]; then
    echo "Usage: ./scripts/release.sh <version>"
    echo "Example: ./scripts/release.sh 0.3.0"
    exit 1
fi

# Get the repo owner/name from git remote
REPO_URL=$(git remote get-url origin)
if [[ "$REPO_URL" == git@github.com:* ]]; then
    REPO=$(echo "$REPO_URL" | sed 's/git@github.com://' | sed 's/\.git$//')
elif [[ "$REPO_URL" == https://github.com/* ]]; then
    REPO=$(echo "$REPO_URL" | sed 's|https://github.com/||' | sed 's/\.git$//')
else
    echo "Error: Could not parse GitHub repo from remote URL: $REPO_URL"
    exit 1
fi

echo "📦 Releasing $REPO version $VERSION"
echo ""

# Check for uncommitted changes
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Error: You have uncommitted changes. Please commit or stash them first."
    exit 1
fi

# Check gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "Error: gh CLI is not installed. Install it with: brew install gh"
    exit 1
fi

# Note: Skipping auth check since gh may be wrapped by 1Password or similar

# Step 1: Build xcframework
echo "🔨 Building xcframework..."
./scripts/build-xcframework.sh

# Step 2: Extract checksum
CHECKSUM=$(openssl dgst -sha256 lib/yniffiFFI.xcframework.zip | awk '{print $2}')
echo "✅ Checksum: $CHECKSUM"

# Step 3: Update Package.swift
echo "📝 Updating Package.swift..."
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$VERSION/yniffiFFI.xcframework.zip"

# Update the URL and checksum in Package.swift
sed -i '' "s|url: \"https://github.com/.*/releases/download/.*/yniffiFFI.xcframework.zip\"|url: \"$DOWNLOAD_URL\"|" Package.swift
sed -i '' "s|checksum: \"[a-f0-9]*\"|checksum: \"$CHECKSUM\"|" Package.swift

echo "   URL: $DOWNLOAD_URL"
echo "   Checksum: $CHECKSUM"

# Step 4: Commit
echo "📝 Committing changes..."
git add Package.swift lib/swift/scaffold/
git commit -m "Release $VERSION"

# Step 5: Tag
echo "🏷️  Tagging $VERSION..."
git tag "$VERSION"

# Step 6: Push
echo "🚀 Pushing to GitHub..."
git push origin main --tags

# Step 7: Create GitHub release (run through login shell for 1Password integration)
echo "📦 Creating GitHub release..."
$SHELL -l -i -c "gh release create '$VERSION' --repo '$REPO' --title '$VERSION' --notes 'Release $VERSION' lib/yniffiFFI.xcframework.zip"

echo ""
echo "✅ Released $VERSION!"
echo "   https://github.com/$REPO/releases/tag/$VERSION"
