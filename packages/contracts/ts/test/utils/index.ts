import {
    waitForPXE,
    createPXEClient,
} from "@aztec/aztec.js";

export const TOKEN_METADATA = {
    usdc: { name: "USDC Token", symbol: "USDC", decimals: 6 },
    weth: { name: "Wrapped Ether", symbol: "WETH", decimals: 18 }
}

export const createPXE = async (id: number = 0) => {
    const { BASE_PXE_URL = `http://localhost` } = process.env;
    const url = `${BASE_PXE_URL}:${8080 + id}`;
    const pxe = createPXEClient(url);
    await waitForPXE(pxe);
    return pxe;
};

export const setupSandbox = async () => {
    return createPXE();
};

export const wad = (n: bigint = 1n, decimals: bigint = 18n) =>
    n * 10n ** decimals;

export * from "./fees.js";
export * from "./contract.js"
