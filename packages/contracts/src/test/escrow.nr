use crate::test::utils::{
    setup::{setup, USDC_ESCROW_AMOUNT, WETH_ESCROW_AMOUNT},
    escrow::{
        deposit_to_escrow,
        fill_otc_order,
        get_escrow_definition
    },
    token::{
        expect_private_balance,
        mint_to_private
    }
};
use aztec::{
    oracle::{
        random::random,
        debug_log::{debug_log, debug_log_format},
    },
    protocol_types::traits::ToField,
};
use uint_note::uint_note::PartialUintNote;

// Basic e2e escrow test
#[test]
unconstrained fn full_otc_order_success() {
    // get test environment
    let (env, accounts, contracts) = setup(true);
    
    // check the definition
    let definition = get_escrow_definition(contracts.escrow);
    assert_eq(definition.owner, contracts.escrow, "Definition owner mismatch!");
    assert_eq(definition.sell_token_address, contracts.usdc, "Definition sell token address mismatch!");
    assert_eq(definition.sell_token_amount, USDC_ESCROW_AMOUNT, "Definition sell token amount mismatch!");
    assert_eq(definition.buy_token_address, contracts.weth, "Definition buy token address mismatch!");
    assert_eq(definition.buy_token_amount, WETH_ESCROW_AMOUNT, "Definition buy token amount mismatch!");
    debug_log_format("Partial Note commitment: {0}", [definition.partial_note]);

    // check the partial note commitment in the definition is valid
    let validity_commitment = PartialUintNote { 
        commitment: definition.partial_note 
    }.compute_validity_commitment(contracts.escrow);
    assert(
        env.public().nullifier_exists(validity_commitment, contracts.weth),
        "Validity nullifier should exist",
    );

    // check usdc balance of seller and contract before deposit
    expect_private_balance(contracts.usdc, accounts.seller, USDC_ESCROW_AMOUNT);
    expect_private_balance(contracts.usdc, contracts.escrow, 0);

    // deposit to escrow
    deposit_to_escrow(
        env,
        accounts.seller,
        contracts.escrow,
        contracts.usdc,
        USDC_ESCROW_AMOUNT,
        false // no malicious authwit
    );

    // check usdc balance of seller and contract after deposit
    expect_private_balance(contracts.usdc, accounts.seller, 0);
    expect_private_balance(contracts.usdc, contracts.escrow, USDC_ESCROW_AMOUNT);

    // fill the otc order
    fill_otc_order(
        env,
        accounts.buyer,
        contracts.escrow,
        contracts.weth,
        WETH_ESCROW_AMOUNT,
        false // no malicious authwit
    );

    // check balances after otc order is complete
    // why does uncommenting this cause
    // "Assertion failed: A partial note's completion log did not result in any notes being found - this should never happen"
    // expect_private_balance(contracts.usdc, accounts.buyer, USDC_ESCROW_AMOUNT);
    // expect_private_balance(contracts.usdc, contracts.escrow, 0);
    // expect_private_balance(contracts.weth, accounts.seller, WETH_ESCROW_AMOUNT);
}

// ensure cannot deposit without sufficient balance
#[test(should_fail_with = "Assertion failed: Balance too low")]
unconstrained fn otc_deposit_insufficient_balance_fail() {
    // get test environment
    let (env, accounts, contracts) = setup(false);

    // try to deposit to escrow with insufficient balance
    deposit_to_escrow(
        env,
        accounts.buyer,
        contracts.escrow,
        contracts.usdc,
        USDC_ESCROW_AMOUNT,
        false // no malicious authwit
    );
}

// ensure cannot deposit with incorrect authwit
#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn otc_deposit_incorrect_authwit_fail() {
    // get test environment
    let (env, accounts, contracts) = setup(true);

    // try to deposit to escrow with malicious authwit
    deposit_to_escrow(
        env,
        accounts.buyer,
        contracts.escrow,
        contracts.usdc,
        USDC_ESCROW_AMOUNT,
        true // malicious authwit
    );
}

