#!/bin/bash
# Pre-commit hook: refuse commits that change DEVELOPMENT_TEAM in the Xcode project.
# To install: cp scripts/check-team-id.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
#
# build.sh passes your own team at build time (FLUIDVOICE_DEVELOPMENT_TEAM, or the
# team of your Apple Development certificate), so the value in the project never
# needs to change. Setting a team in Xcode's Signing pane writes it into
# project.pbxproj; this hook keeps that edit out of a commit.

if git diff --cached --name-only | grep -q "project.pbxproj"; then
  if git diff --cached Fluid.xcodeproj/project.pbxproj | grep -q "^[+-].*DEVELOPMENT_TEAM"; then
    echo "ERROR: DEVELOPMENT_TEAM changes detected in Fluid.xcodeproj/project.pbxproj"
    echo ""
    echo "Don't commit a signing team change. build.sh passes your team at build time."
    echo ""
    echo "To fix:"
    echo "  1. Unstage the file: git reset HEAD Fluid.xcodeproj/project.pbxproj"
    echo "  2. Undo the team change (git checkout -p Fluid.xcodeproj/project.pbxproj)"
    echo "  3. Stage only your intended changes"
    echo ""
    echo "To override this check (only if you mean to change it): git commit --no-verify"
    exit 1
  fi
fi

exit 0
