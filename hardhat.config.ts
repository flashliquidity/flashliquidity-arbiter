import "@nomiclabs/hardhat-waffle"
import "@nomiclabs/hardhat-etherscan"
import "@nomiclabs/hardhat-ethers"
import "hardhat-deploy"
import "hardhat-deploy-ethers"
import "dotenv/config"
import "hardhat-gas-reporter"
import { HardhatUserConfig } from "hardhat/config"

const MAINNET_RPC = "https://rpc-mainnet.maticvigil.com"
const MUMBAI_RPC = "https://rpc-mumbai.maticvigil.com/"
const PRIVATE_KEY = process.env.PRIVATE_KEY || "private key"
const POLYGONSCAN_API_KEY = process.env.POLYGONSCAN_API_KEY || "api key"
const ALCHEMY_MAINNET_RPC_URL = process.env.ALCHEMY_MAINNET_RPC_URL || "alchemy rpc"
const ALCHEMY_MUMBAI_RPC_URL = process.env.ALCHEMY_MUMBAI_RPC_URL || "alchemy rpc"

const config: HardhatUserConfig = {
    etherscan: {
        apiKey: POLYGONSCAN_API_KEY,
    },
    networks: {
        hardhat: {
            forking: {
                // eslint-disable-next-line
                enabled: true,
                url: ALCHEMY_MAINNET_RPC_URL,
                blockNumber: 38905600,
            },
        },
        matic: {
            url: MAINNET_RPC,
            chainId: 137,
            live: true,
            saveDeployments: true,
            accounts: [PRIVATE_KEY],
        },
        mumbai: {
            url: MUMBAI_RPC,
            chainId: 80001,
            live: true,
            saveDeployments: true,
            gasMultiplier: 2,
            accounts: [PRIVATE_KEY],
        },
    },
    gasReporter: {
        enabled: true,
        currency: "USD",
        outputFile: "gas-report.txt",
        noColors: true,
        // coinmarketcap: process.env.COINMARKETCAP_API_KEY,
    },
    solidity: {
        version: "0.8.17",
        settings: {
            optimizer: {
                enabled: true,
                runs: 1000,
            },
        },
    },
}

export default config
