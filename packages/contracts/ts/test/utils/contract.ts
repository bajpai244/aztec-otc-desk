import {
    AccountWallet,
    Contract,
    AztecAddress,
    Fr,
    deriveKeys,
    PXE,
    DeployOptions,
} from "@aztec/aztec.js";
import { computePartialAddress } from "@aztec/stdlib/contract";
import {
    OTCEscrowContractContract as OTCEscrowContract,
    OTCEscrowContractContractArtifact as OTCEscrowContractArtifact
} from "../../../artifacts/OTCEscrowContract.js";
import {
    TokenContract,
    TokenContractArtifact
} from "../../../artifacts/Token.js";

/**
 * Deploys a new instance of the OTC Escrow Contract
 * @dev ensures contract is built with known encryption keys and adds to deployer PXE
 * 
 * @param pxe - the PXE of the deploying account
 * @param deployer - the account deploying the OTC Escrow Contract (the maker)
 * @param offerTokenAddress - the address of the token being offered / sold by the maker
 * @param offerTokenAmount - quantity of offerToken the maker wants to sell
 * @param askTokenAddress - the address of the token being asked for/ bought by the maker
 * @param askTokenAmount - quantity of askToken the maker wants to buy
 * @param deployOptions - Aztec contract deployment options (optional)
 * @returns
 *          contract - the deployed OTC Escrow Contract
 *          secretKey - the master key for the contract
 */
export async function deployEscrowContract(
    pxe: PXE,
    deployer: AccountWallet,
    offerTokenAddress: AztecAddress,
    offerTokenAmount: bigint,
    askTokenAddress: AztecAddress,
    askTokenAmount: bigint,
    deployOptions?: DeployOptions,
): Promise<{ contract: OTCEscrowContract, secretKey: Fr }> {

    // get keys for contract
    const contractSecretKey = Fr.random();
    const contractPublicKeys = (await deriveKeys(contractSecretKey)).publicKeys;

    // set up contract deployment tx
    const contractDeployment = await Contract.deployWithPublicKeys(
        contractPublicKeys,
        deployer,
        OTCEscrowContractArtifact,
        [offerTokenAddress, offerTokenAmount, askTokenAddress, askTokenAmount],
    );

    // add contract decryption keys to PXE
    const partialAddress = await computePartialAddress(
        await contractDeployment.getInstance(),
    );
    await pxe.registerAccount(contractSecretKey, partialAddress);

    // deploy contract
    const contract = await contractDeployment.send(deployOptions).deployed();

    return {
        contract: contract as OTCEscrowContract,
        secretKey: contractSecretKey,
    };
}

/**
 * Deploys a new instance of Defi-Wonderland's Fungible Token Contract
 * @param tokenMetadata - the name, symbol, and decimals of the token
 * @param deployer - the account deploying the token contract (gets minter rights)
 * @param deployOptions - Aztec contract deployment options (optional)
 * @returns - the deployed Token Contract
 */
export async function deployTokenContractWithMinter(
    tokenMetadata: { name: string; symbol: string; decimals: number },
    deployer: AccountWallet,
    deployOptions?: DeployOptions,
): Promise<TokenContract> {
    const contract = await Contract.deploy(
        deployer,
        TokenContractArtifact,
        [
            tokenMetadata.name,
            tokenMetadata.symbol,
            tokenMetadata.decimals,
            deployer.getAddress(),
            AztecAddress.ZERO,
        ],
        "constructor_with_minter",
    )
        .send(deployOptions)
        .deployed();
    return contract as TokenContract;
}

/**
 * Deposit tokens into the escrow contract so that the taker can fill the order
 * @param escrow - the escrow contract to deposit into
 * @param caller - the maker who is selling tokens
 * @param token - the contract instance of the token being sold by the maker
 * @param amount - the amount of tokens to transfer in
 * @param makerSecret - the secret used to privately authorize maker actions
 *                      if not supplied, will retrieve from storage
 */
export async function depositToEscrow(
    escrow: OTCEscrowContract,
    caller: AccountWallet,
    token: TokenContract,
    amount: bigint,
    makerSecret?: Fr
) {
    escrow = escrow.withWallet(caller);
    if (makerSecret === undefined) {
        makerSecret = await escrow.methods.get_maker_secret().simulate();
    }
    const nonce = Fr.random();
    const authwit = await caller.createAuthWit({
        caller: escrow.address,
        action: token.methods.transfer_private_to_private(
            caller.getAddress(),
            escrow.address,
            amount,
            nonce,
        ),
    });
    /// send transfer_in with authwit
    await escrow
        .methods
        .deposit_tokens(makerSecret!, nonce)
        .with({ authWitnesses: [authwit] })
        .send()
        .wait()
}

/**
 * Deposit tokens into the escrow contract so that the taker can fill the order
 * @param escrow - the escrow contract to deposit into
 * @param caller - the taker who is buying tokens / filling the order
 * @param token - the contract instance of the token being bought by the maker (sold by the taker)
 * @param amount - the amount of tokens to transfer in
 */
export async function fillOTCOrder(
    escrow: OTCEscrowContract,
    caller: AccountWallet,
    token: TokenContract,
    amount: bigint,
) {
    escrow = escrow.withWallet(caller);
    
    const nonce = Fr.random();
    const authwit = await caller.createAuthWit({
        caller: escrow.address,
        action: token.withWallet(caller).methods.transfer_private_to_private(
            caller.getAddress(),
            escrow.address,
            amount,
            nonce,
        ),
    });
    /// send transfer_in with authwit
    await escrow
        .methods
        .fill_order(nonce)
        .with({ authWitnesses: [authwit] })
        .send()
        .wait()
}