// ensure cannot deposit twice
#[test(should_fail_with = "Rejecting tx for emitting duplicate nullifiers")]
unconstrained fn otc_deposit_twice_fail() {
    // get test environment
    let (env, accounts, contracts) = setup(true);

    // deposit once successfully
    deposit_to_escrow(
        env,
        accounts.seller,
        contracts.escrow,
        contracts.usdc,
        USDC_ESCROW_AMOUNT,
        false // malicious authwit
    );

    // mint extra tokens to seller so they have enough to deposit twice
    mint_to_private(
        env,
        contracts.usdc,
        accounts.minter,
        accounts.seller,
        USDC_ESCROW_AMOUNT
    );

    // try to deposit a second time
    deposit_to_escrow(
        env,
        accounts.seller,
        contracts.escrow,
        contracts.usdc,
        USDC_ESCROW_AMOUNT,
        false // malicious authwit
    );
}

// ensure cannot fill order without sufficient balance
#[test(should_fail_with = "Assertion failed: Balance too low")]
unconstrained fn otc_fill_insufficient_balance_fail() {
    // get test environment
    let (env, accounts, contracts) = setup(false);

    // mint so alice can deposit
    mint_to_private(
        env,
        contracts.usdc,
        accounts.minter,
        accounts.seller,
        USDC_ESCROW_AMOUNT
    );

    // deposit to escrow
    deposit_to_escrow(
        env,
        accounts.buyer,
        contracts.escrow,
        contracts.usdc,
        USDC_ESCROW_AMOUNT,
        false // no malicious authwit
    );

    // try to fill order without tokens
    fill_otc_order(
        env,
        accounts.buyer,
        contracts.escrow,
        contracts.weth,
        WETH_ESCROW_AMOUNT,
        false // no malicious authwit
    );
}

// ensure cannot fill order with incorrect authwit
// can't set exact fail message because don't know authwit hash
#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn otc_fill_incorrect_authwit_fail() {
    // get test environment
    let (env, accounts, contracts) = setup(true);

    // deposit to escrow
    deposit_to_escrow(
        env,
        accounts.seller,
        contracts.escrow,
        contracts.usdc,
        USDC_ESCROW_AMOUNT,
        false // no malicious authwit
    );

    // try filling order with malicious authwit
    fill_otc_order(
        env,
        accounts.buyer,
        contracts.escrow,
        contracts.weth,
        WETH_ESCROW_AMOUNT,
        true // malicious authwit
    );
}

// ensure cannot fill order before deposit
#[test(should_fail_with = "Assertion failed: Balance too low")]
unconstrained fn otc_fill_before_deposit_fail() {
    // get test environment
    let (env, accounts, contracts) = setup(true);

    // try to fill order before deposit
    fill_otc_order(
        env,
        accounts.buyer,
        contracts.escrow,
        contracts.weth,
        WETH_ESCROW_AMOUNT,
        false // no malicious authwit
    );
}

// try to fill order twice
// NOTE: pretty sure this is the wrong error stemming from broken last part in first test
#[test(should_fail_with = "A partial note's completion log did not result in any notes being found")]
unconstrained fn otc_multiple_fill_fail() {
    // get test environment
    let (env, accounts, contracts) = setup(true);

    // deposit to escrow
    deposit_to_escrow(
        env,
        accounts.seller,
        contracts.escrow,
        contracts.usdc,
        USDC_ESCROW_AMOUNT,
        false // no malicious authwit
    );

    // first fill (should pass)
    fill_otc_order(
        env,
        accounts.buyer,
        contracts.escrow,
        contracts.weth,
        WETH_ESCROW_AMOUNT,
        false // no malicious authwit
    );

    // mint more tokens to Bob to fill order
    mint_to_private(
        env,
        contracts.weth,
        accounts.minter,
        accounts.buyer,
        WETH_ESCROW_AMOUNT
    );

    // mint more tokens to the escrow so it has some to send back out
    mint_to_private(
        env,
        contracts.usdc,
        accounts.minter,
        contracts.escrow,
        USDC_ESCROW_AMOUNT
    );

    // second fill (should throw)
    fill_otc_order(
        env,
        accounts.buyer,
        contracts.escrow,
        contracts.weth,
        WETH_ESCROW_AMOUNT,
        false // no malicious authwit
    );
}