import "@nomiclabs/hardhat-waffle"
import "@nomiclabs/hardhat-etherscan"
import "@nomiclabs/hardhat-ethers"
import "hardhat-deploy"
import "hardhat-deploy-ethers"
import "dotenv/config"
import importToml from "import-toml"
import { HardhatUserConfig } from "hardhat/config"

const foundryConfig = importToml.sync("foundry.toml")

const PRIVATE_KEY = process.env.PRIVATE_KEY
const ETHEREUM_RPC = "https://eth.llamarpc.com" || process.env.ETHEREUM_RPC
const ETHEREUM_SEPOLIA_RPC = "https://rpc.sepolia.org" || process.env.ETHEREUM_SEPOLIA_RPC
const BASE_RPC = "https://mainnet.base.org" || process.env.BASE_RPC
const BASE_GOERLI_RPC = "https://goerli.base.org" || process.env.BASE_GOERLI_RPC
const POLYGON_MAINNET_RPC = "https://rpc-mainnet.maticvigil.com" || process.env.POLYGON_MAINNET_RPC
const POLYGON_MUMBAI_RPC = "https://rpc-mumbai.maticvigil.com/" || process.env.POLYGON_MUMBAI_RPC
const POLYGON_ZKEVM_TESTNET_RPC = "https://rpc.public.zkevm-test.net" || process.env.POLYGON_ZKEVM_TESTNET_RPC
const POLYGON_ZKEVM_RPC = "https://zkevm-rpc.com" || process.env.POLYGON_ZKEVM_RPC
const AVALANCHE_C_CHAIN_RPC = "https://api.avax.network/ext/bc/C/rpc" || process.env.AVALANCHE_C_CHAIN_RPC
const AVALANCHE_FUJI_RPC = "https://api.avax-test.network/ext/bc/C/rpc" || process.env.AVALANCHE_FUJI_RPC
const ARBITRUM_ONE_RPC = "https://arb1.arbitrum.io/rpc" || process.env.ARBITRUM_ONE_RPC
const ARBITRUM_SEPOLIA_RPC = "https://sepolia-rollup.arbitrum.io/rpc" || process.env.ARBITRUM_TESTNET_RPC

const config: HardhatUserConfig = {
    etherscan: {
        apiKey: {
            mainnet: process.env.ETHERSCAN_API_KEY,
            sepolia: process.env.ETHERSCAN_API_KEY,
            polygon: process.env.POLYGONSCAN_API_KEY,
            polygonMumbai: process.env.POLYGONSCAN_API_KEY,
            zkevm: process.env.ZKEVMSCAN_API_KEY,
            zkevm_testnet: process.env.ZKEVMSCAN_API_KEY,
            base: process.env.BASESCAN_API_KEY,
            base_goerli: process.env.BASESCAN_API_KEY,
            avalanche: process.env.SNOWTRACE_API_KEY,
            avalancheFujiTestnet: process.env.SNOWTRACE_API_KEY,
            arbitrum: process.env.ARBISCAN_API_KEY,
            arbitrum_sepolia: process.env.ARBISCAN_API_KEY
        },
        customChains: [

            {
                network: "base",
                chainId: 8453,
                urls: {
                    apiURL: "https://api.basescan.org/api",
                    browserURL: "https://basescan.org"
                }
            },
            {
                network: "base_goerli",
                chainId: 84531,
                urls: {
                    apiURL: "https://api-goerli.basescan.org/api",
                    browserURL: "https://goerli.basescan.org"
                }
            },
            {
                network: "zkevm",
                chainId: 1101,
                urls: {
                    apiURL: "https://api-zkevm.polygonscan.com/api",
                    browserURL: "https://zkevm.polygonscan.com/"
                }
            },
            {
                network: "zkevm_testnet",
                chainId: 1442,
                urls: {
                    apiURL: "https://api-zkevm.polygonscan.com/api",
                    browserURL: "https://zkevm.polygonscan.com/"
                }
            }
        ]
    },
    networks: {
        ethereum: {
            url: ETHEREUM_RPC,
            chainId: 1,
            live: true,
            saveDeployments: true,
            accounts: [PRIVATE_KEY],
        },
        sepolia: {
            url: ETHEREUM_SEPOLIA_RPC,
            chainId: 11155111,
            live: true,
            saveDeployments: true,
            gasMultiplier: 2,
            accounts: [PRIVATE_KEY],
        },
        base: {
            url: BASE_RPC,
            chainId: 8453,
            live: true,
            saveDeployments: true,
            accounts: [PRIVATE_KEY],
        },
        base_goerli: {
            url: BASE_GOERLI_RPC,
            chainId: 84531,
            live: true,
            saveDeployments: true,
            gasMultiplier: 3,
            accounts: [PRIVATE_KEY],
        },
        polygon: {
            url: POLYGON_MAINNET_RPC,
            chainId: 137,
            live: true,
            saveDeployments: true,
            accounts: [PRIVATE_KEY],
        },
        mumbai: {
            url: POLYGON_MUMBAI_RPC,
            chainId: 80001,
            live: true,
            saveDeployments: true,
            gasMultiplier: 2,
            accounts: [PRIVATE_KEY],
        },
        avalanche: {
            url: AVALANCHE_C_CHAIN_RPC,
            chainId: 43114,
            live: true,
            saveDeployments: true,
            accounts: [PRIVATE_KEY],
        },
        fuji: {
            url: AVALANCHE_FUJI_RPC,
            chainId: 43113,
            live: true,
            saveDeployments: true,
            gasMultiplier: 2,
            accounts: [PRIVATE_KEY],
        },
        zkevm: {
            url: POLYGON_ZKEVM_RPC,
            chainId: 1101,
            live: true,
            saveDeployments: true,
            accounts: [PRIVATE_KEY],
        },
        zkevm_testnet: {
            url: POLYGON_ZKEVM_TESTNET_RPC,
            chainId: 1442,
            live: true,
            saveDeployments: true,
            gasMultiplier: 2,
            accounts: [PRIVATE_KEY],
        },
        arbitrum: {
            url: ARBITRUM_ONE_RPC,
            chainId: 42161,
            live: true,
            saveDeployments: true,
            accounts: [PRIVATE_KEY],
        },
        arbitrum_sepolia: {
            url: ARBITRUM_SEPOLIA_RPC,
            chainId: 421614,
            live: true,
            saveDeployments: true,
            gasMultiplier: 2,
            accounts: [PRIVATE_KEY],
        },
    },
    solidity: {
        version: foundryConfig.profile.default.solc_version,
        settings: {
            viaIR: foundryConfig.profile.default.via_ir,
            optimizer: {
                enabled: true,
                runs: foundryConfig.profile.default.optimizer_runs,
            },
        },
    },
}

export default config
