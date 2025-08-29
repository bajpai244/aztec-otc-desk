use aztec::{
    oracle::{
        random::random,
        execution::get_contract_address,
    },
    prelude::AztecAddress,
    protocol_types::contract_instance::ContractInstance,
    test::helpers::{
        test_environment::TestEnvironment,
        cheatcodes,
        authwit as authwit_cheatcodes
    }
};
use crate::{
    OTCEscrowContract,
    types::definition_note::DefinitionNote,
    test::utils::token::{private_transfer_authwit, mint_to_private}
};

pub unconstrained fn get_escrow_definition(
    escrow_address: AztecAddress
) -> DefinitionNote {
    // set cheatcode address to escrow
    let current_contract_address = get_contract_address();
    cheatcodes::set_contract_address(escrow_address);

    // read definition
    let definition = OTCEscrowContract::get_definition();

    // set cheatcode address back to original
    cheatcodes::set_contract_address(current_contract_address);

    definition
}

pub unconstrained fn deposit_to_escrow(
    env: &mut TestEnvironment,
    seller_address: AztecAddress,
    escrow_address: AztecAddress,
    sell_token_address: AztecAddress,
    sell_token_amount: u128,
    malicious_authwit: bool
) {
    // add transfer authwit
    let mut nonce = unsafe { random() };
    private_transfer_authwit(
        sell_token_address,
        escrow_address,
        seller_address,
        sell_token_amount,
        nonce
    );
    
    // increment nonce to make authwit invalid
    if malicious_authwit {
        nonce = nonce + 1;
    }

    // call deposit
    env.impersonate(seller_address);
    OTCEscrowContract::at(escrow_address)
        .deposit_tokens(nonce)
        .call(&mut env.private());
    
    // advance block
    env.advance_block_by(1);
}

pub unconstrained fn fill_otc_order(
    env: &mut TestEnvironment,
    buyer_address: AztecAddress,
    escrow_address: AztecAddress,
    buy_token_address: AztecAddress,
    buy_token_amount: u128,
    malicious_authwit: bool
) {
    // add transfer authwit
    let mut nonce = unsafe { random() };
    private_transfer_authwit(
        buy_token_address,
        escrow_address,
        buyer_address,
        buy_token_amount,
        nonce
    );

    // increment nonce to make authwit invalid
    if malicious_authwit {
        nonce = nonce + 1;
    }

    // call fulfill
    env.impersonate(buyer_address);
    OTCEscrowContract::at(escrow_address)
        .fill_order(nonce)
        .call(&mut env.private());

    // advance block
    env.advance_block_by(1);
}
