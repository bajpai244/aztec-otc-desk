import {
    AccountWallet,
    CompleteAddress,
    PXE,
    AccountWalletWithSecretKey,
    Fr,
    L1FeeJuicePortalManager,
    FeeJuicePaymentMethodWithClaim,
} from "@aztec/aztec.js";
import { getInitialTestAccountsWallets } from "@aztec/accounts/testing";
import {
    deployEscrowContract,
    setupSandbox,
    deployTokenContractWithMinter,
    wad,
    depositToEscrow,
    createPXE,
    getFeeJuicePortalManager,
    TOKEN_METADATA,
    fillOTCOrder
} from "./utils/index.js";
import {
    OTCEscrowContractContract as OTCEscrowContract,
} from "../../artifacts/OTCEscrowContract.js";

import {
    TokenContract,
} from "../../artifacts/Token.js";
import { getSchnorrAccount } from "@aztec/accounts/schnorr";
import { deriveSigningKey } from "@aztec/stdlib/keys";

describe("Private Transfer Demo Test", () => {
    let pxe: PXE[];
    let wallets: AccountWalletWithSecretKey[] = [];

    let minter: AccountWallet;
    let alice: AccountWallet;
    let bob: AccountWallet;
    let charlie: AccountWallet;

    let escrowKey: Fr;

    let escrow: OTCEscrowContract;
    let usdc: TokenContract;
    let weth: TokenContract;

    let feeJuicePortalManager: L1FeeJuicePortalManager;

    beforeAll(async () => {
        // setup PXE
        pxe = await Promise.all([createPXE(), createPXE(1)]);

        console.log("PXE Setup")
        // get PXE1 accounts
        wallets = await getInitialTestAccountsWallets(pxe[0]);
        minter = wallets[0];
        alice = wallets[1];
        charlie = wallets[2];
        console.log("Got test accounts");

        // deploy PXE2 account
        const bobKey = Fr.random();
        const bobAccount = await getSchnorrAccount(pxe[1], bobKey, deriveSigningKey(bobKey), Fr.random());
        bob = await bobAccount.getWallet();
        feeJuicePortalManager = await getFeeJuicePortalManager(pxe[1]);
        const claim = await feeJuicePortalManager.bridgeTokensPublic(
            bob.getAddress(),
            wad(1n),
            true
        );
        console.log("Prepared bob fee juice claim");
        // must allow two transactions to pass before claiming

        // deploy token contract
        usdc = await deployTokenContractWithMinter(TOKEN_METADATA.usdc, minter);
        console.log(`Deployed USDC token contract to ${usdc.address}`);
        weth = await deployTokenContractWithMinter(TOKEN_METADATA.weth, minter);
        console.log(`Deployed WETH token contract to ${weth.address}`);

        // claim fee juice for bob and deploy
        const claimAndPay = new FeeJuicePaymentMethodWithClaim(bob, claim);
        await bobAccount.deploy({ fee: { paymentMethod: claimAndPay } }).wait();
        await pxe[0].registerSender(bob.getAddress());
        await pxe[1].registerSender(alice.getAddress());
        await pxe[1].registerContract(usdc);
        await pxe[1].registerContract(weth);
        console.log("Deployed new account for bob");

        // mint tokens
        // FOR SOME REASON MINTING TOKENS TO BOB DOESN"T WORK?
        // BUT MINTING TO ALICE THEN SENDING FROM BOB WORKS? OK THEN
        // await weth
        //     .withWallet(minter)
        //     .methods.mint_to_private(
        //         minter.getAddress(),
        //         bob.getAddress(),
        //         wad(4n, 18n)
        //     )
        //     .send()
        //     .wait();

        await weth
            .withWallet(minter)
            .methods.mint_to_private(
                minter.getAddress(),
                alice.getAddress(),
                wad(4n)
            )
            .send()
            .wait();

        await weth.withWallet(alice)
            .methods.transfer_private_to_private(
                alice.getAddress(),
                bob.getAddress(),
                wad(4n),
                0
            ).send().wait();

        await usdc
            .withWallet(minter)
            .methods.mint_to_private(
                minter.getAddress(),
                alice.getAddress(),
                wad(10000n, 6n)
            )
            .send()
            .wait();
        console.log("Minted tokens to recipients")
    });

    test("check escrow key leaking", async () => {
        // deploy new escrow instance
        ({ contract: escrow, secretKey: escrowKey } = await deployEscrowContract(
            pxe[0],
            alice,
            usdc.address,
            wad(1000n, 6n),
            weth.address,
            wad(1n),
        ));

        // Check Alice Escrow
        const aliceDefinition = await escrow
            .withWallet(alice)
            .methods.get_definition()
            .simulate();
        // expect(aliceDefinition.owner).toEqual(escrow.address.toBigInt());
        expect(aliceDefinition.owner).not.toEqual(0n);


        // check if maker note exists
        expect(async () => {
            await escrow
                .withWallet(bob)
                .methods.get_definition()
                .simulate();
        }).toThrow()

        // add account to bob pxe
        await pxe[1].registerAccount(escrowKey, await escrow.partialAddress);
        await pxe[1].registerContract(escrow);
        await escrow.withWallet(bob).methods.sync_private_state().simulate();
        const bobDefinition = await escrow
            .withWallet(bob)
            .methods.get_definition()
            .simulate();
        // expect(bobDefinition.owner).toEqual(escrow.address.toBigInt());
        expect(bobDefinition.owner).not.toEqual(0n);
    });

    test("e2e", async () => {
        // notes are owned by the deploying account
        ({ contract: escrow, secretKey: escrowKey } = await deployEscrowContract(
            pxe[0],
            alice,
            usdc.address,
            wad(1000n, 6n),
            weth.address,
            wad(1n),
        ));

        // get maker secret value
        const makerSecret = await escrow.methods.get_maker_secret().simulate();

        // check balances before
        let aliceUSDCBalance = await usdc.methods.balance_of_private(alice.getAddress()).simulate();
        let contractUSDCBalance = await usdc.methods.balance_of_private(escrow.address).simulate();
        expect(aliceUSDCBalance).toEqual(wad(10000n, 6n));
        expect(contractUSDCBalance).toEqual(0n);

        // deposit tokens into the escrow
        await depositToEscrow(
            escrow,
            alice,
            usdc,
            wad(1000n, 6n),
            makerSecret
        );

        // check USDC balances after transfer in
        aliceUSDCBalance = await usdc.methods.balance_of_private(alice.getAddress()).simulate();
        contractUSDCBalance = await usdc.methods.balance_of_private(escrow.address).simulate();
        expect(aliceUSDCBalance).toEqual(wad(9000n, 6n));
        expect(contractUSDCBalance).toEqual(wad(1000n, 6n));

        // check Bob balance balances before filling order
        let bobWethBalance = await weth.withWallet(bob).methods.balance_of_private(bob.getAddress()).simulate();
        let bobUSDCBalance = await usdc.withWallet(bob).methods.balance_of_private(bob.getAddress()).simulate();
        let contractWethBalance = await weth.withWallet(bob).methods.balance_of_private(escrow.address).simulate();
        expect(bobWethBalance).toEqual(wad(4n));
        expect(bobUSDCBalance).toEqual(0n);
        expect(contractWethBalance).toEqual(0n);

        // give bob knowledge of the escrow
        await pxe[1].registerAccount(escrowKey, await escrow.partialAddress);
        await pxe[1].registerContract(escrow);
        await escrow.withWallet(bob).methods.sync_private_state().simulate();

        // transfer tokens back out
        await fillOTCOrder(escrow, bob, weth, wad(1n));

        // check balances after filling order
        bobWethBalance = await weth.withWallet(bob).methods.balance_of_private(bob.getAddress()).simulate();
        bobUSDCBalance = await usdc.withWallet(bob).methods.balance_of_private(bob.getAddress()).simulate();
        contractUSDCBalance = await usdc.withWallet(bob).methods.balance_of_private(escrow.address).simulate();
        contractWethBalance = await weth.withWallet(bob).methods.balance_of_private(escrow.address).simulate();
        expect(bobWethBalance).toEqual(wad(3n));
        expect(bobUSDCBalance).toEqual(wad(1000n, 6n));
        expect(contractWethBalance).toEqual(wad(1n));
        expect(contractUSDCBalance).toEqual(0n);

        await escrow.withWallet(alice).methods.finalize_order(makerSecret).send().wait();
        let aliceBalanceWeth = await weth.withWallet(alice).methods.balance_of_private(alice.getAddress()).simulate();
        contractWethBalance = await weth.withWallet(alice).methods.balance_of_private(escrow.address).simulate();
        expect(aliceBalanceWeth).toEqual(wad(1n));
        expect(contractWethBalance).toEqual(0n);
    });

    

});
