#!/bin/bash
# git submodule update --init --recursive
cd deps/aztec-standards
# aztec-nargo compile --package token_contract
aztec codegen ./target/token_contract-Token.json -o ../../packages/contracts/artifacts -f

