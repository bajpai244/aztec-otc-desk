use crate::{
    OTCEscrowContract,
    test::utils::token::mint_to_private,
};
use token_contract::Token;
use aztec::{
    prelude::AztecAddress,
    oracle::random::random,
    protocol_types::contract_instance::ContractInstance,
    test::helpers::{
        test_environment::TestEnvironment,
        cheatcodes
    }
};
use std::test::OracleMock;

// Token metadata
pub global USDC_NAME: str<31> = "Circle USD\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n";
pub global USDC_SYMBOL: str<31> = "USDC\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n";
pub global USDC_DECIMALS: u8 = 6;

pub global WETH_NAME: str<31> = "Wrapped Ether\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n";
pub global WETH_SYMBOL: str<31> = "WETH\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n";
pub global WETH_DECIMALS: u8 = 18;

pub global USDC_ESCROW_AMOUNT: u128 = (1000 * 10.pow_32(6)) as u128;
pub global WETH_ESCROW_AMOUNT: u128 = (1 * 10.pow_32(18)) as u128;

// pub global USDC_ESCROW_AMOUNT: u128 = 1;
// pub global WETH_ESCROW_AMOUNT: u128 = 1;

// Named structs for easy readability
pub struct TestAccounts {
    minter: AztecAddress,
    seller: AztecAddress,
    buyer: AztecAddress,
    external: AztecAddress,
    escrow_secret: Field
}

pub struct TestContracts {
    usdc: AztecAddress,
    weth: AztecAddress,
    escrow: AztecAddress,
}

/**
 * Setup hook for test environment
 *
 * @param mint - if true, mint USDC to seller and WETH to buyer
 * @return
 *          - the TXE test environment context
 *          - named accounts deployed for the test
 *          - named contracts deployed for the test
 */
pub unconstrained fn setup(mint: bool) -> (
    &mut TestEnvironment,
    TestAccounts,
    TestContracts,
) {
    // setup accounts
    let (env, accounts) = setup_accounts::<4>(true);
    let mut test_accounts = TestAccounts {
        minter: accounts[0],
        seller: accounts[1],
        buyer: accounts[2],
        external: accounts[3],
        escrow_secret: 0
    };

    // deploy contracts
    let usdc = deploy_token_contract(
        env,
        test_accounts.minter,
        USDC_NAME,
        USDC_SYMBOL,
        USDC_DECIMALS
    );
    let weth = deploy_token_contract(
        env,
        test_accounts.minter,
        WETH_NAME,
        WETH_SYMBOL,
        WETH_DECIMALS
    );
    let (escrow, escrow_secret) = deploy_escrow_contract(
        env,
        test_accounts.seller,
        usdc,
        USDC_ESCROW_AMOUNT,
        weth,
        WETH_ESCROW_AMOUNT
    );
    // mint to accounts
    if (mint) {
        mint_to_private(
            env,
            usdc,
            test_accounts.minter,
            test_accounts.seller,
            USDC_ESCROW_AMOUNT
        );
        mint_to_private(
            env,
            weth,
            test_accounts.minter,
            test_accounts.buyer,
            WETH_ESCROW_AMOUNT
        );
    }
    // named contract struct 
    let test_contracts = TestContracts { usdc, weth, escrow };
    test_accounts.escrow_secret = escrow_secret;

    (env, test_accounts, test_contracts)
}

pub unconstrained fn setup_accounts<let NUM_ACCOUNTS: u32>(
    use_account_contracts: bool
) -> (&mut TestEnvironment, [AztecAddress; NUM_ACCOUNTS]) {
    // Setup env, generate keys
    let mut env = TestEnvironment::new();
    let mut accounts: [AztecAddress; NUM_ACCOUNTS]
        = [AztecAddress::zero(); NUM_ACCOUNTS];
    for i in 0..NUM_ACCOUNTS {
        let index = (i + 1) as Field;
        let mut account_address = AztecAddress::zero();
        if use_account_contracts {
            account_address = env.create_account_contract(index);
        } else {
            account_address = env.create_account(index);
        }
        accounts[i] = account_address;
    }
    (&mut env, accounts)
}

pub unconstrained fn deploy_token_contract(
    env: &mut TestEnvironment,
    owner: AztecAddress,
    name: str<31>,
    symbol: str<31>,
    decimals: u8
) -> AztecAddress {
    let initializer_call_iface = Token::interface()
        .constructor_with_minter(
            name,
            symbol,
            decimals,
            owner,
            AztecAddress::zero()
        );
    let contract_instance = env
        .deploy("../../deps/aztec-standards/@token_contract", "Token")
        .with_public_void_initializer(owner, initializer_call_iface);
    env.advance_block_by(1);

    contract_instance.to_address()
}

pub unconstrained fn deploy_escrow_contract(
    env: &mut TestEnvironment,
    owner: AztecAddress,
    sell_token_address: AztecAddress,
    sell_token_amount: u128,
    buy_token_address: AztecAddress,
    buy_token_amount: u128
) -> (AztecAddress, Field) {
    // setup keys for escrow account
    let escrow_secret = unsafe { random() };
    let escrow_contract_account = cheatcodes::add_account(escrow_secret);
    
    // do i even have to do this
    env.impersonate(owner);

    // deploy escrow contract
    let initializer_call_iface = OTCEscrowContract::interface()
        .constructor(
            sell_token_address,
            sell_token_amount,
            buy_token_address,
            buy_token_amount
        );
    let contract_instance = env
        .deploy_self_with_public_keys("OTCEscrowContract", escrow_secret)
        .with_private_initializer(owner, initializer_call_iface);
    env.advance_block_by(1);

    (contract_instance.to_address(), escrow_secret)
}