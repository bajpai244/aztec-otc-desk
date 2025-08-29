use token_contract::Token;
use aztec::{
    prelude::AztecAddress,
    oracle::execution::get_contract_address,
    test::helpers::{
        test_environment::TestEnvironment,
        cheatcodes,
        authwit as authwit_cheatcodes
    }
};

pub unconstrained fn mint_to_private(
    env: &mut TestEnvironment,
    token_address: AztecAddress,
    minter: AztecAddress,
    recipient: AztecAddress,
    amount: u128
) {
    env.impersonate(minter);
    Token::at(token_address)
        .mint_to_private(minter, recipient, amount)
        .call(&mut env.private()
    ); 
    env.advance_block_by(1);
}

pub unconstrained fn get_balance_private(
    token_address: AztecAddress,
    account_address: AztecAddress,
) -> u128 {
    let current_contract_address = get_contract_address();
    cheatcodes::set_contract_address(token_address);
    
    let amount = Token::balance_of_private(account_address);
    cheatcodes::set_contract_address(current_contract_address);
    amount
}

pub unconstrained fn expect_private_balance(
    token_address: AztecAddress,
    account_address: AztecAddress,
    expected_balance: u128
) {
    let actual_balance = get_balance_private(token_address, account_address);
    assert_eq(actual_balance, expected_balance, "Unexpected private balance");
}

/**
 * Adds a private authwit for a private token transfer
 *
 * @param token_address - the address of the token contract being called
 * @param caller - the address of the contract consuming the authwit/ recipient
 *                 you may need an additional recipient param for other usecases
 * @param from - the address holding tokens to transfer
 * @param amount - the amount of tokens to transfer
 * @param nonce - the authwit nonce
 */
pub unconstrained fn private_transfer_authwit(
    token_address: AztecAddress,
    caller: AztecAddress,
    from: AztecAddress,
    amount: u128,
    nonce: Field
) {
    let call_iface = Token::at(token_address)
        .transfer_private_to_private(from, caller, amount, nonce);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        from,
        caller,
        call_iface
    );
}

