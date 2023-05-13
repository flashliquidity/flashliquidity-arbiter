import "@nomiclabs/hardhat-waffle"
import "@nomiclabs/hardhat-etherscan"
import "@nomiclabs/hardhat-ethers"
import "hardhat-deploy"
import "hardhat-deploy-ethers"
import "hardhat-gas-reporter"
import "dotenv/config"
import { HardhatUserConfig } from "hardhat/config"

const MAINNET_RPC = "https://polygon-rpc.com"
const MUMBAI_RPC = "https://matic-mumbai.chainstacklabs.com/"

const config: HardhatUserConfig = {
    etherscan: {
        apiKey: process.env.POLYGONSCAN_API_KEY,
    },
    networks: {
        hardhat: {
            forking: {
                // eslint-disable-next-line
                enabled: true,
                url: process.env.ALCHEMY_MAINNET_RPC_URL,
                blockNumber: 42069420,
            },
        },
        matic: {
            url: MAINNET_RPC,
            chainId: 137,
            live: true,
            saveDeployments: true,
            accounts: [process.env.PRIVATE_KEY],
        },
        mumbai: {
            url: MUMBAI_RPC,
            chainId: 80001,
            live: true,
            saveDeployments: true,
            gasMultiplier: 2,
            accounts: [process.env.PRIVATE_KEY],
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
                runs: 1000000,
            },
        },
    },
}

export default config
