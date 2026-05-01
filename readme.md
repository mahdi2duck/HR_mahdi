COMMANDS:
act workflow_dispatch \
  -W .github/workflows/hermes-rclone.yml \
  --secret-file .secrets \
  -P ubuntu-latest=ghcr.io/catthehacker/ubuntu:act-latest
