#!/bin/bash

# if -r flag is provided, skip download of submodule and only recompile
SKIP_SUBMODULES=false
while getopts "r" opt; do
  case $opt in
    r)
      SKIP_SUBMODULES=true
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

if [ "$SKIP_SUBMODULES" = false ]; then
    # Only run submodule update if -r flag is not provided
    git submodule update --init --recursive
else
    # Remove target if rebuilding
    rm -rf deps/aztec-standards/target
fi

# compile token contract
cd deps/aztec-standards
aztec-nargo compile --package token_contract

# generate TypeScript bindings
aztec codegen ./target/token_contract-Token.json \
    -o ../../packages/contracts/artifacts -f

# add the artifact to the target file for txe
if [ ! -d "../../packages/contracts/target" ]; then
    mkdir ../../packages/contracts/target
fi
cp ./target/token_contract-Token.json ../../packages/contracts/target

